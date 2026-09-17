# Evidence — Container image scan (Trivy)

**Tool:** `aquasec/trivy:0.74.0` (pinned, same version as CI)
**Image:** `nodegoat-devsec/web:local` — built from `Dockerfile` at commit `a11b1a7`
**Flags:** `--scanners vuln --severity CRITICAL,HIGH`
**Gate status:** report-only (threshold: CRITICAL and HIGH)

**Provenance note.** The equivalent figures appear in the CI #14 job summary
(`Security - Container scan (Trivy)`, 53s), but GitHub lazy-loads that summary
behind a "Load summary" control because of its size. The breakdown below was
therefore **regenerated locally** with the same pinned Trivy version against the
same image, rather than transcribed. The totals match those observed in CI #10
and CI #14. Screenshot **S8** in the evidence index captures the in-CI version.

---

## The layer split — the point of this evidence

```
| Layer                                        | Critical | High |
| Base image (Alpine 3.23.4 OS packages)       |     0    |   4  |
| Application dependencies (Node.js packages)  |     9    |  54  |
| Total                                        |     9    |  58  |
```

```
TARGET: nodegoat-devsec/web:local (alpine 3.23.4)   Class=os-pkgs    vulns=4
TARGET: Node.js                                     Class=lang-pkgs  vulns=63
```

**Why the split matters more than the total.**

"67 critical and high findings in our container image" is true but useless.
"**0 critical findings attributable to the base image we chose**, and 9 from the
application's intentional dependency tree" is the same data saying something
actionable — it separates what this workstream controls from what it does not.

It also **retrospectively validates the Phase 1 decision** to move off the
end-of-life `node:12-alpine`: the base image contributes zero criticals
precisely because it is a currently-supported release.

---

## All 4 base-image findings

Every OS-package finding, in full — there are only four, and all are OpenSSL:

| Severity | CVE | Package | Installed | Fixed in | Title |
|---|---|---|---|---|---|
| HIGH | `CVE-2026-14456` | `libcrypto3` | 3.5.6-r0 | 3.5.8-r0 | OpenSSL: Denial of Service via unbounded memory growth in QUIC server |
| HIGH | `CVE-2026-45447` | `libcrypto3` | 3.5.6-r0 | 3.5.7-r0 | Heap Use-After-Free in OpenSSL `PKCS7_verify()` |
| HIGH | `CVE-2026-14456` | `libssl3` | 3.5.6-r0 | 3.5.8-r0 | OpenSSL: Denial of Service via unbounded memory growth in QUIC server |
| HIGH | `CVE-2026-45447` | `libssl3` | 3.5.6-r0 | 3.5.7-r0 | Heap Use-After-Free in OpenSSL `PKCS7_verify()` |

Two distinct CVEs, each affecting two packages from the same OpenSSL source.
**Both have fixes available** — rebuilding on a newer `node:20-alpine` base would
clear them. That is a genuine, actionable finding within this workstream's scope,
unlike the application dependency findings.

Note also that the QUIC denial-of-service does not apply to this deployment: the
application serves plain HTTP on the loopback interface and does not use QUIC.

## The 9 critical application-dependency findings

| Package | Version | Critical | High | Example CVEs |
|---|---|---|---|---|
| `bson` | 1.0.9 | 1 | 0 | `CVE-2020-7610` |
| `minimist` | 0.0.8 | 1 | 0 | `CVE-2021-44906` |
| `minimist` | 0.0.10 | 1 | 0 | `CVE-2021-44906` |
| `minimist` | 1.2.5 | 1 | 0 | `CVE-2021-44906` |
| `mixin-deep` | 1.3.1 | 1 | 0 | `CVE-2019-10746` |
| `set-value` | 0.4.3 | 1 | 1 | `CVE-2019-10747`, `CVE-2021-23440` |
| `set-value` | 2.0.0 | 1 | 1 | `CVE-2019-10747`, `CVE-2021-23440` |
| `tar` | 6.2.1 | 1 | 8 | `CVE-2026-59873`, `CVE-2026-23745`, `CVE-2026-23950` |
| `underscore` | 1.9.1 | 1 | 1 | `CVE-2021-23358`, `CVE-2026-27601` |

`minimist` appears at **three different versions** and `set-value` at two — the
same vulnerable package pulled in repeatedly through different dependency paths.
That duplication is itself a useful observation about an unmaintained tree.

These overlap substantially with the `npm audit` findings in
[`dependency-npm-audit.md`](dependency-npm-audit.md), which is expected: both
tools analyse the same `node_modules` tree, one from the lockfile and one from
the built image. Agreement between two independent tools strengthens the finding
rather than double-counting it.

---

## Why this gate is report-only, and the one threshold that could enforce

Almost every finding originates in NodeGoat's dependency tree, already reported
by the dependency-scan gate and owned by the remediation workstream.

The gate therefore computes and prints the one threshold that **would** be safe
to enforce here — **OS-level CRITICAL, currently 0**:

```bash
OS_CRITICAL=$(cat trivy-os-critical.txt 2>/dev/null || echo 0)
echo "Base-image (OS package) CRITICAL findings: $OS_CRITICAL"
if [ "$OS_CRITICAL" -gt 0 ]; then
  echo "::warning::Container scan found $OS_CRITICAL CRITICAL finding(s) in base-image OS packages."
  # exit 1   # <-- uncomment to enforce on base-image CRITICAL findings
fi
```

That threshold would catch a regression in the base image — something this
workstream *is* responsible for and *can* fix — without being blocked by
application vulnerabilities it is not permitted to touch. It is currently 0, so
enabling it would not break the build today.

---

## Scanning the built artifact, not a rebuild

`container-scan` is the only gate with a `needs:` dependency. It declares
`needs: build` and downloads the **image artifact the build job already
published**, then `docker load`s it.

The image is therefore **built once and scanned once**, and the bytes Trivy
inspects are the same bytes the smoke test exercised. Rebuilding inside this job
would waste time and — more seriously — risk scanning an image that nobody
tested.

---

## Reproducing this locally

```bash
docker compose build web
docker run --rm \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v "$PWD:/out" \
  aquasec/trivy:0.74.0 image --scanners vuln --severity CRITICAL,HIGH \
  --format json --output /out/trivy-report.json --exit-code 0 --quiet \
  nodegoat-devsec/web:local
```

Counts are **point-in-time** — Trivy's vulnerability database updates
continuously, so totals will drift upward as new CVEs are published against these
unmaintained packages.

---

## Artifacts

`container-scan-trivy-report` (61.9 KB in CI #14) contains the full
`trivy-report.json` with every CVE, CVSS score, fixed version and package path.

**Expires 7 days after the run.** This file is the durable record.

---

*Regenerated at commit `a11b1a7` for the IE3142 technical report. See
[README.md](README.md) for the full evidence index.*
