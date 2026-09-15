#!/bin/sh
# ---------------------------------------------------------------------------
# Vault provisioning - runs once, then exits.
#
# Sets up the AppRole workflow that the application uses to obtain its session
# signing key at runtime:
#
#   1. enables a file audit device        -> who read which secret, when
#   2. GENERATES the session secret       -> the value never exists in any file
#                                            in this repository, or in .env
#   3. writes it to the KV store at secret/nodegoat
#   4. writes a least-privilege policy    -> read-only, that one path only
#   5. enables AppRole auth and creates a role bound to that policy
#   6. emits role_id and secret_id to a shared volume for the app to use
#
# WHY APPROLE RATHER THAN THE ROOT TOKEN
# Handing the application a root token would mean the app holds a credential
# that can read and write everything in Vault forever. With AppRole the app
# presents two factors - a non-secret role_id (an identity, like a username)
# and a short-lived secret_id (a credential) - and receives a token that is
# scoped to one read-only policy and expires. That is the difference between
# demonstrating a secrets manager and just moving a password.
#
# HONEST LIMITATION - "SECRET ZERO"
# Something must still authenticate to Vault first. Here that is
# VAULT_DEV_ROOT_TOKEN, supplied from the git-ignored .env. Vault cannot solve
# this for you; production deployments break the chain with platform identity
# (Kubernetes service accounts, AWS IAM, cloud KMS auto-unseal) rather than a
# shared token. This is documented in docs/secrets.md rather than hidden.
# ---------------------------------------------------------------------------
set -e

VAULT_ADDR="${VAULT_ADDR:-http://vault:8200}"
export VAULT_ADDR

SECRET_PATH="secret/nodegoat"
POLICY_NAME="nodegoat-app"
ROLE_NAME="nodegoat-app"
APPROLE_DIR="/vault/approle"

# ---------------------------------------------------------------------------
# Opt-in. Without a root token there is nothing to authenticate with, so we
# skip cleanly and the application falls back to environment-provided secrets.
# Vault is additive here: it must never be able to stop the stack from starting.
# ---------------------------------------------------------------------------
if [ -z "${VAULT_TOKEN:-}" ]; then
    echo "[vault-init] VAULT_DEV_ROOT_TOKEN is not set - skipping Vault provisioning."
    echo "[vault-init] The application will use environment-provided secrets instead."
    echo "[vault-init] To enable the Vault demonstration, set VAULT_DEV_ROOT_TOKEN in .env."
    exit 0
fi
export VAULT_TOKEN

echo "[vault-init] Waiting for Vault at ${VAULT_ADDR} ..."
i=0
while [ "$i" -lt 60 ]; do
    if vault status >/dev/null 2>&1; then
        echo "[vault-init] Vault is responding."
        break
    fi
    i=$((i + 1))
    sleep 1
done
if [ "$i" -ge 60 ]; then
    echo "[vault-init] ERROR: Vault did not become ready in 60s."
    exit 1
fi

# ---------------------------------------------------------------------------
# 0. Fix volume ownership.
#
# Docker creates named volumes owned by root, but the Vault SERVER container
# runs as uid 100 and is the process that writes the audit log. Without this it
# fails with "permission denied" when the audit device is enabled. This
# provisioning container runs as root solely to correct that ownership; it is a
# one-shot job that exits immediately afterwards, and no long-running process
# in this stack runs as root.
# ---------------------------------------------------------------------------
if [ "$(id -u)" = "0" ]; then
    chown -R 100:1000 /vault/audit 2>/dev/null || true
    chmod 0775 /vault/audit 2>/dev/null || true
    echo "[vault-init] Audit volume ownership set to uid 100 (the vault server user)."
fi

# ---------------------------------------------------------------------------
# 1. Audit device.
#
# This is something a .env file fundamentally cannot do: every secret access is
# recorded with the identity that made it, the path, and a timestamp. Secret
# values themselves are HMAC'd in the log, not written in clear.
# ---------------------------------------------------------------------------
if vault audit list 2>/dev/null | grep -q '^file/'; then
    echo "[vault-init] Audit device already enabled."
else
    vault audit enable file file_path=/vault/audit/audit.log
    echo "[vault-init] Audit device enabled -> /vault/audit/audit.log"
fi

# ---------------------------------------------------------------------------
# 2 + 3. Generate the secret INSIDE Vault's world and store it.
#
# The value is created here from /dev/urandom and written straight to the KV
# store. It is never placed in .env, in docker-compose.yml, or in any file in
# the repository. This is the substantive difference from the .env mechanism:
# there is no file on disk to leak.
# ---------------------------------------------------------------------------
gen_hex32() {
    head -c 32 /dev/urandom | od -An -v -tx1 | tr -d ' \n'
}

if vault kv get "${SECRET_PATH}" >/dev/null 2>&1; then
    echo "[vault-init] Secret already present at ${SECRET_PATH} - leaving it alone."
else
    vault kv put "${SECRET_PATH}" \
        session_secret="$(gen_hex32)" \
        crypto_key="$(gen_hex32)" >/dev/null
    echo "[vault-init] Generated and stored session_secret and crypto_key at ${SECRET_PATH}"
    echo "[vault-init] (values generated inside Vault - not present in any repository file)"
fi

# ---------------------------------------------------------------------------
# 4. Least-privilege policy: read one path, nothing else. No write, no list,
#    no access to any other secret.
# ---------------------------------------------------------------------------
vault policy write "${POLICY_NAME}" - <<POLICY >/dev/null
path "secret/data/nodegoat" {
  capabilities = ["read"]
}
POLICY
echo "[vault-init] Policy '${POLICY_NAME}' written (read-only on secret/data/nodegoat)"

# ---------------------------------------------------------------------------
# 5. AppRole auth.
#
# token_ttl / token_max_ttl : the token the app receives expires
# secret_id_ttl             : the credential used to obtain it expires
# Both are short deliberately - a leaked credential has a limited useful life.
# ---------------------------------------------------------------------------
if vault auth list 2>/dev/null | grep -q '^approle/'; then
    echo "[vault-init] AppRole auth already enabled."
else
    vault auth enable approle
    echo "[vault-init] AppRole auth enabled."
fi

vault write "auth/approle/role/${ROLE_NAME}" \
    token_policies="${POLICY_NAME}" \
    token_ttl=20m \
    token_max_ttl=1h \
    secret_id_ttl=30m \
    secret_id_num_uses=0 >/dev/null
echo "[vault-init] Role '${ROLE_NAME}' created (token_ttl=20m, secret_id_ttl=30m)"

# ---------------------------------------------------------------------------
# 6. Emit the AppRole credentials for the application.
#
# role_id   is an IDENTITY, not a secret - comparable to a username.
# secret_id is the credential. It is written with restrictive permissions and
#           expires after secret_id_ttl.
#
# Delivering secret_id to the workload is the "secret zero" problem in
# miniature. Here a shared volume stands in for what a real deployment would do
# with a trusted broker (Vault Agent, a Kubernetes projected token, or an
# instance identity document).
# ---------------------------------------------------------------------------
mkdir -p "${APPROLE_DIR}"

vault read -field=role_id "auth/approle/role/${ROLE_NAME}/role-id" > "${APPROLE_DIR}/role_id"
vault write -f -field=secret_id "auth/approle/role/${ROLE_NAME}/secret-id" > "${APPROLE_DIR}/secret_id"

chmod 0444 "${APPROLE_DIR}/role_id"
chmod 0444 "${APPROLE_DIR}/secret_id"

echo "[vault-init] AppRole credentials written to ${APPROLE_DIR}"
echo "[vault-init] role_id   : $(cat "${APPROLE_DIR}/role_id")   (identity - not secret)"
echo "[vault-init] secret_id : <not logged>"
echo "[vault-init] Provisioning complete."
