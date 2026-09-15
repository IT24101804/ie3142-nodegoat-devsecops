const _ = require("underscore");
const path = require("path");
const util = require("util");

const finalEnv = process.env.NODE_ENV || "development";

const allConf = require(path.resolve(__dirname + "/../config/env/all.js"));
const envConf = require(path.resolve(__dirname + "/../config/env/" + finalEnv.toLowerCase() + ".js")) || {};

const config = { ...allConf, ...envConf };

// ---------------------------------------------------------------------------
// Keys whose values must never reach the logs.
//
// The startup config dump is useful for debugging (the README troubleshooting
// section refers to it), but container logs are shipped, aggregated and shared,
// so printing a signing key there undoes the work of provisioning it from the
// environment in the first place. The structure is still logged; only the
// sensitive values are masked.
// ---------------------------------------------------------------------------
const SECRET_KEYS = ["cookieSecret", "cryptoKey", "zapApiKey"];

const redactSecrets = (source) => {
    "use strict";
    const copy = { ...source };
    for (const key of SECRET_KEYS) {
        if (copy[key]) {
            copy[key] = "***REDACTED***";
        }
    }
    return copy;
};

console.log(`Current Config:`);
console.log(util.inspect(redactSecrets(config), false, null));

module.exports = config;
