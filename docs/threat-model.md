# STRIDE Threat Model and Risk Assessment — IE3142 NodeGoat DevSecOps

## 1. Scope and Method

This threat model analyses the containerised OWASP NodeGoat application documented in `docs/architecture.md`. The analysis focuses on the five identified trust boundaries: TB-1 (Browser ↔ Application), TB-2 (Application ↔ Database), TB-3 (Database ↔ Persistent Storage), TB-0 (Build-Time Supply Chain), and TB-4 (Application ↔ Secrets Management).

The final deployment also includes an optional HashiCorp Vault secrets-management service and a one-shot `vault-init` provisioning service. Vault, `vault-init`, the `vault-approle` volume, and the web application introduce additional security-sensitive flows for secrets provisioning. These flows are considered as part of the system security context, while their detailed implementation and verification are documented separately in `docs/secrets.md`.

The STRIDE methodology is used to identify realistic application-specific security threats. Each identified threat is assessed according to its likelihood and impact, and is mapped to an appropriate security control and its implementation location in the application or DevSecOps pipeline.

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
### T2 — Unauthorised Database Modification Through an Unauthenticated MongoDB Connection

- **STRIDE category:** Tampering
- **Trust boundary:** TB-2 — Application ↔ Database
- **Affected components:** `nodegoat-web` and `nodegoat-mongo`
- **Relevant location:** `docker-compose.yml` and the application's MongoDB connection configuration
- **Threat scenario:** MongoDB is reachable only through the private `nodegoat-net` network, but database authentication is not enabled. If an attacker compromises the NodeGoat application container or otherwise gains access to this Docker network, the attacker could connect to MongoDB without database credentials and modify application records.
- **Potential impact:** Unauthorised modification or deletion of user, allocation, contribution, memo, or other application data could damage the integrity of the NodeGoat system.
- **Existing control:** MongoDB port `27017` is not published to the host, LAN, or Internet and is reachable only by containers attached to the private Docker network.
- **Recommended control:** Enable MongoDB authentication and configure NodeGoat to use a dedicated least-privilege database account. The database credentials should be supplied through the project's secrets-management mechanism, preferably the existing HashiCorp Vault integration, rather than being hardcoded in source code or committed configuration files.

### T3 — Unauthorised Actions Due to Disabled CSRF Protection

- **STRIDE category:** Tampering
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `server.js`
- **Threat scenario:** NodeGoat's CSRF protection is disabled. The `csurf` import and the middleware that enables CSRF protection are commented out in `server.js`. If a user has an authenticated NodeGoat session, an attacker could attempt to cause that user's browser to submit an unwanted state-changing request to the application without a valid CSRF token.
- **Potential impact:** Successful forged requests could cause application data or account-related information to be changed using the victim's authenticated session.
- **Existing control:** Session-based authentication identifies logged-in users, but authentication alone does not verify that a state-changing request was intentionally submitted from a legitimate NodeGoat form.
- **Recommended control:** Enable CSRF middleware, generate a CSRF token for legitimate forms, and validate the token on state-changing requests. The existing commented CSRF implementation in `server.js` provides the intended implementation location.

### T4 — Clickjacking Due to Disabled Frame Protection

- **STRIDE category:** Spoofing
- **Trust boundary:** TB-1 — Browser ↔ Application
- **Affected component:** `nodegoat-web`
- **Relevant location:** `server.js`
- **Threat scenario:** NodeGoat's Helmet security-header configuration is commented out in `server.js`, including the `helmet.frameguard()` protection intended to prevent the application from being displayed inside a malicious frame or iframe. An attacker could attempt to embed a NodeGoat page within a deceptive webpage and visually disguise it so that an authenticated user interacts with NodeGoat while believing they are interacting with the attacker's page.
- **Potential impact:** A victim could be deceived into performing unintended actions in their authenticated NodeGoat session, potentially affecting account or application data.
- **Existing control:** Session-based authentication restricts protected functionality to authenticated users, but it does not by itself prevent an authenticated NodeGoat page from being framed by another website.
- **Recommended control:** Enable appropriate anti-framing response headers using Helmet, such as the frame protection provided by `helmet.frameguard()` or an appropriate Content Security Policy `frame-ancestors` directive. The existing commented Helmet configuration in `server.js` identifies the intended implementation area.

### T5 – Disclosure of Secrets Through Compromise of the AppRole Credential Flow

- **STRIDE category:** Information Disclosure
- **Trust boundary:** TB-4 – Application ↔ Secrets Management
- **Affected components:** `nodegoat-web`, `nodegoat-vault`, `nodegoat-vault-init`, and `vault-approle`
- **Relevant location:** `docker-compose.yml`, `docker/vault-init.sh`, and `docker/vault-fetch.js`
- **Threat scenario:** When Vault is enabled, `vault-init` provisions AppRole credentials into the shared `vault-approle` volume and the web container reads those credentials to retrieve application secrets from Vault. If an attacker compromises a component with access to the AppRole credential flow or obtains the AppRole credentials from the shared volume, the attacker could attempt to retrieve secrets available to the NodeGoat application.
- **Potential impact:** Disclosure of session or cryptographic secrets could weaken session protection or expose other security-sensitive application data.
- **Existing control:** The AppRole volume is mounted read-only in the web container, Vault is not published to the host, and communication occurs on the private Docker network. The Vault policy should restrict the application identity to only the secrets required by NodeGoat.
- **Recommended control:** Maintain least-privilege Vault policies, restrict access to the AppRole credential volume, use short-lived credentials where practical, avoid logging secret values, and verify that secrets are not committed to source control through the secrets-scanning CI gate.

## 4. Risk Assessment

A 3×3 risk matrix is used to assess each identified threat. Likelihood represents how realistically the threat could occur in the current NodeGoat deployment, while impact represents the severity of the consequences if the threat is successfully exploited.

### 4.1 Rating Scale

| Rating | Likelihood | Impact |
|---|---|---|
| 1 — Low | Difficult or unlikely to occur in the current deployment. | Limited effect on application data, users, or availability. |
| 2 — Medium | Realistically possible, but requires additional conditions or attacker access. | Could cause meaningful harm to application data, users, or security. |
| 3 — High | Relatively easy or highly plausible because of the current application configuration. | Could cause serious compromise, modification, loss, or exposure of important application data. |

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
| **T1 — Username Enumeration** | 3 — High | 2 — Medium | 6 | **High** |
| **T2 — Unauthenticated MongoDB Connection** | 2 — Medium | 3 — High | 6 | **High** |
| **T3 — Disabled CSRF Protection** | 2 — Medium | 2 — Medium | 4 | **Medium** |
| **T4 — Clickjacking / Disabled Frame Protection** | 2 — Medium | 2 — Medium | 4 | **Medium** |
| **T5 – AppRole Credential Flow Compromise** | 2 – Medium | 3 – High | 6 | **High** |

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

#### T5 — AppRole Credential Flow Compromise

**Likelihood: Medium (2).** Exploiting this threat requires access to the AppRole credential flow, such as compromising a container with access to the shared `vault-approle` volume or the Vault communication path. The Vault service is not exposed to the host and communicates only on the private Docker network, making direct external access less likely.

**Impact: High (3).** If an attacker successfully retrieves the AppRole credentials and uses them to access Vault, application secrets such as session or cryptographic keys could be exposed. This could weaken authentication or disclose other security-sensitive configuration values.

**Overall Risk: High (6).** Although additional access is required before exploitation is possible, the potential exposure of application secrets makes this a high-risk infrastructure threat that should be mitigated through least-privilege Vault policies, restricted credential access, and secret-scanning controls.

## 5. Threat-to-Control Mapping

The following table maps each identified threat to a specific security control and identifies where that control should be implemented. This ensures that the threat model leads to concrete security improvements rather than only documenting risks.

| Threat | STRIDE Category | Recommended Security Control | Implementation Location |
|---|---|---|---|
| **T1 — Username Enumeration** | Information Disclosure | Use a single generic authentication failure response regardless of whether the username exists or the password is incorrect. | `app/routes/session.js` |
| **T2 — Unauthenticated MongoDB Connection** | Tampering | Enable MongoDB authentication, use a dedicated least-privilege database account, and supply the database credentials through the project's managed secrets mechanism, such as the existing HashiCorp Vault integration. | `docker-compose.yml`, application MongoDB connection configuration, `docker/vault-init.sh`, and `docs/secrets.md` |
| **T3 — Disabled CSRF Protection** | Tampering | Enable the existing CSRF middleware, generate CSRF tokens for legitimate forms, and validate tokens on state-changing requests. | `server.js` and affected application forms/routes |
| **T4 — Clickjacking / Disabled Frame Protection** | Spoofing | Enable anti-framing protection using Helmet frame protection or an appropriate Content Security Policy `frame-ancestors` directive. | `server.js` |
| **T5 – AppRole Credential Flow Compromise** | Information Disclosure | Apply least-privilege Vault policies, restrict access to the `vault-approle` credential volume, avoid exposing or logging secret values, and use the secrets-scanning CI gate to detect accidentally committed credentials. | `docker/vault-init.sh`, `docker/vault-fetch.js`, `docker-compose.yml`, `docs/secrets.md`, and the GitHub Actions secrets-scanning workflow |

### 5.1 Control Mapping Rationale

**T1:** The weakness originates from distinguishable authentication responses. Therefore, the most direct control is to change the login handling in `app/routes/session.js` so that failed authentication attempts return the same generic response.

**T2:** Docker network isolation currently reduces exposure of MongoDB, but it does not authenticate a process that has already reached the database network. Database authentication and a least-privilege account therefore provide an additional control if the application container or internal network is compromised. Credentials should be supplied using the project's secrets-management mechanism rather than stored directly in source code.

**T3:** The relevant CSRF implementation already exists in commented form in `server.js`. Enabling CSRF middleware and requiring valid tokens on state-changing requests directly addresses forged requests made through an authenticated victim's browser.

**T4:** The relevant Helmet frame-protection configuration is currently commented out in `server.js`. Enabling anti-framing protection prevents an attacker-controlled site from embedding NodeGoat in a deceptive frame, directly reducing the clickjacking threat.

**T5:** The AppRole credential flow allows the NodeGoat web application to retrieve required secrets from Vault without storing those secrets directly in the application source code. However, compromise of the shared AppRole credentials could allow an attacker to request secrets available to the application identity. Therefore, the most direct controls are to apply a least-privilege Vault policy, restrict access to the `vault-approle` credential volume, avoid logging secret values, and use the secrets-scanning CI gate to detect credentials accidentally committed to the repository.