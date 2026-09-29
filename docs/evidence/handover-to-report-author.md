# Handover — Infrastructure & CI/CD workstream

**From:** IT24101804 (infrastructure / CI-CD lead)
**To:** whoever is writing the technical report
**Covers:** containerisation, the CI/CD pipeline, the four security gates, secrets management

Everything below is finished, pushed to `main`, and evidenced. This document
tells you where each piece lives, what you can safely claim, and what you must
not claim.

**The other workstreams are not mine.** `IT24103261` owns the threat model and
architecture diagram; `IT24102157` owns the vulnerability assessment and
exploits; `IT24101532` made the application fixes. Ask them about those — I have
not reviewed them and cannot vouch for them.

---

## 1. Where everything is

| You need | Read this |
|---|---|
| The full evidence list, with run numbers and commits | [`README.md`](README.md) |
| How the pipeline works and why it is built that way | [`pipeline-narrative.md`](pipeline-narrative.md) |
| Architecture, data flows, trust boundaries | [`../architecture.md`](../architecture.md) |
| Secrets management and Vault | [`../secrets.md`](../secrets.md) |
| Setup instructions, attribution, licence | [`../../README.md`](../../README.md) |
| Screenshots | [`screenshots/`](screenshots/) — 18 files |
| Scanner findings as citable text | the four `*-findings`/`*-audit`/`*-split`/`*-baseline` files in this folder |

**Start with [`pipeline-narrative.md`](pipeline-narrative.md).** It was written
for exactly this purpose and section 7 has short answers to the questions a
marker is most likely to ask.

---

## 2. What was built, in one paragraph

The OWASP NodeGoat application was containerised into a two-service Docker
Compose stack (Node.js 20 app + MongoDB 4.4) that starts with one command and
runs entirely offline. A GitHub Actions pipeline runs on every push and pull
request: it lints, builds the container image, starts the full stack and runs
an 8-assertion smoke test against it, and applies four security gates — Semgrep
(SAST), npm audit (dependencies), Gitleaks (secrets), and Trivy (container
image), two of which enforce. Secrets were removed from source and are
provisioned at runtime from the environment, with HashiCorp Vault as an optional source using AppRole
authentication.

---

## 3. Numbers you can quote

All verified against real runs. **Cite the run and commit, not just the number.**

### Pipeline

| Fact | Value | Source |
|---|---|---|
| Jobs in the pipeline | 8 | `.github/workflows/ci.yml` |
| Typical end-to-end time | ~1m 30s | CI #20, commit `530da90` |
| Smoke-test assertions | 8, all passing | CI #20 |
| Total CI runs to date | 20+ | Actions tab |

### Gate findings

| Gate | Tool | Findings | Enforces? |
|---|---|---|---|
| SAST | Semgrep | **0 ERROR, 11 WARNING** — was 15 total / 3 ERROR before remediation | **YES** |
| Dependencies | npm audit | **51 production** (16 critical, 24 high, 5 moderate, 6 low) · **145 full tree** (38/66/33/8) | no |
| Secrets | Gitleaks | **2 baselined, 0 new** — gate passes | **YES** |
| Container | Trivy | **9 critical, 58 high** — of which base image is **0 critical, 4 high** | no |

Dependency, secrets and container figures are from CI #20 (`530da90`). The SAST
figure is post-remediation, verified at `69c03ca`; the pre-remediation figure is
what screenshot S5 shows.

### The blocking run — CI #15, commit `b953365`

| Fact | Value |
|---|---|
| Result | **Failure** — build blocked |
| Jobs | 6 green, `secrets-scan` red, `ci-status` red |
| Gitleaks output | `Baselined: 2`, **`New findings: 2`**, `BUILD BLOCKED` |

---

## 4. The points worth making

If the report only has room for a few claims from this workstream, make these.

### 4.1 The gates are real, not decoration

NodeGoat's own tooling **hides failures**. `Gruntfile.js:156` sets
`grunt.option("force", true)`, which downgrades every task failure to a warning
and still exits 0 — two genuine lint errors produced `Used --force, continuing`
and exit code **0**. `npm test` maps to a directory (`test/unit/`) that does not
exist, so it reports `No files to check...OK` and always passes.

The pipeline therefore invokes `jshint` **directly**, bypassing Grunt, which
restores an honest exit code. Without that, the lint gate would have been green
no matter what anyone committed.

*This is the single best point in the workstream.* It shows the pipeline was
verified rather than assumed.

### 4.2 The pipeline drove a real fix, then tightened

Semgrep found NodeGoat's `eval()` code injection at
`app/routes/contributions.js` as **3 ERROR findings**, using stock rulesets and
no custom configuration. The gate was report-only then, because that
vulnerability belonged to another workstream and enforcing would have left
`main` permanently red.

The fixes landed — `eval()` replaced with a validated numeric parser, and the
`/learn` open redirect restricted. Re-scanned: **ERROR 3 to 0, total 15 to 11.**
The gate was switched to **enforcing**, so a reintroduction now blocks the
build. The scanner image was pinned in the same change, because an unpinned
scanner behind an enforcing gate can redden `main` with no code change at all
when a new rule ships upstream.

**That is the whole DevSecOps loop, evidenced at both ends:** detect, fix,
tighten. Before and after figures are in
[`sast-semgrep-findings.md`](sast-semgrep-findings.md).

### 4.3 The enforcing gate demonstrably blocks a build

A randomly generated fake AWS credential was pushed to a throwaway branch.
CI #15 went red on `secrets-scan` only — the credential was deliberately placed
in a file outside the linter's scope so the run could not fail for two reasons
at once.

The decisive detail: **`Baselined: 2` and `New findings: 2` in the same scan.**
The two known upstream findings stayed suppressed *while* two new secrets were
caught. That is what proves the baseline is a baseline and not a blanket
suppression.

Screenshots **S2** (blocked) and **S7** (passing) side by side make this point
better than any paragraph.

### 4.4 The Trivy layer split

"67 critical and high findings in our image" is true but useless. The scan
separates them:

```
Base image (Alpine OS packages)      0 critical,  4 high
Application dependencies (Node.js)   9 critical, 54 high
```

**Zero critical findings attributable to the base image we chose.** Everything
else is NodeGoat's 2016-era dependency tree. This also retrospectively justifies
the Phase 1 decision to move off the end-of-life `node:12-alpine`.

### 4.5 Secrets are provisioned, not hardcoded

Three-layer chain, no hardcoded fallback anywhere:

```
HashiCorp Vault (AppRole)  →  environment / .env  →  random ephemeral key
```

Vault generates the secret **inside Vault** — the value exists in no file in the
repository. Verified: `.env` blank, yet the running process holds a 64-character
value matching Vault exactly, with **0 occurrences** in `docker inspect` or in
any container log. The audit log distinguishes the provisioning read
(`policies: ["root"]`) from the application read
(`policies: ["default","nodegoat-app"]`), 31 ms apart.

---

## 5. Which screenshot for which point

All in [`screenshots/`](screenshots/). Filenames carry their own run and commit.

| Making this point | Use |
|---|---|
| Pipeline runs green, all gates present | **S0** |
| Enforcing gate blocks a build | **S1, S2, S3, S4** |
| Baseline suppresses known but catches new | **S2 + S7 together** |
| SAST findings (pre-fix baseline) | **S5** |
| Dependency scoping (51 vs 145) | **S6a**, then **S6b** for the criticals |
| Container layer split | **S8** |
| Smoke test against running stack | **S9** |
| Artifacts with digests | **S10** |
| Job parallelism / second blocking example | **S11** |
| Encrypted secrets configured | **S12** |
| Encrypted secrets in use | **S13** |
| Vault runtime injection | **S14** |
| Application actually works | **S15** |
| Pipeline gates a real teammate PR | **S16** |

---

## 6. What NOT to claim

Getting these wrong is worse than omitting them.

| Do not say | Say instead |
|---|---|
| "All four gates block the build" | **Two** enforce — Semgrep (ERROR severity) and Gitleaks (any finding). Dependency and container scanning report only, because their findings are NodeGoat's intentional vulnerable dependencies and base-image CVEs that this pipeline is not permitted to fix. |
| "The pipeline prevents bad merges" | It **reports** on every push and pull request. Branch protection is **not enabled**, so nothing currently *prevents* a merge. The `ci-status` job exists so a single required check can be enabled. |
| "npm test runs our tests" | `npm test` runs **zero** tests. It is kept and clearly labelled. The real verification is the 8-assertion smoke test. |
| "Findings are in the GitHub Security tab" | They are not. Code scanning needs GitHub Advanced Security on private repos; `/security/code-scanning` returns 404. Findings go to job summaries and artifacts. |
| "We fixed the vulnerabilities" | Not this workstream — the infrastructure lead changed no application code. The fixes were made by `IT24101532`; the assessment and exploits by `IT24102157`. Ask them. |
| "Vault fully solves secrets management" | It does not. Bootstrapping Vault still needs a token — the "secret zero" problem. Vault runs in dev mode: in-memory, auto-unsealed, no TLS. |

---

## 7. Limitations to include

A report that names its limitations scores better than one that pretends there
are none. Full list in [`README.md` §6](README.md#6-gaps-and-honest-caveats) and
[`pipeline-narrative.md` §6](pipeline-narrative.md#6-honest-limitations). The
ones worth space:

1. **Branch protection is not enabled** — the pipeline reports but does not
   prevent. The aggregating job was built so one required check could enable it.
2. **Two of four gates are report-only** — deliberate, for the reason in §6
   above. Semgrep left that category once its findings were genuinely fixed.
3. **Vault runs in dev mode** — appropriate for a teaching lab, explicitly not
   production. Nine limitations are enumerated in `../secrets.md` §8.
4. **Old secrets remain in git history** — deliberately not rewritten, because
   teammates had already cloned and none of the values were ever live. Worth
   adding: *rotation, not history rewriting, is what actually ends an exposure*,
   since any clone made before a rewrite still holds the old value.
5. **Scan counts are point-in-time** — advisory databases update continuously.

### One unplanned event worth including

**CI #7 failed unexpectedly.** Not a gate finding — a shell quoting bug: an
apostrophe in English prose inside a single-quoted script caused bash to exit 2.
Fixed structurally in CI #8 using a quoted heredoc, which cannot be broken by
its own text.

Include it. It shows the pipeline caught a real defect in its own configuration,
and that the fix addressed the class of bug rather than the instance. Hiding it
gains nothing and a marker can see the red run anyway.

---

## 8. Attribution and licence — do not omit

The application is **OWASP NodeGoat**, imported at commit
**`c5cb68a7084e4ae7dcc60e6a98768720a81841e8`** (branch `master`, dated
2023-06-21), under the **Apache License 2.0**.

The repository is **not a fork** — the upstream tree was copied without its
`.git` history so each member's contributions stay individually attributable.
`LICENSE` is retained unmodified at the repository root, and the files this team
added and modified are listed in the root `README.md` under "Licence
compliance", as Apache-2.0 §4(b) requires.

These details are also on the ethical clearance form. Keep them consistent.

---

## 9. Questions

| Topic | Ask |
|---|---|
| Pipeline, gates, containers, secrets, Vault | IT24101804 (me) |
| Threat model, architecture diagram | Member 2 — IT24103261 |
| Vulnerability assessment, exploits | Member 3 — IT24102157 |

If something in my documents contradicts something in theirs, tell me — I would
rather fix it before submission than have a marker find it.

---

*Handover for the IE3142 DevOps Security group assignment. Infrastructure and
CI/CD workstream. See [`README.md`](README.md) for the full evidence index.*
