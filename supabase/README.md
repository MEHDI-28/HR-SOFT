# Supabase — Org-Ch / HR-SOFT

## Environment

- Environment: development / clean initial database
- Project ref: `xdjhshktjtevusigqzya`
- Region: `us-east-2`
- PostgreSQL: 17.11
- Auth users: 0
- HR tenant/company/app-user records: 0
- Storage buckets: 0

## Source of truth and migration workflow

The repository's `supabase/migrations/` directory is the deployment source of truth. The five migration files currently present correspond to the five versions recorded in `supabase_migrations.schema_migrations`.

Never edit an already-applied migration to change the live database. Add a new migration for every subsequent schema or bootstrap-state change. Review the exact pending migration list before deployment.

For Supabase CLI v3, explicitly select the hosted target. CLI v3 defaults many database commands to the local stack:

```powershell
supabase login
supabase link --project-ref xdjhshktjtevusigqzya
supabase db push --remote --dry-run
# Review the pending list, then:
supabase db push --remote
```

Do not run `db reset --remote` against this project; it is destructive. The local Supabase CLI is not currently installed on the Windows workstation. Database verification and applied migration history were checked through the connected Supabase project tools.

## API exposure

PostgREST is restricted at the `authenticator` role to `public,graphql_public`, and the repository config lists the same schemas. Do not expose `hr_core`, `hr_org`, `hr_security`, `hr_audit`, `hr_workflow`, `hr_files`, `hr_notify`, `hr_sensitive`, `hr_events`, or `hr_internal`.

Business operations must go through narrowly scoped, audited public RPC or Edge Function wrappers. Do not grant direct table access to the browser.

## Current security posture

- All 57 HR domain tables have both RLS and FORCE RLS enabled.
- Broad table, sequence, and function privileges are revoked from `PUBLIC`, `anon`, and `authenticated`.
- The only direct table SELECT grants to `authenticated` are narrow reads for the current tenant, the caller's own app-user mapping, and active system/permission catalogue rows. The relevant RLS policies further restrict these reads.
- No direct INSERT, UPDATE, or DELETE grants are provided to browser roles.
- Supabase Security Advisor reports 53 `RLS Enabled No Policy` informational findings. These tables are intentionally fail-closed while their permission-aware business APIs are being implemented. Do not silence this by adding permissive policies.
- Performance Advisor reports unused indexes in the empty development database; reassess after representative test data and workload exist.
- PostgREST's schema allow-list prevents the private HR schemas from being queried through the Data API.

## Auth and first-admin bootstrap

- `public.hr_session_status()` returns only authentication and active HR mapping status.
- `public.hr_bootstrap_first_admin(...)` is a SECURITY INVOKER wrapper around the private, token-protected bootstrap implementation.
- The bootstrap creates one tenant, one company, one app-user mapping, the HR-SOFT permission catalogue, a tenant-owner group, an explicit tenant scope, memberships, non-sensitive permissions, and an audit event.
- Sensitive-data permissions, permission-catalogue editing, and temporary-access administration are deliberately not granted by default.
- The database stores only a SHA-256 hash of the one-time bootstrap token. It never stores the plaintext token. If the owner no longer has the original token, rotate the invite through a new reviewed migration before first use.
- No Auth user, tenant, company, or HR app-user has been provisioned yet. A successful Auth sign-up alone does not grant access to HR data.

## Permission resolver status — not production-ready

The internal `hr_internal.evaluate_permission_context` function is installed and has no EXECUTE grant to `anon` or `authenticated`. It is not currently referenced by RLS policies or public business APIs.

It is a first implementation of the Stage 6 v2.4 contract, not a completed acceptance-tested resolver. Before any business API uses it, complete and test at least:

1. Trusted wrappers must load the actual resource and derive tenant/company/org-unit/personnel context; never trust context IDs supplied by the browser.
2. Historical org-unit descendant evaluation must use the hierarchy valid at the record's `effective_at`. The current implementation fails closed for historical descendant checks.
3. Temporary access scope-null semantics, approval/reason constraints, and expiry reason codes must be reconciled exactly with the Stage 6 contract.
4. Add pgTAP or equivalent tests for cross-tenant isolation, multi-group deny-overrides-allow, expired memberships, temporary access, scope boundaries, and sensitive-data audit.
5. Sensitive read/download wrappers must emit audit events in the same trusted transaction.

Do not create permissive RLS policies or connect the resolver to business tables until these acceptance tests pass.

## Sensitive data and Storage

Sensitive identity and bank details are separated into `hr_sensitive`. The clean-install `hr_core.people` table omits the sensitive cleartext identity columns identified in the design review.

No Storage buckets or file APIs have been provisioned. When implemented, use private buckets, server-side authorization against the owning HR record, short-lived signed URLs, independent download permission, and audit events.

## Browser configuration

The local `supabase-config.js` is ignored by Git. It contains only the project's URL and publishable key. Never put a `service_role` key, secret API key, or database password in browser code or any tracked file. The tracked `supabase-config.example.js` and `.env.example` contain placeholders only.
