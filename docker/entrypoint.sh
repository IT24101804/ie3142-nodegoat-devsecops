#!/bin/sh
# ---------------------------------------------------------------------------
# Container entrypoint for the NodeGoat application service.
#
# Responsibilities:
#   1. Seed the database, but ONLY if it is empty.
#   2. Hand off to the container's CMD as PID 1.
#
# Why conditional seeding: upstream ran artifacts/db-reset.js unconditionally on
# every start, which dropped every collection each time the stack came up. That
# makes persistence impossible and makes "reset the database" meaningless as a
# documented operation. Here, seeding happens once on a fresh volume; resetting
# is an explicit action the operator takes (see README).
# ---------------------------------------------------------------------------
set -e

echo "[entrypoint] NODE_ENV=${NODE_ENV}"

# ---------------------------------------------------------------------------
# Fetch secrets from Vault, if it is configured.
#
# Additive and never fatal: vault-fetch.js always exits 0. If Vault is absent,
# unreachable or misconfigured it writes an empty file and the application falls
# back to environment-provided secrets, which in turn fall back to a generated
# ephemeral key. A secrets manager must not be able to stop the stack starting.
#
# Sourced rather than exported inline so the values never appear in this
# script's own trace output.
# ---------------------------------------------------------------------------
node /home/node/app/docker/vault-fetch.js || true
if [ -s /tmp/vault-env.sh ]; then
    . /tmp/vault-env.sh
    rm -f /tmp/vault-env.sh
    echo "[entrypoint] Secrets loaded from Vault into the process environment."
else
    rm -f /tmp/vault-env.sh 2>/dev/null || true
fi
echo "[entrypoint] Checking whether the database needs seeding..."

node /home/node/app/docker/seed-if-empty.js

echo "[entrypoint] Starting application: $*"

# exec replaces the shell with the application process, so the app becomes
# PID 1 and receives SIGTERM directly on `docker compose stop`. Without exec,
# the shell would swallow the signal and Docker would fall back to SIGKILL.
exec "$@"
