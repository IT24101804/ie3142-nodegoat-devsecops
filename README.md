# IE3142 NodeGoat DevSecOps

A containerised deployment of **OWASP NodeGoat**, used as the target application
for a DevSecOps pipeline built for SLIIT module **IE3142 - DevOps Security**.

This repository is the **Phase 1** deliverable: repository setup, containerisation
and architecture documentation. CI/CD, security scanning, threat modelling and
vulnerability remediation are handled in later phases.

---

> ## Read this before you run anything
>
> NodeGoat is **deliberately insecure**. It ships with real, exploitable
> vulnerabilities (injection, XSS, broken authentication, SSRF, insecure
> dependencies) — that is the entire point of the project.
>
> - It is bound to `127.0.0.1` by default, so **only your own machine can reach it**.
> - **Do not** expose it to the internet, to the university network, or to any shared host.
> - **Do not** reuse any password from this app anywhere real.
> - Run it only on a machine you control.
>
> If you change `APP_BIND_ADDRESS`, you are removing that protection deliberately.

---

## Contents

- [Prerequisites](#prerequisites)
- [Setup from a fresh clone](#setup-from-a-fresh-clone)
- [Verify it works](#verify-it-works)
- [Default accounts](#default-accounts)
- [Stopping the application](#stopping-the-application)
- [Resetting the database](#resetting-the-database)
- [Everyday commands](#everyday-commands)
- [Configuration](#configuration)
- [Project structure](#project-structure)
- [Troubleshooting](#troubleshooting)
- [Known hardcoded secrets](#known-hardcoded-secrets-phase-1-findings)
- [Attribution and licence](#attribution-and-licence)

---

## Prerequisites

You need **one** thing: Docker. Everything else (Node.js, npm, MongoDB) runs
inside containers, so you do **not** need to install them on your machine.

| Requirement | Minimum | Verified working | Check with |
|---|---|---|---|
| Docker Engine | 20.10+ | 29.6.1 | `docker --version` |
| Docker Compose | v2.0+ | v5.2.0 | `docker compose version` |
| Git | 2.x | 2.55.0 | `git --version` |

**Windows / macOS:** install [Docker Desktop](https://www.docker.com/products/docker-desktop/)
and make sure it is **running** before you start — the whale icon must be in your
system tray. If Docker Desktop is not running you will see:

```
failed to connect to the docker API at npipe:////./pipe/dockerDesktopLinuxEngine
```

**Linux:** install `docker-ce` and the `docker-compose-plugin`.

**Disk space:** roughly **1 GB** for both images (app is about 235 MB, MongoDB about 594 MB).

**Network:** the **first** build downloads base images and npm packages, so it needs
internet. After that the application **runs completely offline** — all front-end
assets are served locally and there is no cloud database or third-party service.

---

## Setup from a fresh clone

```bash
git clone https://github.com/IT24101804/ie3142-nodegoat-devsecops.git
cd ie3142-nodegoat-devsecops
docker compose up --build
```

That is the whole setup. One command brings up the **entire** application:
the Node.js web app and the MongoDB database, networked together, with the
database seeded automatically on first run.

> **No `.env` file is required.** Every setting has a sensible default baked into
> `docker-compose.yml`. Only copy `.env.example` to `.env` if you need to change
> something (see [Configuration](#configuration)).

The first build takes **2 to 5 minutes**. Later starts take a few seconds.

To run it in the background instead, add `-d`:

```bash
docker compose up --build -d
```

### What you should see

```
 Container nodegoat-mongo  Started
 Container nodegoat-mongo  Waiting
 Container nodegoat-mongo  Healthy
 Container nodegoat-web    Started
```

then, in the application log:

```
[entrypoint] Checking whether the database needs seeding...
[seed] Database is empty - running artifacts/db-reset.js
Database reset performed successfully
[seed] Seeding complete.
[entrypoint] Starting application: node server.js
Connected to the database
Express http server listening on port 4000
```

On **later** starts, the seeding line changes to the following. This is correct,
not an error:

```
[seed] Database already contains 3 user(s) - skipping seed.
```

---

## Verify it works

1. Open <http://localhost:4000> in your browser.
2. Log in as `admin` / `Admin_123`.
3. You should land on the dashboard with charts and balances.

Or check from the command line:

```bash
docker compose ps
```

Both containers must report `(healthy)`:

```
NAME             IMAGE                       STATUS                    PORTS
nodegoat-mongo   mongo:4.4                   Up 24 seconds (healthy)   27017/tcp
nodegoat-web     nodegoat-devsec/web:local   Up 18 seconds (healthy)   127.0.0.1:4000->4000/tcp
```

Note that MongoDB shows **no host port mapping**. That is intentional — see
[docs/architecture.md](docs/architecture.md).

---

## Default accounts

Seeded automatically by `artifacts/db-reset.js` on first run.

| Username | Password | Role |
|---|---|---|
| `admin` | `Admin_123` | Administrator |
| `user1` | `User1_123` | Standard user (John Doe) |
| `user2` | `User2_123` | Standard user (Will Smith) |

These are **upstream NodeGoat test credentials and are public knowledge**. They are
stored in plaintext in the database on purpose — that is one of the vulnerabilities
the application exists to demonstrate. Never reuse them anywhere real.

---

## Stopping the application

| Goal | Command | Database |
|---|---|---|
| Stop, keep everything | `docker compose stop` | **kept** |
| Stop and remove containers | `docker compose down` | **kept** |
| Stop and **delete all data** | `docker compose down -v` | **destroyed** |
| Stop with Ctrl+C (foreground) | press `Ctrl+C` | **kept** |

The `-v` flag deletes the `nodegoat-mongo-data` volume. Without it, your data
survives and is still there the next time you start.

---

## Resetting the database

Two ways, depending on what you want.

### Option 1 — Re-seed while the app is running (fast)

Drops all collections and re-inserts the default users and allocations. The app
keeps running and no rebuild is needed.

```bash
docker compose exec web node artifacts/db-reset.js
```

Expected output:

```
Dropped collection: users
Dropped collection: allocations
Dropped collection: memos
Dropped collection: counters
Database reset performed successfully
```

Use this when you have broken the data during testing and want a clean slate.

### Option 2 — Destroy the volume and start completely fresh

Deletes the Docker volume entirely, so the next start re-seeds from nothing.

```bash
docker compose down -v
docker compose up -d
```

Use this when you want to prove the stack builds clean from zero, or if the
database itself is corrupted.

### Which should I use?

- **Option 1** for everyday "reset my test data". Takes about a second.
- **Option 2** for a true from-scratch verification, or before a demo.

---

## Everyday commands

```bash
# Start (background)
docker compose up -d

# Start and rebuild after changing code or the Dockerfile
docker compose up --build -d

# Follow the application log
docker compose logs -f web

# Follow the database log
docker compose logs -f mongo

# Container status and health
docker compose ps

# Shell inside the app container
docker compose exec web sh

# MongoDB shell
docker compose exec mongo mongo nodegoat

# Restart just the app
docker compose restart web

# Remove everything including locally built images
docker compose down -v --rmi local
```

---

## Configuration

The stack runs with no configuration at all. To override anything:

```bash
cp .env.example .env
```

then edit `.env`. **`.env` is git-ignored and must never be committed.**

| Variable | Default | Purpose |
|---|---|---|
| `NODE_ENV` | `production` | App environment. `development` injects a livereload script that points at a port nothing serves. |
| `APP_BIND_ADDRESS` | `127.0.0.1` | Host interface the app binds to. **Leave this alone** unless you understand the consequences. |
| `APP_PORT` | `4000` | Host port. Change if 4000 is taken. |
| `MONGO_HOST` | `mongo` | Database hostname on the internal Docker network. |
| `MONGO_PORT` | `27017` | Database port (internal only). |
| `MONGO_DB` | `nodegoat` | Database name. |
| `MONGO_IMAGE_TAG` | `4.4` | MongoDB image tag. See note below. |

> **Why MongoDB 4.4 and not something newer?** MongoDB 5.0+ requires a CPU with
> AVX instruction support. Older laptops without it crash-loop on startup. 4.4
> keeps the stack runnable on every team member's machine.

---

## Project structure

```
.
├── app/                    NodeGoat application (upstream)
│   ├── data/               Data access objects (MongoDB queries)
│   ├── routes/             Express route handlers
│   ├── views/              Swig HTML templates
│   └── assets/             CSS, JS, images - all served locally, no CDN
├── artifacts/
│   └── db-reset.js         Database seeder (upstream, unmodified)
├── config/
│   ├── config.js           Config loader
│   └── env/                Per-environment config
├── docker/                 Added for this project
│   ├── entrypoint.sh       Seeds only if empty, then execs the app
│   └── seed-if-empty.js    Checks whether seeding is needed
├── docs/
│   └── architecture.md     Components, data flows, trust boundaries
├── test/                   Upstream Cypress and security tests
├── Dockerfile              Multi-stage app image
├── docker-compose.yml      Full stack definition
├── .env.example            Documented configuration template
└── LICENSE                 Apache License 2.0 (upstream)
```

---

## Troubleshooting

**`failed to connect to the docker API ... dockerDesktopLinuxEngine`**

Docker Desktop is not running. Start it and wait for the whale icon to settle.

**`port is already allocated` or `bind: address already in use`**

Something else is on port 4000. Either stop it, or use a different port:

```bash
echo "APP_PORT=4100" >> .env
docker compose up -d
```

Then use <http://localhost:4100>.

**App container restarts repeatedly**

Check the logs with `docker compose logs web`. Most often the database was not
ready. The healthcheck should prevent this, but on a very slow machine try:

```bash
docker compose down
docker compose up -d
```

**`mongo` container exits immediately with `Illegal instruction`**

Your CPU lacks AVX support and someone has raised `MONGO_IMAGE_TAG` above 4.4.
Set it back:

```bash
echo "MONGO_IMAGE_TAG=4.4" >> .env
docker compose down && docker compose up -d
```

**Login fails with valid credentials**

The database may be empty or damaged. Re-seed it:

```bash
docker compose exec web node artifacts/db-reset.js
```

**Changes to the code are not showing up**

The image bakes in the source. Rebuild:

```bash
docker compose up --build -d
```

**Everything is broken, start over**

```bash
docker compose down -v --rmi local
docker compose up --build
```

---

## Known hardcoded secrets (Phase 1 findings)

NodeGoat ships hardcoded credentials. These are **deliberately left in place** so
they can act as findings for the secrets-scanning gate in a later phase. They are
recorded here so nobody mistakes them for an oversight.

| File : line | Value | Type |
|---|---|---|
| `config/env/all.js:8` | `cookieSecret` | Session signing key |
| `config/env/all.js:9` | `cryptoKey` | Encryption key |
| `config/env/development.js:6` | `zapApiKey` | API key (high entropy) |
| `config/env/test.js:6` | `zapApiKey` | API key (high entropy) |
| `artifacts/db-reset.js:18,27,35` | `Admin_123`, `User1_123`, `User2_123` | Seeded passwords, stored plaintext |
| `test/e2e/fixtures/users/*.json` | Test credentials | Test fixtures |
| `config/config.js:12-13` | Whole config object | Secrets printed to container logs at startup |

**Not in this repository:** upstream NodeGoat tracks an RSA private key at
`artifacts/cert/server.key`. Our `.gitignore` excludes `*.key`, so it is **not**
committed here. The code that would read it is commented out (`server.js:21-27`),
so the application is unaffected.

Secrets management is a later-phase task. See
[docs/architecture.md](docs/architecture.md) for the options under consideration.

---

## Attribution and licence

This project is based on **OWASP NodeGoat**.

| | |
|---|---|
| **Upstream project** | [OWASP NodeGoat](https://github.com/OWASP/NodeGoat) |
| **Upstream repository** | `https://github.com/OWASP/NodeGoat` |
| **Branch** | `master` |
| **Base commit** | [`c5cb68a7084e4ae7dcc60e6a98768720a81841e8`](https://github.com/OWASP/NodeGoat/commit/c5cb68a7084e4ae7dcc60e6a98768720a81841e8) |
| **Commit date** | 2023-06-21 |
| **Licence** | [Apache License 2.0](LICENSE) |

The upstream source tree was imported at the commit above **without** its `.git`
history, so that contributions by each member of this team remain individually
attributable. This repository is **not** a fork.

### Licence compliance

NodeGoat is distributed under the Apache License 2.0. In accordance with its terms:

- The full, unmodified `LICENSE` file is retained at the root of this repository.
- Copyright and attribution notices from the original work are preserved.
- Files modified by this team are identified below, as required by section 4(b).

**Files added by this team:**

```
docker/entrypoint.sh        docker/seed-if-empty.js
docs/architecture.md        .env.example
.gitattributes              README.md (this file)
```

**Upstream files modified by this team:**

```
Dockerfile                  rewritten for a supported Node LTS base
docker-compose.yml          rewritten for persistence and trust boundaries
.dockerignore               extended to exclude node_modules and secrets
.gitignore                  replaced with a fuller Node.js ruleset
README.md                   replaced (upstream README preserved in git history)
```

**Upstream application code is unmodified.** Everything under `app/`, `config/`,
`artifacts/`, `test/` and `server.js` is exactly as OWASP published it at commit
`c5cb68a`. The vulnerabilities are intentional and are the subject of later phases.

---

## Module context

| | |
|---|---|
| **Module** | IE3142 - DevOps Security |
| **Institution** | Sri Lanka Institute of Information Technology (SLIIT) |
| **Phase** | 1 of 4 — repository setup, containerisation, architecture |
| **Later phases** | CI/CD pipeline, security scanning gates, threat modelling, remediation |
