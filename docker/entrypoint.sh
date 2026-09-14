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
echo "[entrypoint] Checking whether the database needs seeding..."

node /home/node/app/docker/seed-if-empty.js

echo "[entrypoint] Starting application: $*"

# exec replaces the shell with the application process, so the app becomes
# PID 1 and receives SIGTERM directly on `docker compose stop`. Without exec,
# the shell would swallow the signal and Docker would fall back to SIGKILL.
exec "$@"
