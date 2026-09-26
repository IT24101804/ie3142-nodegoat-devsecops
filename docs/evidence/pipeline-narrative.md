# Pipeline Narrative — working reference

Factual walkthrough of the CI pipeline for report-writing and viva preparation.

**This is reference material, not report prose.** It is written to be accurate
and answerable, not to be quoted. Write the report in your own words.

Current at commit `b111bfb`. Pipeline definition: `.github/workflows/ci.yml`.

---

## Contents

- [1. The job graph](#1-the-job-graph)
- [2. Why each dependency exists](#2-why-each-dependency-exists)
- [3. The four security gates](#3-the-four-security-gates)
- [4. Which gate enforces, and why that one](#4-which-gate-enforces-and-why-that-one)
- [5. Workflow-level decisions](#5-workflow-level-decisions)
- [6. Honest limitations](#6-honest-limitations)
- [7. Likely viva questions](#7-likely-viva-questions)

---

## 1. The job graph

```
lint             ─────────────┐
sast             ─────────────┤
dependency-scan  ─────────────┤──►  ci-status
secrets-scan ⚠   ─────────────┤
build ──┬─► smoke-test ───────┤
        └─► container-scan ───┘
```

Eight jobs. **One** real dependency edge shape: everything is parallel except
`smoke-test` and `container-scan`, which both need `build`, and `ci-status`,
which needs everything.

### Typical timings (CI #14, commit `a11b1a7`, total 1m 34s)

| Job | Time | Depends on |
|---|---|---|
| Lint and static checks | 23s | — |
| Build container image | 25s | — |
| Security - SAST (Semgrep) | 32s | — |
| Security - Dependency scan (npm audit) | 20s | — |
| Security - Secrets scan (Gitleaks) **[ENFORCING]** | 7s | — |
| Smoke test the running stack | 52s | `build` |
| Security - Container scan (Trivy) | 53s | `build` |
| CI status | 4s | all seven |

Total wall-clock is ~1m 30s even though the jobs sum to well over three minutes,
because six of the eight run concurrently. The critical path is
`build (25s) → smoke-test (52s) → ci-status (4s)`.

---

## 2. Why each dependency exists

### Why `lint`, `sast`, `dependency-scan` and `secrets-scan` have no `needs`

None of them consumes anything another job produces:

- `lint` and `sast` read the **source tree**.
- `dependency-scan` reads **`package-lock.json`** — notably it does *not* need
  `npm ci`, because `npm audit` resolves the lockfile against the registry
  advisory API without `node_modules` present. That is why it is the second
  fastest job.
- `secrets-scan` reads the **git history**.

Adding a dependency would only add wall-clock time. It would also make failure
attribution worse: if lint had to wait for build, a build failure would *skip*
lint and you would not know whether the code also had lint errors.

### Why `smoke-test` and `container-scan` need `build`

Both consume the container image. The important part is **how**:

`build` runs `docker save` and uploads the image as an artifact
(`nodegoat-web-image`, ~51.5 MB). `smoke-test` and `container-scan` each
`docker load` that artifact.

Two reasons this matters, and the second is the one worth making in a viva:

1. **Efficiency** — the image is built once, not three times.
2. **Correctness** — the bytes the smoke test exercises and the bytes Trivy
   scans are *the same bytes*. If each job rebuilt, they could each be testing a
   subtly different image, and you would be certifying something nobody ran.

`container-scan` deliberately has **no checkout step**: it scans a built
artifact, not source, so it needs nothing from the repository.

### Why `ci-status` exists

An aggregating job that succeeds only if all seven others did.

Branch protection names required status checks **individually**. With this job,
only "CI status" needs to be marked required — and when a gate is added, it goes
into `ci-status.needs` and becomes enforcing automatically, with no change to
repository settings.

It uses `if: always()`. Without that, a failed dependency would cause
`ci-status` to be **skipped**, and branch protection can interpret a skip as a
pass.

---

## 3. The four security gates

| Gate | Tool | Threshold | Enforces? | Findings (CI #14) |
|---|---|---|---|---|
| SAST | Semgrep | ERROR | No | 3 ERROR, 12 WARNING |
| Dependency / SCA | npm audit | critical, `--omit=dev` | No | 16 critical, 24 high (51 total) |
| **Secrets** | **Gitleaks** | **any finding** | **YES** | 2 baselined, 0 new |
| Container image | Trivy | CRITICAL + HIGH | No | 9 critical, 58 high |

Detailed findings: [`sast-semgrep-findings.md`](sast-semgrep-findings.md),
[`dependency-npm-audit.md`](dependency-npm-audit.md),
[`secrets-gitleaks-baseline.md`](secrets-gitleaks-baseline.md),
[`container-trivy-split.md`](container-trivy-split.md).

### 3.1 SAST — Semgrep

**Why Semgrep and not `eslint-plugin-security`:** this project lints with
**jshint**, not ESLint. The ESLint route would mean introducing a second linter
and a second config purely for CI. Semgrep needs no project config, ships
curated Express/Node rulesets (`p/javascript`, `p/nodejs`, `p/owasp-top-ten`),
and emits SARIF natively.

**Why the threshold is ERROR:** the noise is asymmetric. 5 of the 12 WARNINGs
are `plaintext-http-link` — `http://` hyperlinks in *tutorial documentation
pages*, not application traffic. That is ~33% noise at WARNING level and **0% at
ERROR level**. Setting the bar at ERROR is a measured decision, not a default.

**What it found:** the 3 ERRORs are `code-string-concat` at
`app/routes/contributions.js:32-34` — NodeGoat's **`eval()` code injection**, its
flagship OWASP A1 vulnerability. Stock rulesets, no custom rules.

### 3.2 Dependency / SCA — npm audit

**Why npm audit and not Snyk or OWASP Dependency-Check:** Snyk requires a
`SNYK_TOKEN` repository secret; Dependency-Check downloads the full NVD feed on
every run and targets Java. `npm audit` is native to this ecosystem, reads our
exact lockfile, and needs **no credentials** — which was an explicit selection
criterion across all four gates.

**Why `--omit=dev`, and why both numbers are printed:** the `Dockerfile` builds
the runtime image with `npm ci --omit=dev`, so grunt, cypress, mocha and jshint
are **provably not in the shipped image**. Scanning them inflates the count
without reflecting attack surface.

The job summary prints **both** figures — production 51, full tree 145 — so the
effect of the scoping is visible. That is the distinction to hold onto:
**scoping with a stated reason and both numbers shown is tuning; reporting 51
alone would be suppression.**

### 3.3 Secrets — Gitleaks *(the enforcing gate — see §4)*

**Why the container and not `gitleaks-action`:** the action requires a
`GITLEAKS_LICENSE` for organization accounts. The container keeps the pipeline
free of licensing dependencies. Pinned to `v8.30.1` so results are reproducible.

**`fetch-depth: 0` is load-bearing.** The default checkout is shallow (depth 1),
which would let Gitleaks see only the newest commit. Since the entire value of
history scanning is catching a secret that was committed and *later deleted*, a
shallow checkout would gut the gate **while still reporting green**. Easy to get
wrong and never notice.

**`--redact`** keeps secret values out of CI logs, which are themselves a
disclosure channel.

### 3.4 Container image — Trivy

**Why Trivy:** scans OS packages and language dependencies in one pass, no
credentials, reads the image straight from the Docker daemon. Pinned to `0.74.0`.

**The finding that matters is the split, not the total:**

```
Base image (Alpine OS packages)      0 critical,  4 high
Application dependencies (Node.js)   9 critical, 54 high
```

"67 critical and high findings" is true but useless. "**0 critical findings
attributable to the base image we chose**" is the same data saying something
actionable — and it retrospectively validates the Phase 1 decision to move off
the end-of-life `node:12-alpine`.

All four base-image findings are OpenSSL (`CVE-2026-14456`, `CVE-2026-45447`
across `libcrypto3` and `libssl3`), and **all four have fixes available**. Those
are the only findings in the image that are actionable within this workstream.

---

## 4. Which gate enforces, and why that one

**Gitleaks enforces. The other three report.**

### Why Gitleaks is the right choice

| Reason | Detail |
|---|---|
| **Binary risk** | There is no defensible "acceptable number of leaked secrets". CVE counts are graduated; a leaked credential is not. |
| **Near-zero noise** | 2 precise findings on this repository, both known and understood. |
| **No conflict with other workstreams** | A *new* secret is never intentional NodeGoat behaviour. SAST, dependency and container findings **are** intentional, and teammates are required not to fix them yet. |

That third row is the substance of the argument. Enforcing SAST would make
`main` permanently red over `eval()` code injection that the remediation
workstream is deliberately preserving. A pipeline that is always red gets
ignored — which is a *worse* security outcome than no gate, and you cannot
honestly call it passing.

### Baseline, not suppression

`.gitleaksignore` contains **2 entries**, both the OWASP ZAP API key that
upstream duplicated into `config/env/development.js:6` and
`config/env/test.js:6`.

Entries are **exact fingerprints** (`commit:file:rule:line`), chosen over the
alternatives deliberately:

- A **path** allowlist would exempt the whole file forever — a new secret
  dropped into `development.js` would pass unnoticed.
- A **regex** allowlist would require pasting the secret into another tracked
  file.
- A **fingerprint** covers one specific finding. A different secret in the same
  file, or the same secret in a new commit, still fails.

The file carries the rule: *"Never add an entry to make a red build go green. If
the gate fires, a new secret has been introduced — remove the secret, do not
baseline it."*

### The evidence it actually blocks

**CI #15** (`b953365`, run id `35064195044`) — a randomly generated fake AWS
credential pushed to a throwaway branch:

```
Baselined known upstream findings: 2
New findings this run: 2

BUILD BLOCKED. A secret that is not in the baseline was detected.
```

Six jobs green, `secrets-scan` red (exit 1), `ci-status` red. The fake credential
was placed in a file **outside jshint's scope** so the run could not fail for two
reasons at once.

**`Baselined: 2` and `New findings: 2` in the same scan is the proof.** The known
findings stayed suppressed while new ones were caught. That single line answers
the "isn't your baseline just suppression?" challenge with tool output rather
than assertion.

**Worth mentioning:** the first attempt used AWS's canonical documentation key
(`AKIAIOSFODNN7EXAMPLE`) and Gitleaks **correctly refused to flag it** — it
carries stopwords for known example credentials. Genuinely random values were
needed. That shows entropy and allowlist analysis rather than naive pattern
matching, and pre-empts any suggestion the demo was rigged.

### Enforcement is deferred, not absent

Each report-only gate contains its `exit 1`, commented, with the reason above it:

```bash
echo "Gate is REPORT-ONLY. Not failing the build."
# exit 1   # <-- uncomment to make this gate enforcing
```

Trivy additionally computes the one threshold that *would* be safe to enforce —
**OS-level CRITICAL, currently 0** — which would catch a base-image regression
without being blocked by application vulnerabilities.

---

## 5. Workflow-level decisions

| Decision | Reason |
|---|---|
| `permissions: contents: read` at workflow level | Least privilege on `GITHUB_TOKEN`. Widened to `security-events: write` **only** on the `sast` job. |
| `concurrency` + `cancel-in-progress` | Superseded pushes are cancelled; a branch's status always reflects its newest commit. |
| `cache: 'npm'` on setup-node | The dev tree is 962 packages, ~3 min cold. Install takes ~12s in CI. |
| `CYPRESS_INSTALL_BINARY: '0'` | Skips an ~80 MB download for a suite this pipeline does not run. |
| `--wait --wait-timeout 180` on compose | Blocks on real healthchecks rather than `sleep`. |
| `if: failure()` log dump | A red run tells you *why*, not just *that*. |
| `if: always()` teardown | Cleanup happens even when tests fail. |
| Actions pinned at `checkout@v7`, `setup-node@v7`, `upload-artifact@v7`, `download-artifact@v8` | `v4` raised a Node 20 deprecation annotation; bumped and validated on a branch (CI #2) before merging. |

### The `npm test` situation

`npm test` runs in the lint job and is **explicitly labelled as running no
tests**. Upstream ships no `test/unit/` directory, so `grunt test` reports
`No files to check...OK` and exits 0.

It is kept and labelled rather than removed, so nobody mistakes a green tick for
real unit coverage. Actual verification is `scripts/smoke-test.sh` — 8
assertions against the running stack, including a **trust-boundary regression
test** (assertion 7 fails if anyone publishes MongoDB to the host).

### jshint is invoked directly, not through Grunt

This is the single most important line in the workflow.

`Gruntfile.js:156` sets `grunt.option("force", true)`, which downgrades every
task failure to a warning and **still exits 0**. Verified: two real lint errors
produced `Used --force, continuing` and exit code 0. `--no-force` does not
override it, because the Gruntfile sets the option programmatically after the
CLI is parsed.

Calling `npx jshint` directly bypasses Grunt entirely and restores an honest exit
code (0 clean / 2 on error). **No file was modified to achieve this.** Without
it, the lint gate would have been decoration — green regardless of what anyone
committed.

### Docker Hub authentication — the only encrypted secrets

`DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`. The pipeline pulls five images per
run; Docker Hub rate-limits anonymous pulls per source IP and GitHub runners
share NAT'd ranges. This is a reliability need, not an invented use of the
feature.

Handling: referenced as `${{ secrets.* }}` **only** in the workflow `env:` block
(interpolating into a `run:` body would inline the literal into the shell
script); passed via `--password-stdin`, never as a CLI argument; never echoed.

**Optional by design** — absent secrets log `using anonymous pulls` and exit 0,
so the pipeline works on forks and on PRs without secret access. Both states are
evidenced: CI #12 (fallback) and CI #20 (`Login Succeeded`).

---

## 6. Honest limitations

| # | Limitation | Position |
|---|---|---|
| L1 | Three of four gates do not enforce | Deliberate and documented; see §4. Each `exit 1` is present but commented. |
| L2 | The baseline suppresses 2 real findings | Fingerprint-scoped, justified in-file, and CI #15 proves new secrets are still caught. |
| L3 | `npm audit` excludes dev dependencies | Both numbers printed; the runtime image provably excludes them. |
| L4 | `npm test` runs zero tests | Labelled, not hidden. Smoke test is the real verification. |
| L5 | No SARIF in the Security tab | Code scanning requires GitHub Advanced Security on private repos; `/security/code-scanning` returns 404. The step is skipped rather than failing, and findings go to job summaries and artifacts. |
| L6 | No Docker layer caching | The build is ~25s, so the complexity was not justified. Noted as a future optimisation. |
| L7 | Artifacts expire after 7 days | Run pages and job summaries persist; the numbers are extracted into this directory. |
| L8 | Scan counts are point-in-time | Advisory databases update continuously; a re-run may report different totals. |
| L9 | No branch protection configured | `ci-status` exists precisely so that one required check can be enabled, but the repository setting has not been turned on. |
| L10 | Cypress e2e suite not run | Version 3.3.1 (2019), binary does not install, needs a live app and database. Documented rather than quietly dropped. |

**L9 is the one most likely to be probed.** The honest answer: the pipeline
*reports* on every push and pull request, and the aggregating job is ready, but
nothing currently *prevents* a merge. Enabling branch protection on `ci-status`
is a one-setting change and would close that gap.

---

## 7. Likely viva questions

Short answers to rehearse.

**"Walk me through what happens when you push."**
Eight jobs start. Six run in parallel immediately: lint, build, and the four
security gates — except container-scan, which waits for build. Smoke test also
waits for build, loads the image artifact it produced, brings up the full stack
with `docker compose --wait`, and runs 8 assertions. ci-status then aggregates
everything. About 90 seconds end to end.

**"Which gate blocks, and why only that one?"**
Gitleaks. A leaked credential is binary — there is no acceptable number. The
other three find NodeGoat's *intentional* vulnerabilities, which the remediation
workstream is required not to fix yet, so enforcing them would leave main
permanently red and the pipeline would be ignored.

**"Isn't your baseline just suppression?"**
No, and CI #15 demonstrates it: the same scan reported `Baselined: 2` and
`New findings: 2`, blocking the build. Entries are exact fingerprints, committed
with justifications, and the file forbids adding entries to turn a build green.

**"Why exclude dev dependencies from the audit?"**
Because `npm ci --omit=dev` means they are not in the shipped image. Both numbers
are printed — 51 production, 145 full tree — so the scoping is visible rather
than hidden.

**"How do you know the image you scanned is the one you tested?"**
Because it is the same artifact. Build exports the image with `docker save`;
smoke-test and container-scan both load that artifact rather than rebuilding.

**"Your pipeline went red once unexpectedly — what happened?"**
CI #7. A shell quoting bug, not a gate finding: an apostrophe in English prose
inside a single-quoted `node -e` script caused bash to exit 2. Fixed
structurally in CI #8 by moving the script into a quoted heredoc, which cannot
be broken by its own text. Worth keeping — the pipeline caught a real defect in
its own configuration.

**"What would you do differently with more time?"**
Enable branch protection on `ci-status`; enforce Trivy's OS-level CRITICAL
threshold (currently 0, so it would pass today); add real unit tests under
`test/unit/` so `npm test` is meaningful; digest-pin base images rather than
tag-pin.

---

## Reference — all runs cited here

| Run | Commit | What it shows |
|---|---|---|
| CI #4 | `55c127d` | Lint gate blocking; build and smoke-test still green (parallelism) |
| CI #7 | `ea79fd8` | The shell quoting bug |
| CI #8 | `fe6e2e7` | The structural fix |
| CI #12 | `7790e05` | Docker Hub login falling back to anonymous pulls |
| CI #14 | `a11b1a7` | Reference green run, all job summaries |
| CI #15 | `b953365` | **The enforcing gate blocking a build** |
| CI #18 | `ad4d735` | `pull_request` trigger gating a real teammate PR |
| CI #20 | `530da90` | Docker Hub `Login Succeeded` |

---

*Working reference for the IE3142 DevOps Security group assignment. See
[README.md](README.md) for the evidence index.*
