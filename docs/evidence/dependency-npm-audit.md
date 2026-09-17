# Evidence — Dependency / SCA scan (npm audit)

**Source:** `Security - Dependency scan (npm audit)` job summary
**Run:** CI #14 · commit `a11b1a7` · run id `34937065696` · job duration 20s
**Tool:** `npm audit` (npm 10.x, Node 20) against `package-lock.json`
**Scope:** `--omit=dev` for the reported figure; full tree also run for comparison
**Gate status:** report-only (threshold: critical)

---

## Production vs full tree

```
| Scope                                      | Critical | High | Moderate | Low | Total |
| Production (--omit=dev, what ships)        |    16    |  24  |    5     |  6  |   51  |
| Full tree (incl. dev, for comparison)      |    38    |  66  |   33     |  8  |  145  |
```

## Why both numbers are printed

The `--omit=dev` scope is the significant decision in this gate, so **both
figures are surfaced rather than only the smaller one**.

The justification is concrete rather than convenient: `Dockerfile` builds the
runtime image with `npm ci --omit=dev`, so development dependencies (grunt,
cypress, mocha, jshint) are **provably absent from the shipped image** and are
not attack surface for the deployed application. Scanning them inflates the
count without reflecting real risk.

Reporting 51 while showing that the full tree is 145 is **scoping with a stated
reason**. Reporting 51 alone, without the comparison, would be suppression. The
distinction matters and is the defensible position.

---

## All 16 critical advisories in production dependencies

| Package | Advisory |
|---|---|
| `underscore` | **Arbitrary Code Execution** |
| `swig` | **Arbitrary local file read** during template rendering |
| `bson` | Deserialization of Untrusted Data |
| `fsevents` | **Malware in fsevents** |
| `tar` | Arbitrary File Creation/Overwrite due to insufficient absolute path sanitization |
| `mongodb` | Denial of Service |
| `minimist` | Prototype Pollution |
| `mixin-deep` | Prototype Pollution |
| `nconf` | Prototype Pollution |
| `set-value` | Prototype Pollution |
| `flatiron` | (vulnerable transitive dependency) |
| `forever` | (vulnerable transitive dependency) |
| `mkdirp` | (vulnerable transitive dependency) |
| `mongodb-core` | (vulnerable transitive dependency) |
| `optimist` | (vulnerable transitive dependency) |
| `union-value` | (vulnerable transitive dependency) |

### Not theoretical

`underscore` and `swig` are both **declared directly** in `package.json` and both
are loaded by the running application — `swig` is the template engine and
`underscore` is used in `config/config.js`. These are not distant transitive
dependencies that never execute.

---

## Why this gate is report-only

These are OWASP **A9 — Using Components with Known Vulnerabilities**, which is
one of the risks NodeGoat exists to demonstrate. They are unfixable without
replacing the dependency tree, which would destroy the teaching material and is
owned by the remediation workstream.

The run annotation records that the gate reported rather than blocked:

```
Dependency scan found 16 critical advisory/advisories in production
dependencies. Reported, not enforced - these are NodeGoat's intentional
vulnerable dependencies (OWASP A9), owned by the remediation workstream.
```

As with the other report-only gates, the `exit 1` is present and commented in
`.github/workflows/ci.yml`.

---

## Tool selection note

`npm audit` was chosen over Snyk and OWASP Dependency-Check specifically because
it needs **no credentials**:

- Snyk requires a `SNYK_TOKEN` repository secret.
- OWASP Dependency-Check downloads the full NVD feed on every run (minutes, not
  seconds) and targets Java ecosystems.

This gate also needs **no `npm ci` step** — `npm audit` resolves
`package-lock.json` against the registry advisory API without `node_modules`
present, which is why it is the fastest of the four gates at 20s.

---

## Reproducing this locally

```bash
npm audit --omit=dev            # production: 51
npm audit                       # full tree: 145
```

Counts are **point-in-time**. The registry advisory database is updated
continuously, so a later run may report different totals as new advisories are
published. The figures above are those reported by CI #14.

---

## Artifacts

`dependency-scan-npm-audit-results` (25.1 KB) contains `audit-prod.json` and
`audit-all.json` with full advisory detail, CVSS scores and dependency paths.

**Expires 7 days after the run.** This file is the durable record.

---

*Extracted from CI #14 for the IE3142 technical report. See
[README.md](README.md) for the full evidence index.*
