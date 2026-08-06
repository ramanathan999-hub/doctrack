# DocTrack — Enterprise Readiness Roadmap

**Purpose:** turn DocTrack from a working application into a product that survives an
enterprise security review and a systems-integrator partnership conversation.

**How to use this file:** commit it to the repo root. Work one package at a time, on its
own branch. Each package has acceptance criteria — treat them as the definition of done,
not as suggestions. Do not start a package whose dependencies are unmet.

---

## Context for the assistant

Current stack: Render (frontend), Supabase (Postgres + Auth + Storage), n8n Cloud,
Dropbox Sign. Self-hosted supporting services on a Hetzner box behind Caddy and WireGuard.

Domain: DocTrack tracks which commercial and export documents a shipment requires, by
country, customer, order type and payment term, then collects, versions, routes for
signature, and distributes them. Core tables: `orders`, `checklist_items`,
`order_activity`, `shipment_events`, `customer_portals`, `doc_rules`, `signature_rules`,
`customer_doc_rules`, `document_versions`, `order_types`, `order_type_docs`.

Known weakness driving this roadmap: the browser talks to Supabase directly, with
row-level security as the only authorization layer. This produced IDOR findings on the
supplier portal during self-directed penetration testing. It is a structural property of
the architecture, not a fixed bug.

**Standing rules**

- Never run destructive operations against the production Supabase project.
- Security-critical work is test-first: write the failing test that demonstrates the hole,
  then close it.
- No secrets in the client bundle, in the repo, or in commit history.
- Every package ends with updated `README.md` and, where relevant, `SECURITY.md`.

---

## WP-0 — Isolate and harden the estate

**Dependencies:** none. Do this first; it is cheap and it is currently the largest
unmanaged risk.

**Why:** production data currently shares a host with a browser-based IDE and unrelated
services. That fails logical separation, network segmentation, and prod/non-prod
separation simultaneously.

**Tasks**

1. Move DocTrack production onto a dedicated host. Nothing else runs on it — no Code
   Server, no unrelated web apps, no shared reverse proxy with other projects.
2. Create a separate Supabase project for development. Seed it with synthetic data via a
   generator script. Production data must never be copied into it.
3. Hetzner Cloud Firewall: default deny inbound, allow only 443 and WireGuard. SSH
   reachable only over the VPN.
4. Install CrowdSec or fail2ban. Harden the Caddy config: HSTS, CSP, `X-Frame-Options`,
   `Referrer-Policy`, no server version disclosure.
5. Move all secrets to environment variables injected at deploy time. Rotate every key
   that has ever been in a repo, a browser bundle, or a chat log.
6. CI pipeline: Semgrep (SAST), `npm audit`, Dependabot or Renovate, secret scanning.
   Fail the build on high severity.
7. Automated `pg_dump` to object storage with object-lock enabled. Script and document a
   restore. Perform one restore into the dev project and record the elapsed time.

**Acceptance criteria**

- `nmap` against the production host from outside the VPN shows only 443.
- The dev environment contains zero rows of real customer data.
- A restore has been performed end to end, with the timing written into `docs/dr.md`.
- CI blocks a deliberately introduced SQL injection and a committed dummy API key.

---

## WP-1 — Introduce the API layer

**Dependencies:** WP-0.

**Why:** this is the keystone. Identity, authorization, audit, retention, and rate
limiting all need a server-side chokepoint. Everything after this package assumes it
exists.

**Approach:** strangler pattern. Stand up the backend alongside the current app and move
routes across one domain object at a time, so the application stays shippable throughout.

**Tasks**

1. Scaffold a backend service (Fastify or NestJS, TypeScript). It holds the Supabase
   service-role key. The key never leaves the server.
2. Middleware chain, in order: authenticate — resolve tenant context — authorize —
   validate input (zod) — handle — emit audit event.
3. Authorization is explicit and server-side. Every handler states which resource and
   which action it permits. Never infer permission from a client-supplied ID.
4. Port routes in this order: orders — checklist items — documents and versions — portal
   endpoints — rules. Portal endpoints are where the IDOR findings were; port them with
   the most care.
5. Keep RLS enabled as defence in depth. It is now the second line, not the first.
6. Remove the anon key and all `supabase-js` calls from the browser bundle. Verify with a
   build-output grep in CI.
7. Rate limiting per tenant and per IP, especially on portal upload and download.

**Acceptance criteria**

- A regression suite that, for every ported route, attempts access to another tenant's
  resource by ID and expects 403 or 404. All pass.
- No occurrence of the Supabase URL or anon key in the production client bundle.
- Load test: portal document download holds up under expected concurrency without the
  service-role key path leaking cross-tenant data.

---

## WP-2 — Enterprise identity

**Dependencies:** WP-1.

**Why:** the most common single reason a small vendor is eliminated before anyone looks
at the product. Also required verbatim by the RfP.

**Tasks**

1. OIDC and SAML support against Microsoft Entra ID, with group-to-role mapping and
   just-in-time user provisioning. Multi-tenant: each customer brings their own IdP.
2. Explicit RBAC model — roles, permissions, resource scoping — persisted and
   administrable, not hardcoded.
3. MFA enforced for administrative roles. Short-lived access tokens with refresh rotation.
4. Session management: forced logout, session listing, revocation.
5. Retain the existing local auth path for portal users who have no corporate IdP. Keep
   the two paths cleanly separated in code.
6. Account lifecycle: documented and implemented creation, modification, and prompt
   revocation, plus a periodic access-review export.

**Acceptance criteria**

- End-to-end test against an Entra ID test tenant: login, group change reflected in role
  on next login, deprovisioned user denied within one session lifetime.
- An access-review report can be generated per tenant showing every user, role, and last
  login.

---

## WP-3 — Audit trail and retention

**Dependencies:** WP-1.

**Why:** `order_activity` is an application log — mutable, and stored next to the data it
describes. Enterprise buyers test audit integrity directly.

**Tasks**

1. Append-only audit store. Hash-chain each record to its predecessor so tampering is
   detectable. No UPDATE or DELETE grants on the table for the application role.
2. Cover the full event taxonomy: successful and failed logins with logon type, account
   creation and deletion, privilege escalation and modification, configuration and policy
   changes, information modification, privileged-account activity, session connect and
   disconnect, and any access to the audit log itself.
3. Log reads, not only writes. Who *viewed* a bank draft is an auditable fact.
4. Ship logs to an external destination so they survive host compromise. Start with an
   append-only object-storage sink; a hosted SIEM comes later.
5. Retention policies per document type, configurable per tenant, with enforced deletion
   and a legal-hold flag that suspends it. Dutch invoice retention is seven years; some
   customs documents run longer.
6. Move archived documents to object-lock (WORM) storage.
7. Customer data export: full tenant export in a usable, documented format, available on
   request and at contract end.

**Acceptance criteria**

- A test that mutates an audit row and demonstrates chain verification failing.
- Retention job dry-run report showing what would be deleted and what is on hold.
- A tenant export can be produced and re-imported into a clean instance.

---

## WP-4 — Rule governance

**Dependencies:** WP-1, WP-2.

**Why:** the logic in `doc_rules`, `customer_doc_rules` and `order_type_docs` is the
actual intellectual property. Today a business user cannot touch it. Competing products
handle this badly, which makes it the clearest differentiator on the roadmap.

**Tasks**

1. Rule authoring UI. Conditions on country, customer, order type, Incoterm, payment
   term, destination; outcomes as required documents, routing, and recipients.
2. Versioning with draft, review, and published states. Four-eyes approval on publish.
   Full change history with author and rationale.
3. Simulation mode: run a draft rule set against historical orders and show the diff
   against what actually happened. This is the feature that sells the module.
4. Conditional routing, timing rules, exception handling, resend triggers, and
   human-in-the-loop approval steps.
5. Move rule evaluation out of n8n and into the backend as a deterministic, unit-tested
   engine. n8n stays for integration plumbing, not business logic.

**Acceptance criteria**

- A published rule change is fully reconstructable from the audit trail.
- Simulation against a hundred historical orders completes and produces a readable diff.
- Rule engine has unit-test coverage over every condition operator.

---

## WP-5 — Ingest and distribution adapters

**Dependencies:** WP-1, WP-4.

**Why:** avoids building "an SAP integration" you cannot honestly claim, while making SAP
one adapter among several. This is also the shape a systems integrator needs in order to
resell or embed DocTrack.

**Tasks**

1. Define and publish a document ingest contract — OpenAPI spec, idempotency keys,
   metadata schema, Base64 PDF payload support, webhook callbacks.
2. Inbound adapters: authenticated email intake, SFTP watch folder, generic REST push,
   Flexport (extend the existing demo).
3. Outbound channels: email, SFTP, EDI handoff, REST API, print queue, archive.
4. Adapter interface documented well enough that a third party could write one against it
   without your involvement. Reference implementation plus a conformance test suite.
5. Do not build SAP BTP connectivity. Document the ingest contract that an SAP partner's
   CPI iFlow would call, and stop there.

**Acceptance criteria**

- A new adapter can be added without modifying core code.
- Conformance suite passes for at least two adapters.
- OpenAPI spec published and versioned.

---

## WP-6 — Search and document intelligence

**Dependencies:** WP-1, WP-3.

**Tasks**

1. Postgres full-text search over extracted document text, plus structured metadata search.
2. `pg_trgm` for fuzzy matching on references and party names.
3. Content hashing for exact duplicate detection; embeddings via `pgvector` for near
   duplicates and similar-document identification.
4. Auto-classification of inbound documents into known types, with a confidence threshold
   below which a human confirms. Never auto-file below threshold.
5. Search results respect authorization — never leak the existence of a document the
   caller cannot read.

**Acceptance criteria**

- Classification accuracy measured against a labelled set of real document types and
  recorded in `docs/classification-eval.md`.
- Authorization test: a document outside the caller's scope returns no hit under any query.

---

## WP-7 — Certified signatures

**Dependencies:** WP-1, WP-3. Defer until a customer requires it.

**Tasks**

1. Integrate an eIDAS-qualified trust service provider for advanced and qualified
   electronic signatures with embedded certificates. Keep Dropbox Sign for the tier that
   does not need it.
2. Signature validation on inbound certified PDFs.
3. Long-term validation — timestamping and revocation data embedded so signatures remain
   verifiable after certificate expiry.

---

## Not code, but on the critical path

These are yours, not the assistant's, and several convert more security-questionnaire
answers than any single engineering package:

- Policy set: acceptable use, incident response, change management, business continuity,
  data classification. Free ISO 27001 templates plus a weekend each.
- Business continuity and incident response drills, conducted and minuted annually.
- Threat model for the application, written down and revisited per release.
- External penetration test — **after** WP-1, not before. Testing today's architecture
  would produce a report confirming what you already know, at five figures.
- Independent security assessment or certification, when there is an organization to
  certify.

---

## Sequencing

WP-0 and WP-1 are non-negotiable prerequisites and unblock everything else. WP-2 and WP-3
can proceed in parallel once WP-1 lands. WP-4 is where commercial differentiation lives —
do not let it slip behind the compliance work indefinitely, because compliance work alone
does not sell anything. WP-5 determines whether an integrator can resell you. WP-6 and
WP-7 wait for demand.
