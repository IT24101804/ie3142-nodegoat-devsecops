# Evidence — SAST (Semgrep) findings, before and after remediation

**Tool:** Semgrep, rulesets `p/javascript`, `p/nodejs`, `p/owasp-top-ten`
**Scope:** `app config server.js artifacts`, excluding `app/assets/vendor` and `node_modules`
**Gate status:** **ENFORCING** (threshold: ERROR severity)

This gate has two states worth recording, because the transition between them is
the evidence. It detected a real vulnerability, the remediation workstream fixed
it, and the gate was then switched from report-only to enforcing.

---

## 1. Before remediation

**Source:** `Security - SAST (Semgrep)` job summary
**Run:** CI #20 · commit `530da90` · also identical in CI #5, #6, #8–#15
**Gate status at the time:** report-only
**Screenshot:** `S5` — [`s05-semgrep-findings-summary--ci20-530da90.png`](screenshots/s05-semgrep-findings-summary--ci20-530da90.png)

```
Total findings: 15  -  ERROR: 3, WARNING: 12
```

| Severity | Count | Rule | Locations |
|---|---|---|---|
| **ERROR** | 3 | `code-string-concat` | `app/routes/contributions.js:32`, `:33`, `:34` |
| WARNING | 5 | `plaintext-http-link` | `app/views/tutorial/a2.html:207`, `:209`, `:210` (+2) |
| WARNING | 1 | `express-open-redirect` | `app/routes/index.js:72` |
| WARNING | 6 | `express-cookie-session-*` | `server.js:78` |

### What the ERROR findings were

`code-string-concat` at `app/routes/contributions.js:32-34` was NodeGoat's
**`eval()` code injection** — its headline OWASP A1 demonstration. Semgrep
located it with stock rulesets and no custom configuration.

That is the strongest single fact about this gate: it did not merely run, it
found the exact vulnerability the application was built to contain, and it found
it before anyone went looking.

---

## 2. After remediation

**Verified:** 2026-09-29 against commit `69c03ca`, using the pinned scanner
version the gate now runs (`semgrep/semgrep:1.176.1`), same rulesets and scope.

```
Total findings: 11  -  ERROR: 0, WARNING: 11
```

| Severity | Count | Rule | Locations |
|---|---|---|---|
| WARNING | 5 | `plaintext-http-link` | `app/views/tutorial/a2.html:207`, `:209` (+3) |
| WARNING | 1 | `express-cookie-session-default-name` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-domain` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-expires` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-httponly` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-path` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-secure` | `server.js:78` |

### What changed, and why

| Finding | Status | Fix |
|---|---|---|
| `code-string-concat` ×3 (**ERROR**) | **Resolved** | `c0e4576` — `fix(A1): remove eval from contributions handler`. The `eval()` was replaced with a regex-validated numeric parser that rejects anything other than a plain number. |
| `express-open-redirect` ×1 (WARNING) | **Resolved** | `984473c` — `fix(A7,A10): admin check on benefits and restrict /learn redirect`. |

15 − 4 = 11. The remaining 11 are unchanged.

**These are genuine fixes, not suppression.** No rule was disabled, no threshold
lowered, no path excluded. The findings disappeared because the vulnerable code
was removed. Remediation is owned by another team member
(`IT24101532`); this workstream did not modify application code.

---

## 3. The gate transition

| | Before | After |
|---|---|---|
| ERROR findings | 3 | **0** |
| Total findings | 15 | 11 |
| Gate | report-only | **ENFORCING** |
| Scanner image | `semgrep/semgrep:latest` | `semgrep/semgrep:1.176.1` (pinned) |

### Why it was report-only at first

Enforcing a gate whose findings were NodeGoat's *intentional* vulnerabilities
would have left `main` permanently red over code this pipeline was not permitted
to change. A pipeline that is always red gets ignored, which is a worse security
outcome than no gate at all. The `exit 1` was present but commented, so the
decision was visible rather than absent.

### Why it enforces now

The ERROR count reached 0 through real fixes, so the gate can block without
conflicting with another workstream. A reintroduction of `eval()` — or any other
ERROR-severity pattern — now fails the build:

```bash
if [ "$ERRORS" -gt 0 ]; then
  echo "::error::SAST FAILED. $ERRORS ERROR-severity finding(s) detected. Fix the finding - do not lower the threshold."
  echo "BUILD BLOCKED by the SAST gate."
  exit 1
fi
```

### Why the image was pinned at the same time

Semgrep was the only scanner still on `:latest`; Gitleaks and Trivy were already
pinned. **An unpinned scanner behind an enforcing gate can turn `main` red with
no code change at all** — a new rule ships upstream and the build fails. Pinning
to the exact version the 0-ERROR result was verified against removes that.

This is a real operational point, not a formality: enforcement and
reproducibility have to arrive together.

---

## 4. Why the threshold is ERROR, not WARNING

The noise is asymmetric, and measurably so.

| | Before | After |
|---|---|---|
| ERROR findings that were false positives | 0 of 3 | — |
| WARNING findings that are false positives | 5 of 12 | 5 of 11 |

The 5 `plaintext-http-link` findings are `http://` **hyperlinks in tutorial
documentation pages**, not insecure application traffic. Genuine false positives
for our purposes.

**0% noise at ERROR, roughly 45% at WARNING.** That asymmetry is the
justification for the threshold, and it is why the gate could be switched to
enforcing without also becoming a nuisance.

The 6 remaining `express-cookie-session-*` findings at `server.js:78` are real —
the session cookie is configured without `secure`, `httpOnly`, `path`, `domain`,
`expires` or a non-default name. They are reported, not enforced, and remain
open for the remediation workstream.

---

## 5. Known tool caveat

Semgrep logs `PartialParsing` notices against `app/views/*.html`. Those files
contain Swig template syntax (`{{ … }}`) its HTML parser cannot fully consume. It
still scans what it can parse. A parser limitation, not a scan failure — but it
appears in the job log and is worth recognising rather than mistaking for an
error.

---

## 6. Reproducing this

```bash
docker run --rm -v "$PWD:/src" -w /src semgrep/semgrep:1.176.1 \
  semgrep scan \
    --config p/javascript --config p/nodejs --config p/owasp-top-ten \
    --exclude 'app/assets/vendor' --exclude 'node_modules' --metrics=off \
    --json-output=/src/semgrep.json --quiet \
    app config server.js artifacts
```

Because the image is pinned, this is reproducible. The pre-remediation figures
are not reproducible from current `main` — the vulnerable code is gone. They
remain citable from CI #20's job summary and screenshot S5.

---

## Artifacts

`sast-semgrep-results` contains `semgrep.sarif` and `semgrep.json` with full
finding detail. CI artifacts carry `retention-days: 7`, so this file is the
durable record.

---

*Compiled for the IE3142 technical report. Pre-remediation figures from CI #20
(`530da90`); post-remediation verified at `69c03ca`. See [README.md](README.md)
for the full evidence index.*
