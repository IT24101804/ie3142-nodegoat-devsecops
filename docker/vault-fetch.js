#!/usr/bin/env node
"use strict";

/**
 * Fetch application secrets from HashiCorp Vault using AppRole authentication.
 *
 * Run by docker/entrypoint.sh before the application starts. Writes shell
 * export statements to /tmp/vault-env.sh, which the entrypoint then sources.
 *
 * DESIGN RULES
 *
 * 1. NEVER FATAL. Vault is an additive source of secrets, not a dependency of
 *    the stack. If Vault is absent, unreachable, or misconfigured, this script
 *    logs the reason, writes an empty file and exits 0. The application then
 *    falls back to environment-provided values (see config/env/all.js), which
 *    in turn fall back to a generated ephemeral key. A secrets manager that can
 *    take the application down is a worse outcome than one that is optional.
 *
 * 2. NEVER LOG A SECRET VALUE. Only metadata - token TTL, granted policies,
 *    how many keys were retrieved. Container logs are a disclosure channel.
 *
 * 3. NO NEW DEPENDENCIES. Uses Node 20's global fetch rather than node-vault or
 *    curl, so the runtime image is unchanged and the production dependency tree
 *    is not expanded for an infrastructure concern.
 */

const fs = require("fs");

const VAULT_ADDR = process.env.VAULT_ADDR;
const APPROLE_DIR = process.env.VAULT_APPROLE_DIR || "/vault/approle";
const ROLE_ID_PATH = `${APPROLE_DIR}/role_id`;
const SECRET_ID_PATH = `${APPROLE_DIR}/secret_id`;
const SECRET_PATH = process.env.VAULT_SECRET_PATH || "secret/data/nodegoat";
const OUT_PATH = "/tmp/vault-env.sh";
const TIMEOUT_MS = 5000;

// Map Vault KV field names to the environment variables the app reads.
const FIELD_TO_ENV = {
    session_secret: "SESSION_SECRET",
    crypto_key: "CRYPTO_KEY"
};

const finish = (message, lines) => {
    "use strict";
    const content = (lines && lines.length) ? `${lines.join("\n")}\n` : "";
    fs.writeFileSync(OUT_PATH, content, { mode: 0o600 });
    console.log(`[vault] ${message}`);
    process.exit(0);
};

const skip = (reason) => {
    "use strict";
    console.log(`[vault] ${reason}`);
    finish("Falling back to environment-provided secrets.", []);
};

const request = async (url, options) => {
    "use strict";
    return fetch(url, { ...options, signal: AbortSignal.timeout(TIMEOUT_MS) });
};

const main = async () => {
    "use strict";

    if (!VAULT_ADDR) {
        return skip("VAULT_ADDR is not set - Vault integration is disabled.");
    }
    if (!fs.existsSync(ROLE_ID_PATH) || !fs.existsSync(SECRET_ID_PATH)) {
        return skip(`AppRole credentials not found in ${APPROLE_DIR} - provisioning did not run.`);
    }

    const roleId = fs.readFileSync(ROLE_ID_PATH, "utf8").trim();
    const secretId = fs.readFileSync(SECRET_ID_PATH, "utf8").trim();
    if (!roleId || !secretId) {
        return skip("AppRole credential files are empty.");
    }

    // --- Authenticate -------------------------------------------------------
    const loginResponse = await request(`${VAULT_ADDR}/v1/auth/approle/login`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ role_id: roleId, secret_id: secretId })
    });

    if (!loginResponse.ok) {
        return skip(`AppRole login failed (HTTP ${loginResponse.status}).`);
    }

    const login = await loginResponse.json();
    const auth = login.auth || {};
    const token = auth.client_token;
    if (!token) {
        return skip("AppRole login returned no client token.");
    }

    console.log(`[vault] AppRole login succeeded as role_id ${roleId}`);
    console.log(`[vault] token TTL ${auth.lease_duration}s, renewable=${auth.renewable}, policies: ${(auth.token_policies || []).join(", ")}`);

    // --- Read the secret ----------------------------------------------------
    const readResponse = await request(`${VAULT_ADDR}/v1/${SECRET_PATH}`, {
        headers: { "x-vault-token": token }
    });

    if (!readResponse.ok) {
        return skip(`Reading ${SECRET_PATH} failed (HTTP ${readResponse.status}).`);
    }

    const payload = await readResponse.json();
    const data = (payload.data && payload.data.data) || {};

    const lines = [];
    const names = [];
    for (const field of Object.keys(FIELD_TO_ENV)) {
        const value = data[field];
        if (typeof value === "string" && value.length > 0) {
            // Single quotes, and any embedded quote is escaped, so a value can
            // never break out of the assignment when the file is sourced.
            const escaped = value.replace(/'/g, "'\\''");
            lines.push(`export ${FIELD_TO_ENV[field]}='${escaped}'`);
            names.push(FIELD_TO_ENV[field]);
        }
    }

    if (!lines.length) {
        return skip(`No usable fields found at ${SECRET_PATH}.`);
    }

    return finish(`Retrieved ${lines.length} secret(s) from ${SECRET_PATH}: ${names.join(", ")} (values not logged).`, lines);
};

main().catch((err) => {
    "use strict";
    skip(`Vault unreachable or errored: ${err.message}`);
});
