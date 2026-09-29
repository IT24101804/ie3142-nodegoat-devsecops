# STRIDE Threat Model and Risk Assessment — IE3142 NodeGoat DevSecOps

## 1. Scope and Method

This threat model analyses the containerised OWASP NodeGoat application documented in `docs/architecture.md`. The analysis focuses on the identified trust boundaries: TB-1 (Browser ↔ Application), TB-2 (Application ↔ Database), TB-3 (Database ↔ Persistent Storage), and TB-0 (Build-Time Supply Chain).

The STRIDE methodology is used to identify realistic application-specific security threats. Each identified threat is assessed according to its likelihood and impact, and is mapped to an appropriate security control and its implementation location in the application or DevSecOps pipeline.

This threat model was developed iteratively. T1–T4 were initially identified through architecture and configuration review, reasoning about plausible weaknesses from the code and deployment configuration. Offensive testing was subsequently carried out against every identified threat, and all twelve (T1–T12) are now confirmed as working exploits, with evidence captured in `docs/vulnerabilities.md`.

## 2. STRIDE Categories

| Category | Meaning |
|---|---|
| Spoofing | An attacker pretends to be another legitimate user or identity. |
| Tampering | An attacker makes unauthorised changes to application data or system resources. |
| Repudiation | A user performs an action but the system lacks sufficient evidence to prove who performed it. |
| Information Disclosure | Sensitive information is exposed to an unauthorised person. |
| Denial of Service | An attacker makes the application or one of its services unavailable. |
| Elevation of Privilege | An attacker obtains permissions or capabilities that they should not have. |

## 3. Identified Threats

### T1 — Username Enumeration Through Login Responses

- **STRIDE category:** Information Disclosure
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `app/routes/session.js`
- **Threat scenario:** NodeGoat returns different login error responses for an invalid username and an invalid password. An attacker can submit repeated login attempts with different usernames and use these responses to determine whether particular user accounts exist.
- **Potential impact:** Disclosure of valid usernames can assist further attacks against NodeGoat accounts, such as targeted password guessing or other account-focused attacks.
- **Existing control:** Session-based authentication protects authenticated application routes, but it does not prevent the login endpoint from revealing whether a username exists.
- **Recommended control:** Return the same generic authentication failure message for both unknown usernames and incorrect passwords, such as `Invalid username or password`.
- **Verified:** Exploit demonstrated live against the unmodified application; see `docs/vulnerabilities.md`, Section 3, Instance A2.2.

### T2 — Unauthorised Database Modification Through an Unauthenticated MongoDB Connection

- **STRIDE category:** Tampering
- **Trust boundary:** TB-2 — Application ↔ Database
- **Affected components:** `nodegoat-web` and `nodegoat-mongo`
- **Relevant location:** `docker-compose.yml` and the application's MongoDB connection configuration
- **Threat scenario:** MongoDB is reachable only through the private `nodegoat-net` network, but database authentication is not enabled. If an attacker compromises the NodeGoat application container or otherwise gains access to this Docker network, the attacker could connect to MongoDB without database credentials and modify application records.
- **Potential impact:** Unauthorised modification or deletion of user, allocation, contribution, memo, or other application data could damage the integrity of the NodeGoat system.
- **Existing control:** MongoDB port 27017 is not published to the host, LAN, or Internet and is reachable only by containers attached to the private Docker network.
- **Recommended control:** Enable MongoDB authentication and configure NodeGoat to use a dedicated least-privilege database account. The database credentials should be supplied through the project's secrets-management mechanism rather than being hardcoded in source code or committed configuration files.
- **Verified:** Exploit demonstrated live against the unmodified application; see `docs/vulnerabilities.md`, Section 2, T2.

### T3 — Unauthorised Actions Due to Disabled CSRF Protection

- **STRIDE category:** Tampering
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `server.js`
- **Threat scenario:** NodeGoat's CSRF protection is disabled. The `csurf` import and the middleware that enables CSRF protection are commented out in `server.js`. If a user has an authenticated NodeGoat session, an attacker could attempt to cause that user's browser to submit an unwanted state-changing request to the application without a valid CSRF token.
- **Potential impact:** Successful forged requests could cause application data or account-related information to be changed using the victim's authenticated session.
- **Existing control:** Session-based authentication identifies logged-in users, but authentication alone does not verify that a state-changing request was intentionally submitted from a legitimate NodeGoat form.
- **Recommended control:** Enable CSRF middleware, generate a CSRF token for legitimate forms, and validate the token on state-changing requests. The existing commented CSRF implementation in `server.js` provides the intended implementation location.
- **Verified:** Exploit demonstrated live against the unmodified application; see `docs/vulnerabilities.md`, Section 2, T3.

### T4 — Clickjacking Due to Disabled Frame Protection

- **STRIDE category:** Spoofing
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `server.js`
- **Threat scenario:** NodeGoat's Helmet security-header configuration is commented out in `server.js`, including the `helmet.frameguard()` protection intended to prevent the application from being displayed inside a malicious frame or iframe. An attacker could attempt to embed a NodeGoat page within a deceptive webpage and visually disguise it so that an authenticated user interacts with NodeGoat while believing they are interacting with the attacker's page.
- **Potential impact:** A victim could be deceived into performing unintended actions in their authenticated NodeGoat session, potentially affecting account or application data.
- **Existing control:** Session-based authentication restricts protected functionality to authenticated users, but it does not by itself prevent an authenticated NodeGoat page from being framed by another website.
- **Recommended control:** Enable appropriate anti-framing response headers using Helmet, such as the frame protection provided by `helmet.frameguard()` or an appropriate Content Security Policy `frame-ancestors` directive.
- **Verified:** Exploit demonstrated live against the unmodified application; see `docs/vulnerabilities.md`, Section 2, T4.

### T5 — Unauthorised Data Access Through NoSQL Injection

- **STRIDE category:** Tampering / Information Disclosure
- **Trust boundary:** TB-1 — Browser ↔ Application (query result crosses into TB-2, Application ↔ Database)
- **Affected component:** `nodegoat-web`
- **Relevant location:** `app/data/allocations-dao.js`, `getByUserIdAndThreshold`
- **Threat scenario:** The threshold parameter on the `/allocations` endpoint is interpolated directly into a MongoDB `$where` clause without validation. An attacker can submit a crafted string to alter the query's logic and return records belonging to other users, or submit an infinite-loop expression to stall the database's JavaScript evaluation engine.
- **Potential impact:** Disclosure of other users' allocation records, and a denial-of-service condition against the database connection handling the request.
- **Existing control:** None. The field accepts arbitrary string input with no type or bounds checking before being embedded in the query.
- **Recommended control:** Cast threshold to an integer with `parseInt` and validate it against an expected numeric range before it reaches the query; remove dynamic `$where` string evaluation entirely.
- **Verified:** Exploit demonstrated live against the unmodified application; see `docs/vulnerabilities.md`, Section 2, A1.

### T6 — Credential Compromise Through Plaintext Password Storage

- **STRIDE category:** Information Disclosure
- **Trust boundary:** TB-2 — Application ↔ Database (data at rest)
- **Affected component:** `nodegoat-web`
- **Relevant location:** `app/data/user-dao.js` (`addUser`, `validateLogin`)
- **Threat scenario:** User passwords are stored in MongoDB as plaintext and compared using a direct string equality check (`===`) rather than a salted hash. Anyone who can read the users collection — including an attacker exploiting T2, or anyone with direct database access — obtains every user's actual password immediately, with no cracking or brute-forcing required.
- **Potential impact:** Full, instantaneous compromise of every stored credential. Because users frequently reuse passwords, this also threatens accounts on other systems.
- **Existing control:** None. No hashing, salting, or one-way encoding is applied before storage or comparison.
- **Recommended control:** Hash passwords with a strong, slow, salted algorithm (e.g. bcrypt) before storage, and compare using the hashing library's constant-time verification function instead of `===`.
- **Verified:** Confirmed by direct inspection of stored records; see `docs/vulnerabilities.md`, Section 3, Instance A2.1.

### T7 — Session Exposure Through Insecure Cookie Attributes

- **STRIDE category:** Information Disclosure
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `server.js` session configuration
- **Threat scenario:** The session cookie is issued without the `Secure` attribute. If the application is ever reached over an unencrypted or protocol-downgraded connection, or if traffic is intercepted on a shared network, the session cookie can be captured and reused to impersonate the victim.
- **Potential impact:** Session hijacking, allowing an attacker to act as the victim without needing their password.
- **Existing control:** The application is currently bound to `127.0.0.1` only, which limits practical exposure in the local lab environment, but this is an environment-specific mitigation rather than a fix in the cookie configuration itself.
- **Recommended control:** Set `secure: true` on the session cookie for any deployment reachable over HTTPS, alongside `httpOnly` and an explicit `sameSite` policy.
- **Verified:** Confirmed by inspecting cookie attributes via browser developer tools; see `docs/vulnerabilities.md`, Section 3, Instance A2.3.

### T8 — Account Compromise Through a Weak Password Policy

- **STRIDE category:** Spoofing
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `app/routes/session.js` (`PASS_RE = /^.{1,20}$/`)
- **Threat scenario:** The registration and login password policy accepts any string of one to twenty characters, including trivially guessable values such as a single digit. This makes accounts far more susceptible to guessing, credential-stuffing, or brute-force attacks.
- **Potential impact:** Increased likelihood of successful account takeover, particularly when combined with the absence of any account lockout or rate limiting on the login endpoint.
- **Existing control:** None beyond the minimal length check.
- **Recommended control:** Enforce a stronger password policy (minimum length plus complexity requirements) in the registration validation logic.
- **Verified:** Confirmed by successfully registering and logging in with a weak password; see `docs/vulnerabilities.md`, Section 3, Instance A2.4.

### T9 — Extended Session Exposure Through Missing Idle Timeout

- **STRIDE category:** Elevation of Privilege
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `server.js` session configuration
- **Threat scenario:** No server-side idle timeout (`maxAge`) is configured for user sessions. A session therefore remains valid indefinitely once authenticated, extending the window during which a stolen, leaked, or unattended session can be reused by someone other than the original user.
- **Potential impact:** A longer-lived attack window for any session obtained through another vector, such as T7.
- **Existing control:** None. Sessions do not expire based on inactivity.
- **Recommended control:** Configure an appropriate rolling idle timeout on the session store/cookie in `server.js`.
- **Verified:** Confirmed by code and configuration review; see `docs/vulnerabilities.md`, Section 3, Instance A2.5.

### T10 — Session Hijacking / Content Manipulation Through Stored XSS

- **STRIDE category:** Tampering (page content) / Elevation of Privilege (via session hijacking if exploited further)
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `server.js` (Swig template engine, `autoescape: false`)
- **Threat scenario:** An attacker with a valid account submits a script payload into the First Name or Last Name profile fields. The payload persists in MongoDB and is rendered unescaped in the navigation header shown to every user who views a page where that name appears, executing arbitrary JavaScript in their browser session.
- **Potential impact:** Arbitrary script execution in another user's authenticated session; a more capable payload than the demonstrated proof of concept could exfiltrate session cookies or perform actions as the victim.
- **Existing control:** None active. Swig's autoescaping is explicitly disabled.
- **Recommended control:** Enable `swig.setDefaults({ autoescape: true })` and sanitise profile input server-side before it is stored.
- **Verified:** Exploit demonstrated live against the unmodified application; see `docs/vulnerabilities.md`, Section 2, A3.

### T11 — Cross-User Data Disclosure Through Insecure Direct Object Reference

- **STRIDE category:** Information Disclosure / Elevation of Privilege
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `app/routes/allocations.js`, `displayAllocations`
- **Threat scenario:** The `/allocations/:userId` route trusts the `userId` URL parameter directly rather than the authenticated session's user identifier. A logged-in standard user can change the URL parameter to another user's ID and receive that user's allocation data without any authorisation check.
- **Potential impact:** Disclosure of any user's financial allocation data to any other authenticated user, simply by guessing or enumerating IDs.
- **Existing control:** `isLoggedIn` middleware confirms the requester is authenticated, but does not confirm the requested resource belongs to them.
- **Recommended control:** Derive the user identifier from `req.session.userId` server-side rather than the URL path parameter.
- **Verified:** Exploit demonstrated live against the unmodified application; see `docs/vulnerabilities.md`, Section 2, A4.

### T12 — Privilege Escalation Through Missing Function-Level Access Control

- **STRIDE category:** Elevation of Privilege
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `app/routes/index.js` (route registration for `/benefits`)
- **Threat scenario:** The `/benefits` administrative dashboard is registered with `isLoggedIn` middleware only. The `isAdmin` middleware exists in the codebase but is not attached to this route. Any authenticated standard user can navigate directly to `/benefits` and reach administrative controls, including the ability to modify data.
- **Potential impact:** Full administrative functionality exposed to any authenticated user, regardless of role — the most severe of the demonstrated vulnerabilities, since it grants complete privilege escalation with no additional exploitation required beyond navigating to a URL.
- **Existing control:** `isLoggedIn` confirms authentication only; no authorisation/role check is performed.
- **Recommended control:** Attach the existing `isAdmin` middleware alongside `isLoggedIn` on both the GET and POST `/benefits` handlers.
- **Verified:** Exploit demonstrated live against the unmodified application; see `docs/vulnerabilities.md`, Section 2, A7.

## 4. Risk Assessment

A 3×3 risk matrix is used to assess each identified threat. Likelihood represents how realistically the threat could occur in the current NodeGoat deployment, while impact represents the severity of the consequences if the threat is successfully exploited.

### 4.1 Rating Scale

| Rating | Likelihood | Impact |
|---|---|---|
| **1 — Low** | Difficult or unlikely to occur in the current deployment. | Limited effect on application data, users, or availability. |
| **2 — Medium** | Realistically possible, but requires additional conditions or attacker access. | Could cause meaningful harm to application data, users, or security. |
| **3 — High** | Relatively easy or highly plausible because of the current application configuration. | Could cause serious compromise, modification, loss, or exposure of important application data. |

The risk score is calculated as:

**Risk Score = Likelihood × Impact**

The resulting scores are classified as:

- **Low:** 1–2
- **Medium:** 3–4
- **High:** 6–9

### 4.2 3×3 Risk Matrix

| Impact ↓ / Likelihood → | 1 — Low | 2 — Medium | 3 — High |
|---|---:|---:|---:|
| **3 — High** | 3 — Medium | 6 — High | 9 — High |
| **2 — Medium** | 2 — Low | 4 — Medium | 6 — High |
| **1 — Low** | 1 — Low | 2 — Low | 3 — Medium |

### 4.3 Threat Risk Ratings

| Threat | Likelihood | Impact | Risk Score | Risk Level |
|---|---|---|---:|---|
| T1 — Username Enumeration | 3 — High | 2 — Medium | 6 | High |
| T2 — Unauthenticated MongoDB Connection | 2 — Medium | 3 — High | 6 | High |
| T3 — Disabled CSRF Protection | 2 — Medium | 2 — Medium | 4 | Medium |
| T4 — Clickjacking / Disabled Frame Protection | 2 — Medium | 2 — Medium | 4 | Medium |
| T5 — NoSQL Injection | 3 — High | 3 — High | 9 | High |
| T6 — Plaintext Password Storage | 2 — Medium | 3 — High | 6 | High |
| T7 — Insecure Cookie Attributes | 2 — Medium | 2 — Medium | 4 | Medium |
| T8 — Weak Password Policy | 3 — High | 2 — Medium | 6 | High |
| T9 — Missing Session Idle Timeout | 2 — Medium | 2 — Medium | 4 | Medium |
| T10 — Stored XSS | 2 — Medium | 3 — High | 6 | High |
| T11 — Insecure Direct Object Reference | 3 — High | 2 — Medium | 6 | High |
| T12 — Missing Function-Level Access Control | 3 — High | 3 — High | 9 | High |

### 4.4 Risk Rating Justifications

#### T1 — Username Enumeration
**Likelihood: High (3).** The login endpoint is directly accessible to users, and an attacker does not need an authenticated session to submit different usernames and observe the different authentication responses.

**Impact: Medium (2).** Discovering a valid username does not directly compromise an account. However, the disclosed account information can support follow-up attacks such as targeted password guessing.

#### T2 — Unauthenticated MongoDB Connection
**Likelihood: Medium (2).** MongoDB is not published to the host, LAN, or Internet and is isolated inside the private Docker network. An attacker would therefore first need to compromise the application container or otherwise gain access to the internal Docker network.

**Impact: High (3).** If the internal network boundary is breached, MongoDB does not require database authentication. An attacker reaching the database could potentially access, modify, or delete important NodeGoat application records.

#### T3 — Disabled CSRF Protection
**Likelihood: Medium (2).** CSRF protection is disabled in `server.js`, but exploitation requires additional conditions, including an authenticated victim and a state-changing request that can be triggered through a forged request.

**Impact: Medium (2).** A successful CSRF attack could cause unintended actions or changes to application or account data using the victim's authenticated session. The current analysis does not establish that CSRF alone would result in complete application or system compromise.

#### T4 — Clickjacking Due to Disabled Frame Protection
**Likelihood: Medium (2).** Anti-framing protection is disabled, but exploitation requires an attacker to construct a deceptive page and persuade an authenticated NodeGoat user to visit and interact with it.

**Impact: Medium (2).** Successful clickjacking could deceive an authenticated user into performing unintended actions. However, the current evidence does not establish that clickjacking alone would provide complete compromise of the NodeGoat application or database.

#### T5 — NoSQL Injection
**Likelihood: High (3).** The Threshold field is directly reachable by any authenticated user with no special access, and the vulnerable query construction accepts arbitrary string input.

**Impact: High (3).** A successful payload discloses other users' records outright and a second variant can stall the database connection — both demonstrated working against the unmodified application.

#### T6 — Plaintext Password Storage
**Likelihood: Medium (2).** Exploiting this in isolation requires an attacker to already have some form of database read access, such as through T2 or direct access to the container/host. It is not exploitable from the browser alone.

**Impact: High (3).** Once database access is obtained, every stored password is immediately usable with no cracking effort required, and password reuse means the impact extends beyond the NodeGoat application itself.

#### T7 — Insecure Cookie Attributes
**Likelihood: Medium (2).** The application currently binds only to `127.0.0.1`, which limits realistic interception opportunities in the local lab environment, but the missing `Secure` attribute would become directly exploitable the moment the application is reachable over a shared or untrusted network.

**Impact: Medium (2).** A successfully intercepted cookie enables session hijacking, but this requires a suitable network position that does not currently exist in the lab deployment.

#### T8 — Weak Password Policy
**Likelihood: High (3).** The policy is trivially testable and was confirmed by successfully registering an account with a one-character password; no special tooling is required to exploit it.

**Impact: Medium (2).** A weak password alone does not grant access — it lowers the effort required for a subsequent guessing or brute-force attack, which is not otherwise rate-limited by the application.

#### T9 — Missing Session Idle Timeout
**Likelihood: Medium (2).** Exploiting this requires an attacker to first obtain a valid session through another means, such as a stolen cookie or an unattended authenticated browser.

**Impact: Medium (2).** The absence of a timeout extends the window of exposure rather than independently causing compromise.

#### T10 — Stored XSS
**Likelihood: Medium (2).** Requires the attacker to hold a valid account to submit the payload, and requires a victim to subsequently view a page where the affected name is rendered. Both conditions are easily met in normal use of the application, since the name appears in the navigation header on every page.

**Impact: High (3).** Successful execution runs arbitrary JavaScript in another user's authenticated session, which could be extended to session theft or unauthorised actions performed as the victim.

#### T11 — Insecure Direct Object Reference
**Likelihood: High (3).** Exploitation requires only editing a URL parameter while authenticated as any standard user; no special tooling or crafted payload is needed.

**Impact: Medium (2).** Impact is confined to disclosure of another user's allocation data rather than full system compromise, though it affects every user record accessible through sequential or guessable IDs.

#### T12 — Missing Function-Level Access Control
**Likelihood: High (3).** Exploitation requires only navigating to a known URL while authenticated as any standard user — no payload, tooling, or additional access is needed.

**Impact: High (3).** Successful access grants full administrative functionality, including the ability to modify data, to any authenticated user regardless of assigned role.

## 5. Threat-to-Control Mapping

The following table maps each identified threat to a specific security control and identifies where that control should be implemented in the application or DevSecOps pipeline.

| Threat | Recommended Security Control | Implementation Location |
|---|---|---|
| **T1 — Username Enumeration** | Return a generic authentication failure message regardless of whether the username exists, so that valid accounts cannot be distinguished from invalid ones. | `app/routes/session.js` |
| **T2 — Unauthenticated MongoDB Connection** | Enable MongoDB authentication, provision a dedicated least-privilege application database user, and provide the credentials through the project's secrets-management mechanism rather than hardcoding them. | MongoDB configuration in `docker-compose.yml`; application database configuration; secrets supplied through the Vault/AppRole secrets-management flow documented in `docs/secrets.md`. |
| **T3 — Disabled CSRF Protection** | Enable CSRF protection and require valid CSRF tokens for state-changing requests. | Express middleware configuration in `server.js` and affected forms/routes. |
| **T4 — Clickjacking / Disabled Frame Protection** | Enable anti-framing protection using Helmet's frameguard or an appropriate `Content-Security-Policy: frame-ancestors` directive. | HTTP security middleware configuration in `server.js`. |
| **T5 — NoSQL Injection** | Validate and cast the threshold value to the expected numeric type and remove dynamically constructed MongoDB `$where` expressions. | `app/data/allocations-dao.js`, particularly `getByUserIdAndThreshold`. |
| **T6 — Plaintext Password Storage** | Hash passwords using a strong salted password-hashing algorithm such as bcrypt and verify passwords through the hashing library instead of direct plaintext comparison. | `app/data/user-dao.js`, particularly user creation and login validation logic. |
| **T7 — Insecure Cookie Attributes** | Configure secure session-cookie attributes including `secure`, `httpOnly`, and an explicit `sameSite` policy for an HTTPS deployment. | Session configuration in `server.js`. |
| **T8 — Weak Password Policy** | Enforce a stronger minimum password length and suitable password-strength requirements during registration. | Registration validation in `app/routes/session.js`, replacing the current weak `PASS_RE` validation. |
| **T9 — Missing Session Idle Timeout** | Configure an appropriate session/cookie idle timeout and expire inactive sessions. | Session configuration in `server.js`, including `maxAge`/session expiry settings. |
| **T10 — Stored XSS** | Enable template autoescaping and validate/sanitise user-controlled profile data before storage and rendering. | Swig configuration in `server.js` and profile input-handling logic. |
| **T11 — Insecure Direct Object Reference** | Enforce server-side object-level authorisation and derive the requested user's identifier from the authenticated session rather than trusting a URL parameter. | `app/routes/allocations.js`, particularly `displayAllocations`, using `req.session.userId`. |
| **T12 — Missing Function-Level Access Control** | Require administrator authorisation for the `/benefits` functionality by applying the existing `isAdmin` middleware in addition to authentication. | `/benefits` GET and POST route registration in `app/routes/index.js`. |

### 5.1 Control Strategy

The controls above follow a defence-in-depth approach. Input validation and safer database-query construction reduce injection risk; authentication and authorisation controls protect identities and restricted resources; secure password and session handling reduce account-compromise risk; output encoding and browser security controls reduce client-side attacks; and database authentication provides an additional protection layer if the application or Docker-network boundary is breached.

The controls should also be supported by the DevSecOps pipeline. Static analysis with Semgrep can identify insecure coding patterns, dependency scanning with `npm audit` detects known vulnerable packages, Gitleaks helps prevent credentials and secrets from entering the repository, and Trivy identifies vulnerabilities in the built container image. These pipeline gates complement the application-level controls but do not replace them.

### 5.2 Traceability to Exploit Evidence

Where a threat has been experimentally demonstrated by the secure-coding members, the corresponding evidence is documented in `docs/vulnerabilities.md`. This creates traceability between the architecture and threat model, the demonstrated vulnerability, the proposed security control, and the secure-coding remediation work.