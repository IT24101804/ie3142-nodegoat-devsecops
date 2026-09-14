# syntax=docker/dockerfile:1
#
# OWASP NodeGoat - application container
# IE3142 DevOps Security :: Phase 1 (containerisation)
#
# Two-stage build:
#   deps    - resolves production dependencies against the lockfile
#   runtime - minimal image containing only the app + its runtime deps
#
# The build toolchain (npm cache, dev dependencies) never reaches the final
# image, which keeps the runtime attack surface small and the image slim.

# ---------------------------------------------------------------------------
# Stage 1: dependencies
# ---------------------------------------------------------------------------
FROM node:20-alpine AS deps

WORKDIR /build

# Copy ONLY the manifests first. Docker caches this layer, so dependencies are
# re-resolved only when package.json / package-lock.json actually change -
# not on every source edit.
COPY package.json package-lock.json ./

# `npm ci` (not `npm install`) installs the exact tree pinned in
# package-lock.json and fails if the lockfile is out of sync with package.json.
# This is what makes the build reproducible across all four team machines.
#   --omit=dev  : production dependencies only
#   --no-audit  : audit belongs in the pipeline (later phase), not the build
#   --no-fund   : suppress funding noise in build logs
RUN npm ci --omit=dev --no-audit --no-fund

# ---------------------------------------------------------------------------
# Stage 2: runtime
# ---------------------------------------------------------------------------
FROM node:20-alpine AS runtime

# NOTE: NODE_ENV is set here as a safe default. docker-compose.yml overrides it
# at run time so the value is explicit rather than inherited from a host shell.
ENV NODE_ENV=production

# The node:* images already ship an unprivileged `node` user (uid 1000).
WORKDIR /home/node/app

# Bring across the dependency tree built in stage 1. These were compiled inside
# Linux, so they are correct regardless of the developer's host OS.
COPY --from=deps --chown=node:node /build/node_modules ./node_modules

# Then the application source. .dockerignore excludes node_modules, so a
# developer's host-built node_modules can never overwrite the line above.
COPY --chown=node:node . .

# Drop privileges. Everything from here runs as a non-root user, so a
# successful exploit of this deliberately-vulnerable app does not get root
# inside the container.
USER node

EXPOSE 4000

# Liveness probe used by docker-compose to gate dependent services and to
# report container health. busybox wget ships in the alpine base image.
HEALTHCHECK --interval=15s --timeout=5s --start-period=40s --retries=5 \
    CMD wget --spider --quiet http://127.0.0.1:4000/login || exit 1

# The entrypoint seeds the database only when it is empty, then hands off to
# CMD via `exec "$@"`. Invoked through `sh` rather than relying on the file's
# executable bit, which Windows checkouts do not reliably preserve.
ENTRYPOINT ["/bin/sh", "/home/node/app/docker/entrypoint.sh"]

# The image is runnable on its own: `docker run` starts the server without
# compose having to supply a command.
CMD ["node", "server.js"]
