# Vulnerability Assessment & Secure Coding Evidence — IE3142 NodeGoat DevSecOps

**Target application:** OWASP NodeGoat (`http://localhost:4000`)
**Assessed by:** Karthiban S (IT24102157)
**Handoff to:** Ahamad R R (IT24101532) — secure coding fixes and re-verification

## Scope and method

This document records offensive testing performed against the unmodified,
containerised NodeGoat application prior to any secure coding fixes. A
baseline static application security testing (SAST) scan was run first,
followed by manual exploitation covering every threat identified in
`docs/threat-model.md` (T1–T12). All twelve threats have been confirmed as
working exploits against the unmodified application.

- **SAST tool used (local baseline):** Semgrep, `semgrep --config=auto`
- **Local baseline finding count:** 38

> **Note on SAST baseline reconciliation.** This 38-finding baseline was
> produced with `--config=auto` run locally. The project's CI pipeline
> (`.github/workflows/ci.yml`, `sast` job) runs Semgrep with a different,
> pinned configuration (`p/javascript`, `p/nodejs`, `p/owasp-top-ten`,
> excluding `app/assets/vendor`). The two are **separate scans with different
> scope and will not produce the same count.** The Technical Report should
> either (a) re-run the post-fix comparison against the pipeline's own config
> so the reported diff matches what CI actually enforces, or (b) present both
> baselines explicitly labelled as separate, so the numbers don't appear
> inconsistent to a reader.

![Baseline Semgrep terminal output](evidence/exploits/sast-baseline-semgrep-terminal.png)

*Figure 1 — Baseline Semgrep terminal output (local `--config=auto` run, 38 findings)*

---

## 1. STRIDE and OWASP Category Mapping (cross-reference to `docs/threat-model.md`)

Every threat in the threat model corresponds to an OWASP Top 10 category
(A1–A8) and has been fully demonstrated.

| Threat Model ID | OWASP Category | Vulnerability Title | Exploitation Status |
|---|---|---|---|
| T1 | A2.2 | Username Enumeration | ✅ Demonstrated (Section 4) |
| T2 | A5 | Unauthenticated MongoDB Connection | ✅ Demonstrated (Section 2) |
| T3 | A8 | Disabled CSRF Protection | ✅ Demonstrated (Section 2) |
| T4 | A5 | Clickjacking / Disabled Frame Protection | ✅ Demonstrated (Section 2) |
| T5 | A1 | NoSQL Injection | ✅ Demonstrated (Section 2) |
| T6 | A2.1 | Plaintext Password Storage | ✅ Demonstrated (Section 4) |
| T7 | A2.3 | Insecure Cookie Attributes | ✅ Demonstrated (Section 4) |
| T8 | A2.4 | Weak Password Policy | ✅ Demonstrated (Section 4) |
| T9 | A2.5 | Missing Session Idle Timeout | ✅ Demonstrated (Section 4) |
| T10 | A3 | Stored XSS | ✅ Demonstrated (Section 2) |
| T11 | A4 | Insecure Direct Object Reference | ✅ Demonstrated (Section 2) |
| T12 | A7 | Missing Function-Level Access Control | ✅ Demonstrated (Section 2) |

---

## 2. Core vulnerabilities (exploit-and-fix set)

### A1 — NoSQL Injection (Server-Side JavaScript) — T5

- **Target endpoint:** `/allocations` → Stocks Threshold field
- **Attack method:** Submitted a payload that alters the underlying MongoDB
  query logic: `1'; return 1 == '1`
- **Observed impact:** Overrides the query filter constraint and returns
  unauthorised database records belonging to other users.
- **Vulnerable location:** `app/data/allocations-dao.js`,
  `getByUserIdAndThreshold` — the `threshold` parameter is interpolated
  directly into a `$where` clause without validation.
- **Required remediation:** Replace raw string evaluation with explicit
  numeric casting (`parseInt`) and a bounds check before the value reaches
  the query.

![NoSQL injection payload submission](evidence/exploits/a1-nosqli-payload-submission.png)

*Figure 2 — Submitting the payload in the Threshold field*

![NoSQL injection unauthorized records returned](evidence/exploits/a1-nosqli-unauthorized-records.png)

*Figure 3 — Query returns unauthorised database records for all users*

**Secondary instance — Denial of Service via the same field:**
Submitting `';while(true){};` into the same `$where`-evaluated field traps
the Node.js event loop until MongoDB aborts execution. Same vulnerable
location and same fix (removing dynamic `$where` string evaluation resolves
both).

![DoS payload submission](evidence/exploits/a1-nosqli-dos-payload.png)

*Figure 4 — Submitting an infinite-loop payload*

![MongoDB aborting execution](evidence/exploits/a1-nosqli-mongodb-abort.png)

*Figure 5 — MongoDB aborts execution after the payload runs*

---

### A3 — Stored Cross-Site Scripting (XSS) — T10

- **Target endpoint:** `/profile` → First Name / Last Name fields
- **Attack method:** Injected `<script>alert('XSS Exploit')</script>` into
  editable profile fields.
- **Observed impact:** Payload persists in MongoDB and renders unescaped in
  the navigation header, executing JavaScript in the browser of any user who
  navigates the affected pages.
- **Vulnerable location:** `server.js` — Swig template engine initialised
  with `autoescape: false`.
- **Required remediation:** Set `swig.setDefaults({ autoescape: true })` and
  apply input sanitisation before database insertion.

![XSS payload injected into last name field](evidence/exploits/a3-xss-payload-injection.png)

*Figure 6 — Injecting a script tag into the Last Name field*

![XSS payload executing](evidence/exploits/a3-xss-execution-popup.png)

*Figure 7 — Pop-up confirming script execution when navigating pages*

---

### A4 — Insecure Direct Object Reference (IDOR) — T11

- **Target endpoint:** `/allocations/{userId}`
- **Attack method:** Authenticated as a standard user (`userId=2`), then
  manually changed the URL path to `/allocations/1`.
- **Observed impact:** Server returns the Administrator's allocation
  details without verifying the route parameter against the authenticated
  session.
- **Vulnerable location:** `app/routes/allocations.js`,
  `displayAllocations` — the handler trusts `req.params.userId` instead of
  `req.session.userId`.
- **Required remediation:** Source the user identifier from
  `req.session.userId` server-side rather than the URL parameter.

![IDOR URL tampering](evidence/exploits/a4-idor-url-tampering.png)

*Figure 8 — Authenticated as a standard user, manually navigating to another user's allocation URL*

![Insecure code path](evidence/exploits/a4-idor-code.png)

*Figure 9 — The insecure direct object reference in the route handler*

---

### A7 — Missing Function-Level Access Control — T12

- **Target endpoint:** `/benefits` (administrative dashboard)
- **Vulnerable files:** `app/routes/index.js`, `app/routes/admin.js`
- **Attack method:** Authenticated as a standard non-administrative user and
  navigated directly to `http://localhost:4000/benefits`.
- **Observed impact:** The application renders administrative controls and
  allows data modification without checking `req.session.user.isAdmin`.
- **Vulnerable location:** `app/routes/index.js` — the `/benefits` routes
  are registered with `isLoggedIn` only; the `isAdmin` middleware exists but
  is not attached.
- **Required remediation:** Attach `isAdmin` alongside `isLoggedIn` on both
  the `GET` and `POST` `/benefits` route handlers.

![Standard user reaching the admin dashboard](evidence/exploits/a7-access-control-bypass.png)

*Figure 10 — A standard user navigating directly to `/benefits` and modifying data*

---

## 3. Additional core vulnerabilities — T2, T3, T4

These three complete the coverage of every threat in `docs/threat-model.md`.

### A5 — Unauthorised Access Through an Unauthenticated MongoDB Connection — T2

- **Target:** `nodegoat-mongo`, reachable only within the private
  `nodegoat-net` Docker network
- **Attack method:** Started a temporary container attached to the same
  Docker network as the application and connected directly to MongoDB with
  no credentials:
  ```
  docker run -it --rm --network nodegoat-net mongo:4.4 mongo --host mongo --eval "db.getSiblingDB('nodegoat').users.find().toArray()"
  ```
- **Observed impact:** Returned all database user records, including
  plaintext passwords, completely bypassing authentication controls.
- **Vulnerable location:** `docker-compose.yml` — the MongoDB instance
  lacks explicit authentication enforcement
  (`MONGO_INITDB_ROOT_USERNAME`/`PASSWORD`).
- **Required remediation:** Enable MongoDB authentication, create a
  dedicated least-privilege database user, and pass credentials securely
  via environment variables sourced from the project's secrets-management
  mechanism.

![Unauthenticated MongoDB access](evidence/exploits/t2-mongo-unauthenticated-access.png)

*Figure 11 — Connecting directly to MongoDB from another container on the same network, with no credentials, and retrieving user records*

---

### A8 — Unauthorised State Change Through Disabled CSRF Protection — T3

- **Target endpoint:** `/contributions`
- **Attack method:** Logged into NodeGoat, then opened an external local
  HTML file containing an auto-submitting form targeting
  `http://localhost:4000/contributions` with modified allocation values —
  no interaction with the real NodeGoat form required.
- **Observed impact:** Contribution values were modified successfully
  without user interaction on the legitimate form, confirming that
  cross-site requests are processed blindly.
- **Vulnerable location:** `server.js` — the `csurf` import and middleware
  initialisation are commented out.
- **Required remediation:** Enable the `csurf` middleware, generate CSRF
  tokens for form views, and enforce token validation on all
  state-changing POST requests.

![Forged CSRF request page](evidence/exploits/t3-csrf-forged-page.png)

*Figure 12 — The forged HTML page used to submit an unauthorised request*

![Contributions changed before and after](evidence/exploits/t3-csrf-before-after.png)

*Figure 13 — Contributions page values modified via the external CSRF request*

---

### A5 — Clickjacking Through Disabled Frame Protection — T4

- **Target endpoint:** `/dashboard` (global layout)
- **Attack method:** Embedded the NodeGoat application inside an HTML
  inline frame (`<iframe src="http://localhost:4000/dashboard">`) hosted
  on a local test page.
- **Observed impact:** The dashboard rendered fully inside the
  third-party iframe without browser refusal, enabling UI redressing and
  clickjacking attacks.
- **Vulnerable location:** `server.js` — Helmet's `frameguard()` security
  header module is commented out.
- **Required remediation:** Enable Helmet's frame protection
  (`helmet.frameguard({ action: "deny" })`) or configure a Content
  Security Policy `frame-ancestors 'none'` header.

![NodeGoat rendered inside an attacker-controlled iframe](evidence/exploits/t4-clickjacking-iframe.png)

*Figure 14 — NodeGoat's dashboard loading inside a third-party iframe with no restriction*

---

## 4. Additional secure coding findings (audit-based, not full exploit cycles)

These are real weaknesses, identified by code/configuration audit with
supporting evidence, but without the same attack-and-reattempt cycle as
Sections 2 and 3. Each corresponds to a threat in `docs/threat-model.md`.

### A2.1 — Plaintext Password Storage — T6

- **Location:** `app/data/user-dao.js` (`addUser`, `validateLogin`)
- **Finding:** Passwords are stored and compared using direct string
  equality (`===`); the bcrypt-based fix exists in the codebase but is
  commented out.

![Plaintext password storage code](evidence/exploits/a2-plaintext-password-code.png)

*Figure 15 — `addUser` storing the password with no hashing*

![Plaintext password comparison code](evidence/exploits/a2-plaintext-password-db.png)

*Figure 16 — `validateLogin` comparing passwords with `===` instead of a hash check*

### A2.2 — Username Enumeration — T1

- **Location:** `/login`
- **Finding:** Distinct error messages for an invalid username versus an
  invalid password allow account discovery.

![Invalid username response](evidence/exploits/a2-username-enum-invalid-user.png)

*Figure 17 — "Invalid username" response*

![Invalid password response](evidence/exploits/a2-username-enum-invalid-password.png)

*Figure 18 — "Invalid password" response for a known username*

### A2.3 — Insecure Cookie Attributes — T7

- **Location:** `server.js` session configuration
- **Finding:** The session cookie is missing the `Secure` attribute,
  confirmed via browser developer tools.

![Insecure cookie flags](evidence/exploits/a2-insecure-cookie-flag.png)

*Figure 19 — Session cookie inspected via DevTools, `Secure` not set*

### A2.4 — Weak Password Policy — T8

- **Location:** `app/routes/session.js` (`PASS_RE = /^.{1,20}$/`)
- **Finding:** A one-character password was successfully registered and
  used to log in.

![Weak password accepted at signup](evidence/exploits/a2-weak-password-signup.png)

*Figure 20 — Registering an account with a single-character password*

![Weak password accepted at login](evidence/exploits/a2-weak-password-login.png)

*Figure 21 — Successfully logging in with the same weak password*

### A2.5 — Missing Session Idle Timeout — T9

- **Location:** `server.js` session configuration
- **Finding:** No `maxAge` is configured, so sessions remain valid
  indefinitely regardless of inactivity.

![Missing session timeout](evidence/exploits/a2-missing-session-timeout.png)

*Figure 22 — Session cookie inspected via DevTools, no expiry/Max-Age set*

---

## 5. Handoff checklist

- [x] Apply source code fixes for A1, A3, A4, A7 and re-verify (Section 2)
- [x] Exploit T2, T3, T4 and capture evidence (Section 3)
- [ ] Apply source code fixes for T2, T3, T4
- [ ] Re-run the SAST scan (using the same config as the baseline, or the
      pipeline's config — see the reconciliation note above) and record the
      before/after count or diff
- [ ] Optionally address the five audit-based findings in Section 4
- [x] Threat model (`docs/threat-model.md`) already covers T1–T12
