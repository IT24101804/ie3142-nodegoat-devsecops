"use strict";

const bcrypt = require("bcrypt-nodejs");
const MongoClient = require("mongodb").MongoClient;
const databaseUrl = require("../config/config").db;
const hashPattern = /^\$2a\$(?:0[4-9]|[12]\d|3[01])\$[./A-Za-z0-9]{53}$/;

async function migrate() {
    const db = await MongoClient.connect(databaseUrl);

    try {
        const users = db.collection("users");
        const records = await users.find({}, { password: 1 }).toArray();

        // Check every record before changing anything.
        for (const user of records) {
            if (hashPattern.test(user.password)) continue;

            if (
                typeof user.password !== "string" ||
                user.password.length === 0 ||
                user.password.includes("\0") ||
                Buffer.byteLength(user.password, "utf8") > 72 ||
                /^\$2/.test(user.password)
            ) {
                throw new Error("Unsupported stored password format.");
            }
        }

        let converted = 0;

        for (const user of records) {
            // Preserve passwords that are already bcrypt hashes.
            if (hashPattern.test(user.password)) continue;

            const hash = bcrypt.hashSync(
                user.password,
                bcrypt.genSaltSync(12)
            );

            const result = await users.updateOne(
                { _id: user._id, password: user.password },
                { $set: { password: hash } }
            );

            const matched = result.matchedCount !== undefined
                ? result.matchedCount
                : result.result.n;

            if (matched !== 1) {
                throw new Error("A password changed during migration.");
            }

            converted += 1;
        }

        console.log("Passwords converted: " + converted);
        console.log("Existing bcrypt hashes were preserved.");
    } finally {
        await db.close();
    }
}

migrate().catch(() => {
    console.error("Migration failed. Keep web stopped and review before retrying.");
    process.exitCode = 1;
});