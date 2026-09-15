// default app configuration
const crypto = require("crypto");

const port = process.env.PORT || 4000;
let db = process.env.MONGODB_URI || "mongodb://localhost:27017/nodegoat";

// ---------------------------------------------------------------------------
// Secrets are provisioned from the environment - see .env.example and
// docs/secrets.md. They are deliberately NOT given hardcoded fallback values.
//
// When a variable is absent we generate a random value for this process rather
// than falling back to a literal. A missing environment variable must never
// silently produce a predictable secret, which is exactly what the previous
// hardcoded defaults did. The trade-off is that sessions do not survive a
// container restart unless SESSION_SECRET is set, which is the safer default.
// ---------------------------------------------------------------------------
const generateEphemeralKey = (name) => {
    "use strict";
    const value = crypto.randomBytes(32).toString("hex");
    console.warn(`[config] ${name} is not set - generated an ephemeral random value for this process.`);
    console.warn(`[config] Set ${name} in .env for a stable key. See .env.example.`);
    return value;
};

// Signing key for express-session cookies (server.js). If this is predictable,
// session cookies can be forged.
const cookieSecret = process.env.SESSION_SECRET || generateEphemeralKey("SESSION_SECRET");

// Key for the AES encryption of profile data.
// NOTE: the code that consumes this is currently commented out in
// app/data/profile-dao.js (the disabled "Fix for A6"), so this value is inert
// today. It is provisioned from the environment anyway so that enabling that
// fix does not require reintroducing a hardcoded key.
const cryptoKey = process.env.CRYPTO_KEY || generateEphemeralKey("CRYPTO_KEY");

module.exports = {
    port,
    db,
    cookieSecret,
    cryptoKey,
    cryptoAlgo: "aes256",
    hostName: "localhost",
    environmentalScripts: []
};
