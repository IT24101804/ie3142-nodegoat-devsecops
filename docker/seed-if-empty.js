#!/usr/bin/env node
"use strict";

/**
 * Conditional database seeder.
 *
 * Connects to MongoDB and counts documents in the `users` collection.
 *   - empty  -> delegates to artifacts/db-reset.js (upstream's seeder, unmodified)
 *   - seeded -> exits without touching any data
 *
 * This file is infrastructure, not application code. artifacts/db-reset.js is
 * left exactly as OWASP ships it so that it remains usable as the explicit
 * "reset the database" command documented in the README.
 *
 * Also retries the initial connection. docker-compose already gates startup on
 * the mongo healthcheck, so this is belt-and-braces for slow machines rather
 * than the primary ordering mechanism.
 */

const path = require("path");
const { execFileSync } = require("child_process");
const { MongoClient } = require("mongodb");
const { db: mongoUri } = require("../config/config");

const RESET_SCRIPT = path.resolve(__dirname, "../artifacts/db-reset.js");
const MAX_ATTEMPTS = 30;
const RETRY_DELAY_MS = 2000;

const runReset = () => {
    console.log("[seed] Database is empty - running artifacts/db-reset.js");
    // stdio: inherit so the seeder's own output appears in `docker compose logs`.
    execFileSync(process.execPath, [RESET_SCRIPT], { stdio: "inherit" });
    console.log("[seed] Seeding complete.");
};

const attemptConnect = (attempt) => {
    MongoClient.connect(mongoUri, (err, db) => {
        if (err) {
            if (attempt >= MAX_ATTEMPTS) {
                console.error(`[seed] Could not reach MongoDB after ${MAX_ATTEMPTS} attempts.`);
                console.error(err.message);
                process.exit(1);
            }
            console.log(`[seed] MongoDB not ready (attempt ${attempt}/${MAX_ATTEMPTS}), retrying in ${RETRY_DELAY_MS}ms...`);
            setTimeout(() => attemptConnect(attempt + 1), RETRY_DELAY_MS);
            return;
        }

        db.collection("users").count((countErr, count) => {
            if (countErr) {
                console.error("[seed] Failed to count users collection:", countErr.message);
                db.close();
                process.exit(1);
            }

            db.close();

            if (count > 0) {
                console.log(`[seed] Database already contains ${count} user(s) - skipping seed.`);
                process.exit(0);
            }

            try {
                runReset();
                process.exit(0);
            } catch (resetErr) {
                console.error("[seed] db-reset.js failed:", resetErr.message);
                process.exit(1);
            }
        });
    });
};

console.log(`[seed] Target database: ${mongoUri}`);
attemptConnect(1);
