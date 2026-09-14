#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Smoke test for the running NodeGoat stack.
#
# Asserts that the deployed application actually works end to end: it serves
# pages, enforces authentication, accepts a real login, and keeps the database
# off the host network.
#
# Run it against a stack that is already up:
#     docker compose up -d --wait
#     ./scripts/smoke-test.sh
#
# Exits 0 if every assertion passes, 1 on the first failure. The non-zero exit
# is what makes this usable as a CI gate - see .github/workflows/ci.yml.
#
# Environment:
#     BASE_URL   application base URL      (default http://localhost:4000)
#     MONGO_PORT port that must NOT be open on the host (default 27017)
# ---------------------------------------------------------------------------
set -euo pipefail

BASE_URL="${BASE_URL:-http://localhost:4000}"
MONGO_PORT="${MONGO_PORT:-27017}"

COOKIE_JAR="$(mktemp)"
trap 'rm -f "$COOKIE_JAR"' EXIT

PASS=0
FAIL=0

pass() { printf '  [PASS] %s\n' "$1"; PASS=$((PASS + 1)); }
fail() { printf '  [FAIL] %s\n' "$1"; FAIL=$((FAIL + 1)); }

section() { printf '\n=== %s ===\n' "$1"; }

# ---------------------------------------------------------------------------
# Wait for the application to accept connections.
#
# docker compose --wait already gates on the container healthcheck, so this is
# a short backstop for the gap between "container healthy" and "route serving",
# not the primary readiness mechanism.
# ---------------------------------------------------------------------------
section "Waiting for application at ${BASE_URL}"
ATTEMPTS=30
for i in $(seq 1 "$ATTEMPTS"); do
    if curl -fsS -o /dev/null --max-time 5 "${BASE_URL}/login" 2>/dev/null; then
        printf '  application responded after %s attempt(s)\n' "$i"
        break
    fi
    if [ "$i" -eq "$ATTEMPTS" ]; then
        printf '  ERROR: application did not respond after %s attempts\n' "$ATTEMPTS"
        exit 1
    fi
    sleep 2
done

# ---------------------------------------------------------------------------
# 1. The login page is served.
# ---------------------------------------------------------------------------
section "1. Application serves the login page"
CODE="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/login")"
if [ "$CODE" = "200" ]; then
    pass "GET /login returned 200"
else
    fail "GET /login returned ${CODE}, expected 200"
fi

# ---------------------------------------------------------------------------
# 2. Static assets are served locally (no CDN dependency).
#
# Guards the offline requirement from docs/architecture.md: if someone swaps a
# vendored asset for a CDN link, this assertion breaks.
# ---------------------------------------------------------------------------
section "2. Front-end assets are served locally"
CODE="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/vendor/jquery.min.js")"
if [ "$CODE" = "200" ]; then
    pass "GET /vendor/jquery.min.js returned 200 (asset served by the app, not a CDN)"
else
    fail "GET /vendor/jquery.min.js returned ${CODE}, expected 200"
fi

# ---------------------------------------------------------------------------
# 3. Authentication is enforced on protected routes.
# ---------------------------------------------------------------------------
section "3. Protected routes reject unauthenticated requests"
CODE="$(curl -s -o /dev/null -w '%{http_code}' "${BASE_URL}/dashboard")"
if [ "$CODE" = "302" ]; then
    pass "GET /dashboard without a session returned 302 (redirect to login)"
else
    fail "GET /dashboard without a session returned ${CODE}, expected 302"
fi

# ---------------------------------------------------------------------------
# 4. A real login succeeds.
#
# Credentials are the seeded, publicly documented NodeGoat test accounts. They
# are NOT secrets: they ship in artifacts/db-reset.js and are published in the
# upstream project. Nothing sensitive is hardcoded here.
# ---------------------------------------------------------------------------
section "4. Seeded admin account can log in"
CODE="$(curl -s -c "$COOKIE_JAR" -o /dev/null -w '%{http_code}' \
        -d 'userName=admin&password=Admin_123' "${BASE_URL}/login")"
if [ "$CODE" = "302" ]; then
    pass "POST /login with seeded admin returned 302 (login accepted)"
else
    fail "POST /login with seeded admin returned ${CODE}, expected 302"
fi

if grep -q 'connect.sid' "$COOKIE_JAR"; then
    pass "session cookie 'connect.sid' was issued"
else
    fail "no session cookie was issued"
fi

# ---------------------------------------------------------------------------
# 5. The authenticated session actually works.
#
# This is the assertion that proves the whole stack is wired up: serving the
# dashboard requires the app to read seeded data back out of MongoDB.
# ---------------------------------------------------------------------------
section "5. Authenticated session can reach the dashboard"
BODY="$(curl -s -b "$COOKIE_JAR" "${BASE_URL}/dashboard")"
if printf '%s' "$BODY" | grep -q 'Node Goat Admin'; then
    pass "GET /dashboard with session shows the logged-in admin user"
else
    fail "GET /dashboard with session did not show the expected user"
fi

# ---------------------------------------------------------------------------
# 6. Bad credentials are rejected.
# ---------------------------------------------------------------------------
section "6. Invalid credentials are rejected"
BODY="$(curl -s -d 'userName=admin&password=definitely-not-the-password' "${BASE_URL}/login")"
if printf '%s' "$BODY" | grep -qiE 'invalid (password|username)'; then
    pass "POST /login with a wrong password was rejected"
else
    fail "POST /login with a wrong password was NOT rejected"
fi

# ---------------------------------------------------------------------------
# 7. Trust boundary TB-2: the database must not be reachable from the host.
#
# Regression test for the architecture decision in docs/architecture.md. If
# someone adds a `ports:` mapping to the mongo service, this fails.
# ---------------------------------------------------------------------------
section "7. Trust boundary: MongoDB is not exposed to the host"
if curl -s --max-time 4 -o /dev/null "http://localhost:${MONGO_PORT}/" 2>/dev/null; then
    fail "port ${MONGO_PORT} answered on the host - the database is exposed!"
else
    pass "port ${MONGO_PORT} is not reachable from the host (database correctly isolated)"
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '\n=====================================\n'
printf '  Smoke test: %s passed, %s failed\n' "$PASS" "$FAIL"
printf '=====================================\n'

if [ "$FAIL" -gt 0 ]; then
    exit 1
fi
exit 0
