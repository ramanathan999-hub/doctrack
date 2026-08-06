# DocTrack — Roadmap

Work packages are ordered by dependency. A package may not begin until all packages it
depends on are marked **Done**.

Status values: `Planned` · `In Progress` · `Done` · `Blocked`

---

## WP-0 — Environment isolation

**Status:** Planned  
**Branch:** `wp-0/env-isolation`  
**Depends on:** —

### Goal
Dev and test environments must be fully isolated from production. No action on a
non-production branch may affect production data, trigger a live signature request, or
send an email to a real counterparty.

### Work
- [ ] Create a nonprod Supabase project (separate from `syorwcsahfxbemvwdxrz`)
- [ ] Apply schema migrations to nonprod project
- [ ] Create synthetic seed script (`seed.sql` or `scripts/seed.js`) — no real customer data
- [ ] Wire runtime environment detection: hostname → Supabase credentials
  - `doctrack.52755928.xyz` → prod project
  - `test.doctrack.52755928.xyz` → nonprod project
  - `dev.doctrack.52755928.xyz` → nonprod project
- [ ] Split `supabase_schema.sql` into numbered migration files under `migrations/`
- [ ] Update n8n Dropbox Sign callback to use nonprod Supabase for dev/test webhooks
- [ ] Configure Dropbox Sign test mode credentials for dev/test
- [ ] Document `Conventions` section in `CLAUDE.md`

### Acceptance criteria
- A destructive SQL statement run against the nonprod project leaves prod data unchanged
- A signature request triggered on dev sends to a Dropbox Sign test account, not a real counterparty
- `npm run seed` (or equivalent) populates the nonprod project with synthetic orders and checklist items
- All three URLs serve distinct data sets

---

## WP-1 — Server-side API layer

**Status:** Planned  
**Branch:** `wp-1/api-layer`  
**Depends on:** WP-0

### Goal
Replace direct browser-to-Supabase calls with a server-side API. Eliminate the IDOR
surface on the supplier portal and move authorization out of client-visible RLS.

### Work
- [ ] Choose runtime (Edge Functions, lightweight Node service, or other) — ask before deciding
- [ ] Define API contract for every existing `supabase-js` call in `index.html`
- [ ] Implement endpoints behind authentication
- [ ] Migrate client to use API endpoints (remove direct `supabase-js` calls)
- [ ] Harden supplier portal: token-scoped read-only access, server-enforced
- [ ] Remove anon/public RLS policies that are no longer needed
- [ ] Security test: write failing test for each IDOR finding, then close it

### Acceptance criteria
- No Supabase URL or anon key is present in the client bundle
- The supplier portal token grants read access only to the order it was issued for
- All IDOR test cases pass
- Authenticated routes reject unauthenticated requests with 401

---

## WP-2 — Identity and access management

**Status:** Planned  
**Branch:** `wp-2/iam`  
**Depends on:** WP-1

### Goal
Replace anonymous access with verified user identities. Scope write permissions to the
authenticated user's own data.

### Work
- [ ] Integrate identity provider (Microsoft Entra or Supabase Auth with Google)
- [ ] Add `owner_id` / `created_by` columns to tables that need per-user scoping
- [ ] Tighten RLS write policies from `USING(true)` to `USING(auth.uid() = owner_id)`
- [ ] Enable Supabase leaked-password protection
- [ ] Define roles: admin, operator, viewer, external supplier

### Acceptance criteria
- An authenticated user cannot read or modify another user's orders
- Unauthenticated users cannot read any DocTrack data
- Role boundaries are enforced server-side, not only in the UI

---

## WP-3 — ERP integration (SAP inbound)

**Status:** Planned  
**Branch:** `wp-3/erp-inbound`  
**Depends on:** WP-1

### Goal
Receive order and document events from the customer's SAP instance automatically,
replacing the current manual order creation flow.

### Work
- [ ] Define inbound event schema with ERP team
- [ ] Build integration plumbing in n8n (receive only — no business logic)
- [ ] Map SAP document types to DocTrack `document_type` values
- [ ] Handle duplicate / update events idempotently

### Acceptance criteria
- A new SAP shipment order creates a DocTrack order with the correct checklist within 5 minutes
- Duplicate events do not create duplicate orders
- Failures are logged and alertable

---

## WP-4 — Email and SFTP document ingestion

**Status:** Planned  
**Branch:** `wp-4/doc-ingestion`  
**Depends on:** WP-1

### Goal
Automatically ingest documents arriving by email or SFTP from freight forwarders,
chambers of commerce, and inspection bodies — the hard part this product exists to solve.

### Work
- [ ] Define ingestion rules: sender domain / subject pattern → order + document type
- [ ] Build email ingestion pipeline (Resend inbound, or Microsoft mail server)
- [ ] Build SFTP listener
- [ ] Classify incoming documents and attach to correct checklist item
- [ ] Handle unmatched documents (quarantine queue for manual review)

### Acceptance criteria
- A document emailed from a known freight forwarder address is attached to the correct order within 2 minutes
- Unmatched documents appear in a review queue, not silently dropped
- No document is lost on transient failure (at-least-once delivery)

---

## Deferred / unprioritised

- Microsoft Entra SSO (depends on WP-2 IAM decision)
- Resend transactional email (internal notifications, document distribution)
- Customer-facing portal hardening (depends on WP-1)
- Audit trail (separate from `order_activity` — append-only, tamper-evident)
- Mobile / offline support
