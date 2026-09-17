# Evidence — Secrets scan (Gitleaks), the enforcing gate

**Tool:** `zricethezav/gitleaks:v8.30.1` (pinned)
**Scope:** working tree **and full git history** (`fetch-depth: 0` on checkout)
**Gate status:** **ENFORCING** — any finding outside the baseline fails the build

This is the only one of the four security gates that blocks.

---

## 1. The baseline

`.gitleaksignore` contains exactly **two** entries:

```
bd39d5f46cbbc89dce8931c2aedabfef2b9bc794:config/env/development.js:generic-api-key:6
bd39d5f46cbbc89dce8931c2aedabfef2b9bc794:config/env/test.js:generic-api-key:6
```

### What they are

Both are the **same OWASP ZAP API key**, which upstream NodeGoat duplicated into
its development and test configs:

| Property | Value |
|---|---|
| Rule | `generic-api-key` |
| Entropy | 4.056 |
| Introduced in | `bd39d5f` — the NodeGoat import commit |
| Consumer | `test/security/profile-test.js` only |

### Why they are acceptable

- The value is **published in the public OWASP/NodeGoat repository** — it is not
  a live credential.
- It refers to a ZAP proxy at a hardcoded VirtualBox address
  (`192.168.56.20:8080`) that does not exist in this environment.
- The suite that consumes it **cannot run** — it additionally requires
  `chromedriver`, which is not even a declared dependency.
- It is **deliberately retained** as the demonstration finding for this gate.

### Why fingerprints rather than path or regex allowlists

Entries are exact fingerprints (`commit:file:rule:line`), which was a deliberate
choice over the alternatives:

| Approach | Problem |
|---|---|
| Path allowlist (`config/env/*.js`) | Exempts the **whole file forever** — a genuinely new secret dropped into `development.js` would pass unnoticed |
| Regex allowlist (the secret value) | Requires **pasting the secret into another tracked file** |
| **Exact fingerprint** ✅ | Covers **one specific finding**. A different secret in the same file, or the same secret in a new commit, still fails |

### The rule that makes this a baseline, not suppression

`.gitleaksignore` carries this instruction in its header:

> **Never add an entry to make a red build go green.** If the gate fires, a new
> secret has been introduced — remove the secret, do not baseline it.

Every entry states what the secret is and why it is acceptable. The file is
committed and reviewable, and every scan report is uploaded as a CI artifact.

---

## 2. The gate passing — CI #14

**Run:** CI #14 · commit `a11b1a7` · run id `34937065696` · job duration 7s

```
Secrets scan (Gitleaks) - ENFORCING GATE

Baselined known upstream findings: 2
New findings this run: 0

No new secrets detected. Gate passes.
```

---

## 3. The gate BLOCKING — CI #15

**Run:** CI #15 · commit `b953365` · run id `35064195044` · **Status: Failure**
Branch `test/secrets-gate-blocking-demo` (deleted; the run persists)

A randomly generated fake AWS credential was committed to a throwaway branch in
`ci-secrets-gate-demo.json`, a file **deliberately placed outside jshint's
scope** so that only the secrets gate could fail and the evidence would be
unambiguous.

### Job results — six green, one red

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

### The job summary

```
Secrets scan (Gitleaks) - ENFORCING GATE

Baselined known upstream findings: 2
New findings this run: 2

BUILD BLOCKED. A secret that is not in the baseline was detected.

| Rule             | File                      | Line | Commit     | Entropy |
| aws-access-token | ci-secrets-gate-demo.json |   4  | b953365f20 |  3.621  |
| generic-api-key  | ci-secrets-gate-demo.json |   5  | b953365f20 |  4.871  |

Secret values are redacted from logs deliberately: CI logs are themselves a
disclosure channel.

Do not add these to .gitleaksignore to make the build pass. Remove the secret,
rotate it if it was ever real, and purge it from git history.
```

### Annotations

```
3 errors and 2 warnings

Security - Secrets scan (Gitleaks) [ENFORCING]
  Process completed with exit code 1.

Security - Secrets scan (Gitleaks) [ENFORCING]
  Secrets scan FAILED. A secret not present in the baseline was detected.
  Remove it and purge it from git history - do not add it to .gitleaksignore.

CI status
  Process completed with exit code 1.
```

### Why this run is the decisive evidence

**`Baselined: 2` and `New findings: 2` appear in the same scan.** The two known
upstream findings stayed suppressed *while* two brand-new secrets were caught.

That single fact is what proves the baseline is a baseline and not a blanket
suppression — the most likely challenge to this design, answered by the tool's
own output rather than by assertion.

---

## 4. An unplanned result worth reporting

The first attempt at this demonstration used AWS's canonical documentation
credential (`AKIAIOSFODNN7EXAMPLE`). **Gitleaks correctly did not flag it:**

```
INF no leaks found
>>>>>> EXIT CODE: 0 <<<<<<
```

Gitleaks carries stopwords for well-known example credentials to avoid false
positives. Genuinely random high-entropy values had to be generated for the gate
to fire.

This is worth including in the report for two reasons: it shows the scanner
performs entropy and allowlist analysis rather than naive pattern matching, and
it pre-empts any suggestion that the demonstration was rigged to succeed.

---

## 5. Baseline accuracy checks

A stale baseline entry — one kept after the underlying secret was removed —
would be exactly the silent suppression this project committed to avoiding. The
baseline was therefore re-verified after every change in Phase 5:

```
actual findings : 2   baseline entries : 2

  [VALID] bd39d5f…:config/env/development.js:generic-api-key:6
  [VALID] bd39d5f…:config/env/test.js:generic-api-key:6

unbaselined findings (would fail the gate): 0

RESULT: no stale entries - baseline is accurate.
```

**Note on why no entry needed removing.** The secrets removed in Phase 5
(`cookieSecret`, `cryptoKey`) were **never Gitleaks findings** — they are
low-entropy placeholder strings that the `generic-api-key` rule does not match.
The baseline is accurate by construction, not by luck.

### Reproducing the check

Gitleaks **auto-loads `.gitleaksignore` from the scan root**, regardless of the
`--gitleaks-ignore-path` flag, so the file must be moved aside to see raw
findings:

```bash
mv .gitleaksignore .gitleaksignore.bak
docker run --rm -v "$PWD:/repo" zricethezav/gitleaks:v8.30.1 \
  detect --source /repo --no-banner --redact \
  --report-format json --report-path /repo/raw.json
mv .gitleaksignore.bak .gitleaksignore
```

That auto-loading behaviour is itself a limitation: anyone could silence a
finding by editing the file. It is mitigated by the file being committed,
commented and reviewable — by review, not by tooling. Recorded as limitation L9
in `docs/secrets.md`.

---

## 6. Why this is the gate that enforces

| Reason | Detail |
|---|---|
| **Binary risk** | There is no defensible "acceptable number of leaked secrets", unlike CVE counts where risk is graduated |
| **Near-zero noise** | 2 precise findings on this repository, both known |
| **No conflict with other workstreams** | A *new* secret is never intentional NodeGoat behaviour. The SAST and dependency gates cannot say that — their findings are deliberate and teammates are required not to fix them |

Supporting properties:

- **`fetch-depth: 0`** — the default shallow checkout would let Gitleaks see only
  the newest commit. Since the whole value of history scanning is catching a
  secret that was committed and *later deleted*, a shallow checkout would gut the
  gate while still reporting green.
- **`--redact`** — secret values never reach CI logs, which are themselves a
  disclosure channel.
- **Pinned to `v8.30.1`**, not `:latest`, so scan results are reproducible.
- **Container, not `gitleaks-action`** — the action requires a
  `GITLEAKS_LICENSE` for organization accounts.

---

## Artifacts

| Run | Artifact | Size |
|---|---|---|
| CI #14 | `secrets-scan-gitleaks-report` | 159 bytes (empty findings array) |
| CI #15 | `secrets-scan-gitleaks-report` | 1.07 KB (the two blocking findings) |

**Expire 7 days after each run.** This file is the durable record.

---

*Compiled from `.gitleaksignore`, CI #14 and CI #15 for the IE3142 technical
report. See [README.md](README.md) for the full evidence index.*
