# Evidence Index — IE3142 NodeGoat DevSecOps

Evidence for the **infrastructure and CI/CD workstream**: containerisation, the
pipeline, the four security gates, and secrets management. For each artefact —
what it proves, which criterion it supports, and the run and commit it came from.

Evidence for the other workstreams is owned and maintained by their authors and
is indexed separately in [§7](#7-evidence-owned-by-other-team-members). This
document does not review or vouch for that material.

**Note on criteria.** The "Supports" column maps to the assignment requirements
as stated in the project brief. It is not a transcription of the official rubric
document — check the wording against the marking scheme before quoting it.

**Note on retention.** GitHub Actions **run pages and job summaries persist
indefinitely**. The uploaded **artifacts have `retention-days: 7`** and expire
roughly one week after each run. That is why the text evidence in this directory
was extracted into the repository — see [§4](#4-extracted-text-evidence).

---

## Contents

- [1. Run ledger](#1-run-ledger)
- [2. Evidence already in this repository](#2-evidence-already-in-this-repository)
- [3. Screenshots](#3-screenshots)
- [4. Extracted text evidence](#4-extracted-text-evidence)
- [5. Coverage against the brief](#5-coverage-against-the-brief)
- [6. Gaps and honest caveats](#6-gaps-and-honest-caveats)
- [7. Evidence owned by other team members](#7-evidence-owned-by-other-team-members)

---

## 1. Run ledger

All 15 CI runs. Reference runs as **CI #N at commit `sha`** — that pair is stable
and unambiguous. URLs follow the pattern
`https://github.com/IT24101804/ie3142-nodegoat-devsecops/actions/runs/<id>`.

| Run | Commit | Branch | Result | Time | What it demonstrates | Run id |
|---|---|---|---|---|---|---|
| CI #1 | `f0db03a` | main | ✅ | 1m29s | First working pipeline: lint, build, smoke test, ci-status | `34854641314` |
| CI #2 | `cd7c1aa` | chore/bump-actions | ✅ | 1m30s | Action version bump validated on a branch before merge | `34855402243` |
| CI #3 | `cd7c1aa` | main | ✅ | 1m31s | Same commit green on main after fast-forward merge | — |
| **CI #4** | `55c127d` | test/deliberate-ci-failure | ❌ | 1m30s | **Lint gate blocks a build** (3 deliberate jshint errors) | `34855795216` |
| CI #5 | `003e1cc` | main | ✅ | 1m39s | SAST gate added (Semgrep) | `34865088624` |
| CI #6 | `13b7e61` | main | ✅ | 1m31s | Semgrep single-run optimisation; SARIF upload skipped on private repo | — |
| **CI #7** | `ea79fd8` | main | ❌ | 1m32s | Unplanned failure: shell quoting bug, exit code 2 (see §6) | `34867061747` |
| CI #8 | `fe6e2e7` | main | ✅ | 2m36s | Quoting bug fixed via quoted heredoc | `34867966873` |
| CI #9 | `d57d9b5` | main | ✅ | 1m30s | Secrets gate added (Gitleaks, enforcing) | `34921802782` |
| CI #10 | `644ac7d` | main | ✅ | 1m33s | Container scan added (Trivy) — all four gates live | `34923082154` |
| CI #11 | `00b5abc` | main | ✅ | 1m28s | Secrets moved to env vars; startup log redaction | — |
| CI #12 | `7790e05` | main | ✅ | 1m29s | Docker Hub login step degrading gracefully with no secrets set | `34925562415` |
| CI #13 | `89ef3ae` | main | ✅ | 1m44s | Vault added; all 7 jobs still green | — |
| **CI #14** | `a11b1a7` | main | ✅ | 1m34s | **Reference green run.** Matches current `main`; all job summaries | `34937065696` |
| **CI #15** | `b953365` | test/secrets-gate-blocking-demo | ❌ | 1m32s | **Enforcing security gate blocks a build** (Gitleaks) | `35064195044` |
| CI #16 | `a11b1a7` | member2-threat-model | ✅ | 1m31s | Teammate's branch — pipeline runs on contributors' work, not just the lead's | — |
| CI #17 | `ad4d735` | member2-threat-model | ✅ | 2m8s | Teammate's threat-model commit | — |
| **CI #18** | `ad4d735` | member2-threat-model | ✅ | 1m45s | **`pull_request` trigger gating a real PR** — all four gates ran on a teammate's contribution before merge | — |
| CI #19 | `ac1d960` | main | ✅ | 1m34s | PR #1 merge validated on main | — |
| **CI #20** | `530da90` | main | ✅ | 1m49s | **Docker Hub encrypted secrets authenticating** (`Login Succeeded`) | `36165428549` |

**The two runs that matter most are CI #14 (everything green, all findings
reported) and CI #15 (the enforcing gate blocking).**

**CI #16-#19 were not created by the infrastructure lead.** They are a
teammate's branch pushes, her pull request, and its merge. CI #18 is therefore
unplanned but valuable evidence: the `pull_request:` trigger firing on a real
contribution, with all four security gates running against someone else's work
before it reached `main`. That is the pipeline performing its actual function
rather than a synthetic demonstration, and it could not have been produced by
the pipeline's own author.

### CI #14 job timings — the reference green run

```
Lint and static checks                          23s
Build container image                           25s
Security - SAST (Semgrep)                       32s
Security - Dependency scan (npm audit)          20s
Security - Secrets scan (Gitleaks) [ENFORCING]   7s
Smoke test the running stack                    52s
Security - Container scan (Trivy)               53s
CI status                                        4s
Total                                         1m34s
```

### CI #15 job results — the blocking run

```
Lint and static checks                          ✅ 23s
Build container image                           ✅ 26s
Security - SAST (Semgrep)                       ✅ 31s
Security - Dependency scan (npm audit)          ✅ 19s
Security - Secrets scan (Gitleaks) [ENFORCING]  ❌ 11s   exit code 1
Smoke test the running stack                    ✅ 51s
Security - Container scan (Trivy)               ✅ 45s
CI status                                       ❌  5s   aggregated failure
```

Six jobs green, one red. The fake credential was deliberately placed in a file
**outside jshint's scope** so the run could not fail for two reasons at once.

---

## 2. Evidence already in this repository

No screenshot needed. Cite by file path and line number.

| Artefact | Proves | Supports |
|---|---|---|
| `.github/workflows/ci.yml` (1010 lines) | Full pipeline definition; every gate, threshold and justification is an inline comment | CI/CD pipeline; all four gates |
| `Dockerfile` (72 lines) | Multi-stage build, non-root user, `npm ci` from lockfile, healthcheck | Containerisation |
| `docker-compose.yml` (214 lines) | Full stack in one command; healthcheck gating; named volume; loopback binding; Vault services | Containerisation; trust boundaries |
| `docs/architecture.md` (499 lines) | Components, data flows F1–F7, trust boundaries TB-0 to TB-3, Mermaid diagrams, verification appendix | Architecture documentation |
| `docs/secrets.md` (418 lines) | Full secrets inventory, provisioning, Vault design, 9 named limitations | Secrets management |
| `scripts/smoke-test.sh` (163 lines) | 8 assertions incl. a trust-boundary regression test | Functional testing |
| `.gitleaksignore` (40 lines) | Baseline with per-entry justification and the "never baseline to go green" rule | Secrets scanning |
| `.env.example` (126 lines) | Every variable by name and purpose, never values | Secrets management |
| `docker/vault-init.sh` (177 lines) | AppRole provisioning, least-privilege policy, audit device | Vault (favourable marking) |
| `docker/vault-fetch.js` (134 lines) | Runtime AppRole auth and secret retrieval; never fatal; never logs values | Vault (favourable marking) |
| `docker/entrypoint.sh` (47 lines) | Vault fetch → conditional seed → `exec` as PID 1 | Containerisation; Vault |
| `README.md` (457 lines) | Setup from a fresh clone, reset procedures, upstream attribution and licence | Repository setup |

---

## 3. Screenshots

**All 18 captured.** Files are in [`screenshots/`](screenshots/), named
`<id>-<description>--<run>-<sha>.png`, so each carries its own provenance. The
run-and-commit segment is omitted for captures that are not from a CI run.

**The captures are not all from one run.** Each row below cites its own.

### 3.1 From CI #15 — `b953365` — the blocking run *(run id `35064195044`)*

| # | File | Proves |
|---|---|---|
| **S1** | [`s01-red-job-graph--ci15-b953365.png`](screenshots/s01-red-job-graph--ci15-b953365.png) | Six jobs green, `secrets-scan` red, `ci-status` red. Only the enforcing gate failed. |
| **S2** | [`s02-gitleaks-build-blocked-summary--ci15-b953365.png`](screenshots/s02-gitleaks-build-blocked-summary--ci15-b953365.png) | `Baselined: 2`, `New findings: 2`, `BUILD BLOCKED`, and the two-row findings table. |
| **S3** | [`s03-red-annotations--ci15-b953365.png`](screenshots/s03-red-annotations--ci15-b953365.png) | `3 errors and 2 warnings`, including `Secrets scan FAILED...` and `Process completed with exit code 1`. |
| **S4** | [`s04-gitleaks-gate-decision-log--ci15-b953365.png`](screenshots/s04-gitleaks-gate-decision-log--ci15-b953365.png) | The step log: `Gitleaks exit code: 1` and `BUILD BLOCKED by the secrets gate.` |

> **S2 paired with S7 is the strongest evidence in the set.** Same gate, same
> baseline, one scan passing with 0 new findings and one blocking with 2. That
> pairing is what proves the baseline suppresses *known* findings without
> blinding the gate. S2 alone would only show that the gate can fail.

### 3.2 From CI #20 — `530da90` — the reference green run *(run id `36165428549`)*

| # | File | Proves |
|---|---|---|
| **S0** | [`s00-green-job-graph--ci20-530da90.png`](screenshots/s00-green-job-graph--ci20-530da90.png) | All eight jobs green, with the parallel/dependent structure visible. |
| **S5** | [`s05-semgrep-findings-summary--ci20-530da90.png`](screenshots/s05-semgrep-findings-summary--ci20-530da90.png) | `Total findings: 15 - ERROR: 3, WARNING: 12` and the per-rule table. |
| **S6a** | [`s06a-npm-audit-scope-comparison--ci20-530da90.png`](screenshots/s06a-npm-audit-scope-comparison--ci20-530da90.png) | Production 51 vs full tree 145 — the scoping decision made visible. |
| **S6b** | [`s06b-npm-audit-critical-advisories--ci20-530da90.png`](screenshots/s06b-npm-audit-critical-advisories--ci20-530da90.png) | All 16 critical advisories in production dependencies. |
| **S7** | [`s07-gitleaks-passing-summary--ci20-530da90.png`](screenshots/s07-gitleaks-passing-summary--ci20-530da90.png) | `Baselined: 2`, `New findings: 0`, `Gate passes`. **Pair with S2.** |
| **S8** | [`s08-trivy-layer-split--ci20-530da90.png`](screenshots/s08-trivy-layer-split--ci20-530da90.png) | Base image 0 critical / 4 high vs application dependencies 9 critical / 54 high. |
| **S9** | [`s09-smoke-test-steps--ci20-530da90.png`](screenshots/s09-smoke-test-steps--ci20-530da90.png) | The smoke-test job steps against the running stack. |
| **S10** | [`s10-artifacts-panel-digests--ci20-530da90.png`](screenshots/s10-artifacts-panel-digests--ci20-530da90.png) | Five artifacts with SHA-256 digests. |
| **S13** | [`s13-dockerhub-login-succeeded--ci20-530da90.png`](screenshots/s13-dockerhub-login-succeeded--ci20-530da90.png) | `Login Succeeded` and `Authenticated to Docker Hub as ***` — the encrypted secrets in use. GitHub masks the username because it is a secret. Contrast with CI #12, which logged `using anonymous pulls`. |

> **On CI #20 versus CI #14.** The text extracts in [§4](#4-extracted-text-evidence)
> were taken from CI #14 (`a11b1a7`); these screenshots are from CI #20
> (`530da90`), ten days later. The figures are **identical** — Semgrep 15
> (3 ERROR / 12 WARNING), npm audit 51 production / 145 full tree with the same
> 16 criticals, Gitleaks 2 baselined / 0 new. Verified against both run pages.
> Two independent runs reporting the same numbers strengthens the evidence; it
> also shows the point-in-time caveat on advisory counts did not bite here.

### 3.3 From CI #4 — `55c127d` — the lint gate blocking *(run id `34855795216`)*

| # | File | Proves |
|---|---|---|
| **S11** | [`s11-lint-gate-blocking--ci4-55c127d.png`](screenshots/s11-lint-gate-blocking--ci4-55c127d.png) | Lint red while build and smoke-test stayed green — the clearest visual proof of **job parallelism**, and a second, independent example of a gate blocking a build. |

### 3.4 From pull request #1 — head commit `ad4d735` *(CI #18)*

| # | File | Proves |
|---|---|---|
| **S16** | [`s16-pr1-checks--ci18-ad4d735.png`](screenshots/s16-pr1-checks--ci18-ad4d735.png) | PR #1 with **16 checks passed**. The `pull_request` trigger gating a real contribution from another team member before it reached `main`. |

> **Note on the SHA.** `ad4d735` is PR #1's head commit — verified on the PR
> page, which reads *"merged 1 commit … ad4d735"* and *"16 checks passed"*. CI
> #18 was the `pull_request`-event run for that PR. A `pull_request` run checks
> out a synthetic merge ref rather than the head commit, so CI #18's own
> checkout SHA differs from `ad4d735`; the head commit is the meaningful
> citation and the one the PR page displays.

### 3.5 Not from a CI run

| # | File | Proves |
|---|---|---|
| **S12** | [`s12-repository-secrets.png`](screenshots/s12-repository-secrets.png) | `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN` configured as encrypted repository secrets, values hidden. Repository settings page — no commit. |
| **S14** | [`s14-vault-approle-provisioning.png`](screenshots/s14-vault-approle-provisioning.png) | Vault AppRole provisioning and the application's runtime secret fetch. Local `docker compose` stack — no commit. See [`vault-audit-log.md`](vault-audit-log.md). |
| **S15** | [`s15-app-logged-in.png`](screenshots/s15-app-logged-in.png) | The containerised application running and logged in as `Node Goat Admin`. Local browser — no commit. |

---

## 4. Extracted text evidence

Text pulled out of the runs into this directory so it is citable after the
7-day artifact retention expires.

| File | Contents | Source |
|---|---|---|
| [`sast-semgrep-findings.md`](sast-semgrep-findings.md) | All 15 Semgrep findings by rule and severity | CI #14 job summary |
| [`dependency-npm-audit.md`](dependency-npm-audit.md) | 51 production vs 145 full tree; all 16 critical advisories | CI #14 job summary |
| [`container-trivy-split.md`](container-trivy-split.md) | Base image vs application dependency layer split | Trivy 0.74.0 against the built image |
| [`secrets-gitleaks-baseline.md`](secrets-gitleaks-baseline.md) | Baseline entries, justification, and the blocking run findings | `.gitleaksignore` + CI #14 and CI #15 |
| [`vault-audit-log.md`](vault-audit-log.md) | Audit entries distinguishing root provisioning from AppRole read | Local `docker compose` stack |
| [`pipeline-narrative.md`](pipeline-narrative.md) | Walkthrough of the job graph, dependencies, gate thresholds, enforcement rationale and limitations, plus rehearsal answers for likely viva questions | Working reference |
| [`handover-to-report-author.md`](handover-to-report-author.md) | Handover for whoever writes the technical report: where each artefact lives, the figures that can be quoted with their citations, which screenshot supports which claim, what must NOT be claimed, and the limitations to include | Handover |

---

## 5. Coverage against the brief

| Requirement (as stated in the brief) | Evidence | Status |
|---|---|---|
| Repo setup, not a fork, clean attributable history | `git log` — upstream imported without `.git` at `bd39d5f`; history attributable per member | ✅ |
| Containerisation, single-command startup, offline | `Dockerfile`, `docker-compose.yml`, S15 | ✅ |
| Architecture documentation with trust boundaries | `docs/architecture.md` | ✅ |
| CI pipeline builds and tests on every push | CI #1–#20; S0, S9 | ✅ |
| Pipeline fails on a broken build | CI #4, S11 | ✅ |
| SAST gate | `ci.yml` `sast` job; S5; `sast-semgrep-findings.md` | ✅ |
| Dependency / SCA gate | `ci.yml` `dependency-scan`; S6a, S6b; `dependency-npm-audit.md` | ✅ |
| Secrets scanning gate | `ci.yml` `secrets-scan`; S7; `secrets-gitleaks-baseline.md` | ✅ |
| Container image scanning gate | `ci.yml` `container-scan`; S8; `container-trivy-split.md` | ✅ |
| At least one **enforcing** gate | Gitleaks; `ci.yml` `secrets-scan` "Gate decision (ENFORCING)" | ✅ |
| **Captured evidence of it blocking a build** | **CI #15**; S1–S4 | ✅ |
| GitHub Actions encrypted secrets | `ci.yml` workflow `env:` block; S12, S13; **CI #20** `Login Succeeded` | ✅ |
| Pipeline gates pull requests, not just pushes | **CI #18** — PR #1 from a teammate; S16 | ✅ |
| Secrets management for the application | `docs/secrets.md`; `.env.example`; CI #11 | ✅ |
| Vault / secrets manager injecting at runtime *(favourable marking)* | `docker/vault-init.sh`, `docker/vault-fetch.js`, S14, `vault-audit-log.md` | ✅ |

---

## 6. Gaps and honest caveats

Things a marker could reasonably probe. Better to have answers ready.

| # | Caveat | The honest answer |
|---|---|---|
| **C1** | Three of four gates are **report-only**, not enforcing | Deliberate. SAST, dependency and container findings are NodeGoat's *intentional* vulnerabilities, owned by the remediation workstream and required not to be fixed yet. Enforcing them would make `main` permanently red, and a pipeline that is always red gets ignored. Each gate's `exit 1` is present but commented, so enforcement is visibly deferred rather than absent. |
| **C2** | The Gitleaks baseline suppresses 2 real findings | It is a baseline, not a blanket suppression: entries are exact fingerprints (`commit:file:rule:line`), committed with written justification, and CI #15 proves new secrets are still caught while those 2 stay suppressed. |
| **C3** | `npm audit` excludes dev dependencies | Stated openly and both numbers are printed (51 vs 145). The Dockerfile builds with `npm ci --omit=dev`, so dev dependencies are provably not in the runtime image. |
| **C4** | CI #7 was an unplanned red run | A shell quoting bug, not a gate finding: an apostrophe in prose inside a single-quoted `node -e` script caused bash to exit 2. Fixed structurally with a quoted heredoc in CI #8. Worth keeping in the report — it shows the pipeline caught a real defect in its own configuration. |
| **C5** | `npm test` runs zero tests | Upstream ships no `test/unit/` directory, so `npm test` reports "No files to check...OK". Kept and clearly labelled rather than hidden; real verification is the 8-assertion smoke test. |
| **C6** | SARIF is not uploaded to the Security tab | Code scanning requires GitHub Advanced Security on private repositories; `/security/code-scanning` returns 404. The step is skipped rather than failing, and findings go to job summaries and artifacts instead. |
| **C7** | Vault runs in dev mode | In-memory, auto-unsealed, no TLS. Appropriate for a teaching lab, explicitly not production. Nine limitations are enumerated in `docs/secrets.md` §8, including secret zero. |
| **C8** | Old secrets remain in git history | Deliberate: teammates have clones, and none of the values were ever live. Documented in `docs/secrets.md` §7. Rotation, not history rewriting, is what actually ends an exposure. |
| **C9** | Artifacts expire after 7 days | Run pages and job summaries persist; the numbers that matter are extracted into [§4](#4-extracted-text-evidence). |
| **C10** | CI #15's branch was deleted | The run and its summaries persist, exactly as for CI #4. The credential was randomly generated and never valid in any account. |

---

## 7. Evidence owned by other team members

Listed so this index accounts for everything under `docs/`, and so nobody
assumes an unlisted directory is stray. **These artefacts were produced by other
members and are not reviewed or verified here** — their authors own their
accuracy.

| Artefact | Author | Contents |
|---|---|---|
| [`../threat-model.md`](../threat-model.md) | Member 2 (`IT24103261`) | STRIDE threat model and risk assessment: scope and method, STRIDE categories, identified threats, risk assessment, threat-to-control mapping |
| [`../images/nodegoat-architecture-diagram.drawio.png`](../images/nodegoat-architecture-diagram.drawio.png) | Member 2 (`IT24103261`) | Rendered architecture diagram, embedded at the top of `docs/architecture.md` |
| [`../vulnerabilities.md`](../vulnerabilities.md) | Member 3 (`IT24102157`) | Vulnerability assessment and secure-coding evidence: STRIDE/OWASP mapping, exploit-and-fix write-ups for A1, A3, A4, A7, further findings for A2, A5 and A8, and a handoff checklist |
| [`exploits/`](exploits/) | Member 3 (`IT24102157`) | 22 exploit screenshots covering A1 NoSQL injection, A2 authentication findings, A3 XSS, A4 IDOR, A7 access control, plus T2/T3/T4 and a Semgrep baseline capture |

### Note on `docs/evidence/exploits/`

That directory sits inside `docs/evidence/` but belongs to Member 3's
workstream. The pipeline evidence in sections 1–6 is independent of it.

### Relationship to this index

The two bodies of evidence are complementary and should not be conflated:

- **This index** shows that the pipeline *detects* problems — Semgrep finding
  the `eval()` injection, the enforcing gate blocking a build, Trivy separating
  base-image from application CVEs.
- **Member 3's material** shows those problems being *exploited* against the
  running application.

Where they overlap — for example Semgrep's `code-string-concat` finding at
`app/routes/contributions.js:32-34` and an exploited NoSQL injection — the
agreement between a static finding and a demonstrated exploit is worth pointing
out in the report, since it shows the gate flags something genuinely reachable
rather than a theoretical pattern.

---

*Evidence index for the IE3142 DevOps Security group assignment. Compiled at
commit `a11b1a7`. See [`pipeline-narrative.md`](pipeline-narrative.md) for the
walkthrough of pipeline design decisions.*
