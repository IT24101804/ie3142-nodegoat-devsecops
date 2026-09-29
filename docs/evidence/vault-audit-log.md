# Evidence — HashiCorp Vault audit log

**Source:** `/vault/audit/audit.log` inside the `nodegoat-vault` container
**Stack:** local `docker compose` deployment at commit `a11b1a7`
**Vault:** `hashicorp/vault:2.1.0`, dev mode, file audit device
**Captured:** stack started 2026-09-15T06:22Z

This is the evidence for the "secrets manager injecting a secret at runtime"
requirement. It is **local terminal evidence, not a GitHub Actions run** — the
Vault demonstration is part of the application stack, not the pipeline.

---

## Why the audit log is the evidence that matters

An audit trail is the capability a `.env` file **fundamentally cannot provide**.
Anyone can claim "we used Vault"; the audit log shows *which identity read
which secret at what time, under which policy*.

Crucially, it distinguishes the **provisioning** access (root token) from the
**application** access (AppRole, least-privilege) — proving the application was
never handed a root token.

---

## The extracted entries

34 audit entries were recorded. Six concern the application secret or AppRole
authentication:

```
time          : 2026-09-15T06:22:21.827054282Z
operation     : read     path: secret/data/nodegoat
display_name  : token
policies      : ["root"]
client_token  : hmac-sha256:39770bd3b9deea56...

time          : 2026-09-15T06:22:21.870466763Z
operation     : create   path: secret/data/nodegoat
display_name  : token
policies      : ["root"]
client_token  : hmac-sha256:39770bd3b9deea56...

time          : 2026-09-15T06:22:22.450140721Z
operation     : update   path: auth/approle/login
display_name  : approle
policies      : ["default","nodegoat-app"]
token_ttl     : 1200
client_token  : hmac-sha256:2892ebea1bf8e7db...

time          : 2026-09-15T06:22:22.481873459Z
operation     : read     path: secret/data/nodegoat
display_name  : approle
policies      : ["default","nodegoat-app"]
token_ttl     : 1200
client_token  : hmac-sha256:2892ebea1bf8e7db...

time          : 2026-09-15T06:22:46.468173715Z
operation     : read     path: secret/data/nodegoat
display_name  : token
policies      : ["root"]

time          : 2026-09-15T06:22:58.384540813Z
operation     : read     path: secret/data/nodegoat
display_name  : token
policies      : ["root"]
```

## Reading the trail

| Time | Actor | What happened |
|---|---|---|
| `06:22:21.827` | **root** (`vault-init`) | Checked whether the secret already existed |
| `06:22:21.870` | **root** (`vault-init`) | **Created** the secret — generated inside Vault from `/dev/urandom` |
| `06:22:22.450` | **approle** (application) | **Authenticated** — received a token, TTL **1200s**, policies `default` + `nodegoat-app` |
| `06:22:22.481` | **approle** (application) | **Read** the secret — 31 ms after authenticating |
| `06:22:46`, `06:22:58` | root | Later manual verification reads (comparing the app's value against Vault's) |

**The two entries at `06:22:22` are the decisive pair.** They show the
application authenticating with AppRole and immediately reading exactly one
secret, under a token scoped to `nodegoat-app` — not root.

## Two distinct identities, visible in the log

| | Provisioning | Application |
|---|---|---|
| `display_name` | `token` | `approle` |
| `policies` | `["root"]` | `["default","nodegoat-app"]` |
| Token TTL | unlimited | **1200s (20 min)** |
| Capability | everything | `read` on `secret/data/nodegoat` only |

## Secret values are not in the log

`client_token` appears as `hmac-sha256:…` — Vault HMACs sensitive fields in audit
output rather than writing them in clear. **The audit log can be shared as
evidence without disclosing anything**, which is precisely what makes it usable
in a report.

---

## Corresponding application output

`docker compose logs web | grep '\[vault\]'`:

```
[vault] AppRole login succeeded as role_id 80310685-1248-e8ec-d861-fd2cfecb0ba9
[vault] token TTL 1200s, renewable=true, policies: default, nodegoat-app
[vault] Retrieved 2 secret(s) from secret/data/nodegoat: SESSION_SECRET, CRYPTO_KEY (values not logged).
[entrypoint] Secrets loaded from Vault into the process environment.
```

`role_id` is logged deliberately — it is an **identity**, comparable to a
username, and is not secret. `secret_id` is never logged.

---

## Proof the secret genuinely came from Vault

| Check | Result |
|---|---|
| `.env` values | `SESSION_SECRET=` and `CRYPTO_KEY=` — **both blank** |
| Running app process (`/proc/1/environ` in `nodegoat-web`) | `SESSION_SECRET` present, **64 characters** |
| Compared against `vault kv get -field=session_secret secret/nodegoat` | **MATCH** |
| `docker inspect nodegoat-web` | **0 occurrences** of the value; `SESSION_SECRET=` shown empty |
| Full container logs grepped for the value | **0 occurrences** |
| `scripts/smoke-test.sh` | **8 passed, 0 failed** |
| Real login | `POST /login` → `302 → /benefits`; dashboard shows `Node Goat Admin` |

The `docker inspect` result is a **genuine security property**, not a formality.
A secret passed through compose `environment:` is visible to anyone who can run
`docker inspect`. Fetched at runtime by the entrypoint, it exists only in the
application process's own environment.

> **Verification note.** `docker compose exec web env` will show
> `SESSION_SECRET` as empty. That is **expected, not a failure**: `exec` spawns a
> new process which does not inherit what the entrypoint sourced into the shell
> that `exec`'d the application. Read `/proc/1/environ` instead. This caught out
> the first verification attempt during Phase 5.

---

## Reproducing this

```bash
cp .env.example .env
echo "VAULT_DEV_ROOT_TOKEN=dev-root-$(openssl rand -hex 12)" >> .env
# leave SESSION_SECRET and CRYPTO_KEY blank - Vault supplies them
docker compose down -v && docker compose up -d --wait

docker compose logs vault-init | grep '\[vault-init\]'
docker compose logs web        | grep '\[vault\]'
docker compose exec vault cat /vault/audit/audit.log
```

---

## Honest limitations

Vault's real value is only partly demonstrable on a two-container local stack.
Full detail is in `docs/secrets.md` §8; the ones that matter most here:

| # | Limitation |
|---|---|
| **L1** | **Secret zero** — bootstrapping Vault still needs `VAULT_DEV_ROOT_TOKEN` in `.env`. Vault cannot eliminate this; production breaks the chain with platform identity (Kubernetes service accounts, cloud IAM, KMS auto-unseal) |
| **L2** | `secret_id` is delivered via a shared Docker volume, standing in for what a real deployment would do with Vault Agent or a projected service-account token |
| **L3** | Dev mode: in-memory, auto-unsealed, single node. Secrets are regenerated on every restart |
| **L4** | No TLS to Vault — plain HTTP on the private compose network |
| **L6** | The 20-minute token is fetched once at startup and never renewed. Harmless here because the secret is read once at boot |

Naming the secret-zero problem explicitly is the honest position: it is the
limitation every Vault deployment has, and a report that claims otherwise is
wrong.

---

*Captured from the local stack at commit `a11b1a7` for the IE3142 technical
report. See [README.md](README.md) for the full evidence index and
`docs/secrets.md` for the full secrets design.*
