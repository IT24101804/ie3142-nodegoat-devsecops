# Evidence — SAST (Semgrep) findings

**Source:** `Security - SAST (Semgrep)` job summary
**Run:** CI #14 · commit `a11b1a7` · run id `34937065696` · job duration 32s
**Tool:** `semgrep/semgrep` (container), rulesets `p/javascript`, `p/nodejs`, `p/owasp-top-ten`
**Scope:** `app config server.js artifacts`, excluding `app/assets/vendor` and `node_modules`
**Gate status:** report-only (threshold ERROR)

Identical output appears in CI #5, #6, #8–#15 — the findings have not changed
since the gate was added, because no application code has been modified.

---

## Totals

```
Total findings: 15  -  ERROR: 3, WARNING: 12
```

## All findings by rule

| Severity | Count | Rule | Locations |
|---|---|---|---|
| **ERROR** | 3 | `code-string-concat` | `app/routes/contributions.js:32`, `:33`, `:34` |
| WARNING | 5 | `plaintext-http-link` | `app/views/tutorial/a2.html:207`, `:209`, `:210` (+2) |
| WARNING | 1 | `express-open-redirect` | `app/routes/index.js:72` |
| WARNING | 1 | `express-cookie-session-default-name` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-domain` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-expires` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-httponly` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-path` | `server.js:78` |
| WARNING | 1 | `express-cookie-session-no-secure` | `server.js:78` |

---

## What the findings actually are

### The 3 ERROR findings — NodeGoat's flagship vulnerability

`code-string-concat` at `app/routes/contributions.js:32-34` is NodeGoat's
**`eval()` code injection**, its headline OWASP A1 demonstration. Semgrep located
it with stock rulesets and no custom configuration.

This is the strongest single argument that the SAST gate works: it did not just
run, it found the exact vulnerability the application was built to contain.

### Genuine findings among the WARNINGs

- `express-open-redirect` at `app/routes/index.js:72` — the deliberate open
  redirect.
- The six `express-cookie-session-*` findings at `server.js:78` — the session
  cookie configured without `secure`, `httpOnly`, `path`, `domain`, `expires` or
  a non-default name. These correspond to the `cookieSecret` issue recorded in
  the Phase 1 inventory.

### Noise, stated openly

The 5 `plaintext-http-link` findings are `http://` **hyperlinks in tutorial
documentation pages**, not insecure application traffic. They are genuine false
positives for our purposes.

**That is 5 of 15 findings — roughly 33% noise at WARNING level, and 0% at ERROR
level.** That asymmetry is the justification for setting the threshold at ERROR
rather than filtering rules individually.

---

## Why this gate is report-only

Every ERROR finding is an intentional NodeGoat vulnerability owned by the
remediation workstream, which is required not to fix them yet. Enforcing here
would leave `main` permanently red for work this pipeline is not permitted to
change.

The `exit 1` that would make the gate enforcing is present and commented in
`.github/workflows/ci.yml`, so enforcement is visibly deferred rather than
absent:

```bash
if [ "$ERRORS" -gt 0 ]; then
  echo "::warning::SAST found $ERRORS ERROR-severity finding(s). ..."
  echo "Gate is REPORT-ONLY. Not failing the build."
  # exit 1   # <-- uncomment to make this gate enforcing
fi
```

The run annotation confirms the gate reported rather than blocked:

```
SAST found 3 ERROR-severity finding(s). Reported, not enforced - these are
NodeGoat's intentional vulnerabilities, owned by the remediation workstream.
```

---

## Known tool caveat

Semgrep logs 10 `PartialParsing` notices against `app/views/*.html`. Those files
contain Swig template syntax (`{{ … }}`) that its HTML parser cannot fully
consume. It still scans what it can parse. This is a parser limitation, not a
scan failure, and it appears in the job log.

---

## Artifacts

`sast-semgrep-results` (112 KB) contains `semgrep.sarif` and `semgrep.json` with
full finding detail including code snippets and rule metadata.

**Expires 7 days after the run** (`retention-days: 7`). This file is the durable
record.

---

*Extracted from CI #14 for the IE3142 technical report. See
[README.md](README.md) for the full evidence index.*
