# Vulnerability Assessment & Secure Coding Evidence — IE3142 NodeGoat DevSecOps[cite: 4]

**Target application:** OWASP NodeGoat (`http://localhost:4000`)[cite: 4]  
**Assessed by:** Karthiban S (IT24102157)[cite: 4]  
**Handoff to:** Ahamad R R (IT24101532) — secure coding fixes and re-verification[cite: 4]  

---

## Scope and Method[cite: 4]

This document records offensive testing performed against the unmodified, containerised NodeGoat application prior to any secure coding fixes[cite: 4]. A baseline static application security testing (SAST) scan was run first, followed by manual exploitation covering every application-layer threat identified in `docs/threat-model.md` (T1–T12)[cite: 4]. All twelve have been confirmed as working exploits against the unmodified application[cite: 4]. T13 (AppRole credential flow compromise) is an infrastructure-level threat and was not exploited — see `docs/threat-model.md`, Section 3, for the rationale[cite: 4].

* **SAST tool:** Semgrep[cite: 4]
* **Primary baseline (CI-enforced):** 15 findings (3 ERROR, 12 WARNING) — CI #20, commit `530da90`, using the pipeline’s pinned configuration (`p/javascript`, `p/nodejs`, `p/owasp-top-ten`, excluding `app/assets/vendor`)[cite: 4]. This is the number the Technical Report’s before/after SAST comparison should use, since it reflects the scan actually enforced by the DevSecOps pipeline[cite: 4].
* **Secondary, non-enforced local scan:** 38 findings, produced locally with Semgrep’s broader `--config=auto` ruleset[cite: 4]. This scan has wider scope than the pipeline’s configuration and is not directly comparable to the CI number above — it is included only for completeness and should not be used in a before/after comparison against a CI-based “after” scan[cite: 4].

![Baseline Semgrep Terminal Output](evidence/exploits/sast-baseline-semgrep-terminal.png)[cite: 4]  
*Figure 1 — Local Semgrep terminal output (`--config=auto` run, 38 findings — secondary/non-enforced scan; see note above)*[cite: 4]

---

## 1. STRIDE and OWASP Category Mapping (cross-reference to `docs/threat-model.md`)[cite: 4]

Every application-layer threat in the threat model corresponds to an OWASP Top 10 category (A1–A8) and has been fully demonstrated[cite: 4]. T13 is an infrastructure-level threat and is not exploited (see `docs/threat-model.md`)[cite: 4].

| Threat Model ID | OWASP Category | Vulnerability Title | Exploitation Status |
| :--- | :--- | :--- | :--- |
| **T1** | A2.2 | Username Enumeration | ✅ Demonstrated (Section 4)[cite: 4] |
| **T2** | A5 | Unauthenticated MongoDB Connection | ✅ Demonstrated (Section 2)[cite: 4] |
| **T3** | A8 | Disabled CSRF Protection | ✅ Demonstrated (Section 2)[cite: 4] |
| **T4** | A5 | Clickjacking / Disabled Frame Protection | ✅ Demonstrated (Section 2)[cite: 4] |
| **T5** | A1 | NoSQL Injection | ✅ Demonstrated (Section 2)[cite: 4] |
| **T6** | A2.1 | Plaintext Password Storage | ✅ Demonstrated (Section 4)[cite: 4] |
| **T7** | A2.3 | Insecure Cookie Attributes | ✅ Demonstrated (Section 4)[cite: 4] |
| **T8** | A2.4 | Weak Password Policy | ✅ Demonstrated (Section 4)[cite: 4] |
| **T9** | A2.5 | Missing Session Idle Timeout | ✅ Demonstrated (Section 4)[cite: 4] |
| **T10** | A3 | Stored XSS | ✅ Demonstrated (Section 2)[cite: 4] |
| **T11** | A4 | Insecure Direct Object Reference | ✅ Demonstrated (Section 2)[cite: 4] |
| **T12** | A7 | Missing Function-Level Access Control | ✅ Demonstrated (Section 2)[cite: 4] |
| **T13** | — | AppRole Credential Flow Compromise | ⬛ Identified, not exploited (infrastructure-level — see `docs/threat-model.md`)[cite: 4] |

---

## 2. Core Vulnerabilities (exploit-and-fix set)[cite: 4]

### A1 — NoSQL Injection (Server-Side JavaScript) — T5[cite: 4]

* **Target endpoint:** `/allocations` → Stocks Threshold field[cite: 4]
* **Attack method:** Submitted a payload that alters the underlying MongoDB query logic: `1'; return 1 == '1`[cite: 4]
* **Observed impact:** Overrides the query filter constraint and returns unauthorised database records belonging to other users[cite: 4].
* **Vulnerable location:** `app/data/allocations-dao.js`, `getByUserIdAndThreshold` — the threshold parameter is interpolated directly into a `$where` clause without validation[cite: 4].
* **Required remediation:** Replace raw string evaluation with explicit numeric casting (`parseInt`) and a bounds check before the value reaches the query[cite: 4].

![NoSQL Injection Payload Submission](evidence/exploits/a1-nosqli-payload-submission.png)[cite: 4]  
*Figure 2 — Submitting the payload in the Threshold field*[cite: 4]

![NoSQL Injection Unauthorized Records Returned](evidence/exploits/a1-nosqli-unauthorized-records.png)[cite: 4]  
*Figure 3 — Query returns unauthorised database records for all users*[cite: 4]

* **Secondary instance — Denial of Service via the same field:** Submitting `';while(true){};` into the same `$where`-evaluated field traps the Node.js event loop until MongoDB aborts execution[cite: 4]. Same vulnerable location and same fix (removing dynamic `$where` string evaluation resolves both)[cite: 4].

![DoS Payload Submission](evidence/exploits/a1-nosqli-dos-payload.png)[cite: 4]  
*Figure 4 — Submitting an infinite-loop payload*[cite: 4]

![MongoDB Aborting Execution](evidence/exploits/a1-nosqli-mongodb-abort.png)[cite: 4]  
*Figure 5 — MongoDB aborts execution after the payload runs*[cite: 4]

---

### A3 — Stored Cross-Site Scripting (XSS) — T10[cite: 4]

* **Target endpoint:** `/profile` → First Name / Last Name fields[cite: 4]
* **Attack method:** Injected `<script>alert('XSS Exploit')</script>` into editable profile fields[cite: 4].
* **Observed impact:** Payload persists in MongoDB and renders unescaped in the navigation header, executing JavaScript in the browser of any user who navigates the affected pages[cite: 4].
* **Vulnerable location:** `server.js` — Swig template engine initialised with `autoescape: false`[cite: 4].
* **Required remediation:** Set `swig.setDefaults({ autoescape: true })` and apply input sanitisation before database insertion[cite: 4].

![XSS Payload Injected](evidence/exploits/a3-xss-payload-injection.png)[cite: 4]  
*Figure 6 — Injecting a script tag into the Last Name field*[cite: 4]

![XSS Payload Executing](evidence/exploits/a3-xss-execution-popup.png)[cite: 4]  
*Figure 7 — Pop-up confirming script execution when navigating pages*[cite: 4]

---

### A4 — Insecure Direct Object Reference (IDOR) — T11[cite: 4]

* **Target endpoint:** `/allocations/{userId}`[cite: 4]
* **Attack method:** Authenticated as a standard user (`userId=2`), then manually changed the URL path to `/allocations/1`[cite: 4].
* **Observed impact:** Server returns the Administrator’s allocation details without verifying the route parameter against the authenticated session[cite: 4].
* **Vulnerable location:** `app/routes/allocations.js`, `displayAllocations` — the handler trusts `req.params.userId` instead of `req.session.userId`[cite: 4].
* **Required remediation:** Source the user identifier from `req.session.userId` server-side rather than the URL parameter[cite: 4].

![IDOR URL Tampering](evidence/exploits/a4-idor-url-tampering.png)[cite: 4]  
*Figure 8 — Authenticated as a standard user, manually navigating to another user’s allocation URL*[cite: 4]

![Insecure Code Path](evidence/exploits/a4-idor-code.png)[cite: 4]  
*Figure 9 — The insecure direct object reference in the route handler*[cite: 4]

---

### A7 — Missing Function-Level Access Control — T12[cite: 4]

* **Target endpoint:** `/benefits` (administrative dashboard)[cite: 4]
* **Vulnerable files:** `app/routes/index.js`, `app/routes/admin.js`[cite: 4]
* **Attack method:** Authenticated as a standard non-administrative user and navigated directly to `http://localhost:4000/benefits`[cite: 4].
* **Observed impact:** The application renders administrative controls and allows data modification without checking `req.session.user.isAdmin`[cite: 4].
* **Vulnerable location:** `app/routes/index.js` — the `/benefits` routes are registered with `isLoggedIn` only; the `isAdmin` middleware exists but is not attached[cite: 4].
* **Required remediation:** Attach `isAdmin` alongside `isLoggedIn` on both the GET and POST `/benefits` route handlers[cite: 4].

![Standard User Reaching Admin Dashboard](evidence/exploits/a7-access-control-bypass.png)[cite: 4]  
*Figure 10 — A standard user navigating directly to /benefits and modifying data*[cite: 4]

---

## 3. Additional Core Vulnerabilities — T2, T3, T4[cite: 4]

These three complete the coverage of every application-layer threat in `docs/threat-model.md`[cite: 4].

### A5 — Unauthorised Access Through an Unauthenticated MongoDB Connection — T2[cite: 4]

* **Target:** `nodegoat-mongo`, reachable only within the private `nodegoat-net` Docker network[cite: 4]
* **Attack method:** Started a temporary container attached to the same Docker network as the application and connected directly to MongoDB with no credentials[cite: 4]:
  ```bash
  docker run -it --rm --network nodegoat-net mongo:4.4 mongo --host mongo --eval "db.getSiblingDB('nodegoat').users.find().toArray()"
  ```[cite: 4]
* **Observed impact:** Returned all database user records, including plaintext passwords, completely bypassing authentication controls[cite: 4].
* **Vulnerable location:** `docker-compose.yml` — the MongoDB instance lacks explicit authentication enforcement (`MONGO_INITDB_ROOT_USERNAME/PASSWORD`)[cite: 4].
* **Required remediation:** Enable MongoDB authentication, create a dedicated least-privilege database user, and pass credentials securely via environment variables sourced from the project’s secrets-management mechanism[cite: 4].

![Unauthenticated MongoDB Access](evidence/exploits/t2-mongo-unauthenticated-access.png)[cite: 4]  
*Figure 11 — Connecting directly to MongoDB from another container on the same network, with no credentials, and retrieving user records*[cite: 4]

---

### A8 — Unauthorised State Change Through Disabled CSRF Protection — T3[cite: 4]

* **Target endpoint:** `/contributions`[cite: 4]
* **Attack method:** Logged into NodeGoat, then opened an external local HTML file containing an auto-submitting form targeting `http://localhost:4000/contributions` with modified allocation values — no interaction with the real NodeGoat form required[cite: 4].
* **Observed impact:** Contribution values were modified successfully without user interaction on the legitimate form, confirming that cross-site requests are processed blindly[cite: 4].
* **Vulnerable location:** `server.js` — the `csurf` import and middleware initialisation are commented out[cite: 4].
* **Required remediation:** Enable the `csurf` middleware, generate CSRF tokens for form views, and enforce token validation on all state-changing POST requests[cite: 4].

![Forged CSRF Request Page](evidence/exploits/t3-csrf-forged-page.png)[cite: 4]  
*Figure 12 — The forged HTML page used to submit an unauthorised request*[cite: 4]

![Contributions Changed Before and After](evidence/exploits/t3-csrf-before-after.png)[cite: 4]  
*Figure 13 — Contributions page values modified via the external CSRF request*[cite: 4]

---

### A5 — Clickjacking Through Disabled Frame Protection — T4[cite: 4]

* **Target endpoint:** `/dashboard` (global layout)[cite: 4]
* **Attack method:** Embedded the NodeGoat application inside an HTML inline frame (`<iframe src="http://localhost:4000/dashboard">`) hosted on a local test page[cite: 4].
* **Observed impact:** The dashboard rendered fully inside the third-party iframe without browser refusal, enabling UI redressing and clickjacking attacks[cite: 4].
* **Vulnerable location:** `server.js` — Helmet’s `frameguard()` security header module is commented out[cite: 4].
* **Required remediation:** Enable Helmet’s frame protection (`helmet.frameguard({ action: "deny" })`) or configure a Content Security Policy `frame-ancestors 'none'` header[cite: 4].

![NodeGoat Rendered Inside Frame](evidence/exploits/t4-clickjacking-iframe.png)[cite: 4]  
*Figure 14 — NodeGoat’s dashboard loading inside a third-party iframe with no restriction*[cite: 4]

---

## 4. Additional Secure Coding Findings (audit-based, not full exploit cycles)[cite: 4]

These are real weaknesses, identified by code/configuration audit with supporting evidence, but without the same attack-and-reattempt cycle as Sections 2 and 3[cite: 4]. Each corresponds to a threat in `docs/threat-model.md`[cite: 4].

### A2.1 — Plaintext Password Storage — T6[cite: 4]

* **Location:** `app/data/user-dao.js` (`addUser`, `validateLogin`)[cite: 4]
* **Finding:** Passwords are stored and compared using direct string equality (`===`); the bcrypt-based fix exists in the codebase but is commented out[cite: 4].

![Plaintext Password Storage Code](evidence/exploits/a2-plaintext-password-code.png)[cite: 4]  
*Figure 15 — `addUser` storing the password with no hashing*[cite: 4]

![Plaintext Password Comparison Code](evidence/exploits/a2-plaintext-password-db.png)[cite: 4]  
*Figure 16 — `validateLogin` comparing passwords with `===` instead of a hash check*[cite: 4]

---

### A2.2 — Username Enumeration — T1[cite: 4]

* **Location:** `/login`[cite: 4]
* **Finding:** Distinct error messages for an invalid username versus an invalid password allow account discovery[cite: 4].

![Invalid Username Response](evidence/exploits/a2-username-enum-invalid-user.png)[cite: 4]  
*Figure 17 — “Invalid username” response*[cite: 4]

![Invalid Password Response](evidence/exploits/a2-username-enum-invalid-password.png)[cite: 4]  
*Figure 18 — “Invalid password” response for a known username*[cite: 4]

---

### A2.3 — Insecure Cookie Attributes — T7[cite: 4]

* **Location:** `server.js` session configuration[cite: 4]
* **Finding:** The session cookie is missing the `Secure` attribute, confirmed via browser developer tools[cite: 4].

![Insecure Cookie Flags](evidence/exploits/a2-insecure-cookie-flag.png)[cite: 4]  
*Figure 19 — Session cookie inspected via DevTools, Secure not set*[cite: 4]

---

### A2.4 — Weak Password Policy — T8[cite: 4]

* **Location:** `app/routes/session.js` (`PASS_RE = /^.{1,20}$/`)[cite: 4]
* **Finding:** A one-character password was successfully registered and used to log in[cite: 4].

![Weak Password Accepted at Signup](evidence/exploits/a2-weak-password-signup.png)[cite: 4]  
*Figure 20 — Registering an account with a single-character password*[cite: 4]

![Weak Password Accepted at Login](evidence/exploits/a2-weak-password-login.png)[cite: 4]  
*Figure 21 — Successfully logging in with the same weak password*[cite: 4]

---

### A2.5 — Missing Session Idle Timeout — T9[cite: 4]

* **Location:** `server.js` session configuration[cite: 4]
* **Finding:** No `maxAge` is configured, so sessions remain valid indefinitely regardless of inactivity[cite: 4].

![Missing Session Timeout](evidence/exploits/a2-missing-session-timeout.png)[cite: 4]  
*Figure 22 — Session cookie inspected via DevTools, no expiry/Max-Age set*[cite: 4]

---

## 5. T13 — AppRole Credential Flow Compromise (not exploited)[cite: 4]

T13, documented in `docs/threat-model.md`, concerns compromise of the Vault AppRole credential flow used for secrets provisioning[cite: 4]. It is intentionally excluded from the exploit-and-fix set: no working exploit is demonstrated here, since doing so safely would require simulating a compromise of a running container to steal live credentials, rather than an external application-layer attack[cite: 4]. Its recommended controls are infrastructure hardening measures (Vault policy scope, credential volume access, credential lifetime) rather than an application code fix[cite: 4]. One of its recommended controls — preventing secrets from reaching source control — is already implemented and enforced via the Gitleaks secrets-scanning CI gate[cite: 4].

---

## 6. Handoff Checklist[cite: 4]

- [x] Exploit T1–T12 and capture evidence[cite: 4]
- [ ] Apply source code fixes for T1–T12 and re-verify[cite: 4]
- [ ] Re-run the CI pipeline’s SAST scan after all fixes are pushed and record the new finding count against the CI #20 baseline of 15 (3 ERROR, 12 WARNING); cite the new run number and commit[cite: 4]
- [ ] Optionally address the five audit-based findings in Section 4[cite: 4]
- [x] Threat model (`docs/threat-model.md`) covers T1–T13[cite: 4]
- [x] T13 documented as identified-but-not-exploited (infrastructure-level, out of scope for this workstream)[cite: 4]
