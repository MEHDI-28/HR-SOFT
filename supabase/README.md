# Supabase — Org-Ch / HR-SOFT

## Environment and bootstrap status

- Hosted Supabase target: production (linked through Supabase CLI)
- Repository branch: `docs/hr-soft-design-v3.5`
- Project ref: `xdjhshktjtevusigqzya`
- Region: `us-east-2`
- PostgreSQL: 17
- Applied HR-SOFT migrations: 9
- HR-SOFT domain tables: 57
- Auth users: 1 (email confirmed)
- Active HR app-user mappings: 1
- Tenants: 1
- Companies: 1
- Active tenant-owner group memberships for the initial user: 1
- Allow rules configured for the tenant-owner group: 68
- Bootstrap invite: redeemed
- Operational personnel, organization-unit, position, and workflow data: not yet provisioned
- Storage buckets: 0
- Public read-only organization APIs: 2 (`hr_admin_get_context_v1`, `hr_org_get_admin_snapshot_v1`)
- Read-only browser page: `org-structure-readonly.html` (positive authenticated-session test pending)

The first-admin bootstrap has completed. The browser session was refreshed and `public.hr_session_status()` returned the provisioned state, causing the bootstrap form to remain hidden.

## Source of truth and migration workflow

The repository's `supabase/migrations/` directory is the deployment source of truth. Nine migration versions are recorded in `supabase_migrations.schema_migrations`: five foundation/bootstrap migrations and four hardening/read-API migrations deployed on 2026-11-20. The exact applied versions are listed in `docs/HR-SOFT/Implementation-v0.1/HR_SOFT_Supabase_Deployment_Report_v0.3.md`. The older local proposal `20261119090000_hr_soft_resolver_deny_precedence_hardening.sql` is not the deployed source file; do not deploy it or create duplicate history from it.

Never edit an already-applied migration to change the live database. Add a new migration for every subsequent schema or bootstrap-state change. Review the exact pending migration list before deployment.

For Supabase CLI v3, explicitly select the hosted target. CLI v3 defaults many database commands to the local stack:

```powershell
supabase login
supabase link --project-ref xdjhshktjtevusigqzya
supabase db push --remote --dry-run --skip-vault
# Review the pending list, then deploy only with explicit approval:
supabase db push --remote --skip-vault
```

Do not run `db reset --remote` against this project; it is destructive. Supabase CLI 3.2.0 is installed and authenticated on the Windows workstation, and the repository is linked to `xdjhshktjtevusigqzya` (Org-Ch). The 2026-11-19 dry-run note above is historical and predates the 2026-11-20 deployment. A direct hosted query now confirms exactly nine recorded versions (the five foundation migrations and four hardening/read-API migrations listed in the deployment report). Before any future deployment, run `supabase migration list --remote` and `supabase db push --remote --dry-run --skip-vault` again; do not assume the old pending list is current.

## API exposure

PostgREST is restricted at the `authenticator` role to `public,graphql_public`, and the repository config lists the same schemas. Do not expose `hr_core`, `hr_org`, `hr_security`, `hr_audit`, `hr_workflow`, `hr_files`, `hr_notify`, `hr_sensitive`, `hr_events`, or `hr_internal`.

Business operations must go through narrowly scoped, audited public RPC or Edge Function wrappers. Do not grant direct table access to the browser.

Public RPCs include `hr_session_status()`, the protected first-admin bootstrap wrapper, and two authenticated-only read RPCs: `hr_admin_get_context_v1()` and `hr_org_get_admin_snapshot_v1(...)`. The read-only UI uses the latter two. No business-data write API is available.

## Current security posture

- All 57 HR domain tables have both RLS and FORCE RLS enabled.
- Broad table, sequence, and function privileges are revoked from `PUBLIC`, `anon`, and `authenticated`.
- Narrow direct reads are limited to the current tenant, the caller's own app-user mapping, and active system/permission catalogue rows; applicable RLS policies further restrict them.
- No direct INSERT, UPDATE, or DELETE grants are provided to browser roles.
- Supabase Security Advisor reports 53 `RLS Enabled No Policy` informational findings. These tables are intentionally fail-closed while permission-aware business APIs are being implemented. Do not silence this by adding permissive policies.
- Performance Advisor reports unused indexes in a development database with no representative workload; reassess after test data and workload exist.
- Supabase Auth's leaked-password protection is currently disabled and should be enabled through Auth settings after review.

## First-admin bootstrap and authorization

- `public.hr_session_status()` returns only authentication and active HR mapping status.
- `public.hr_bootstrap_first_admin(...)` is a SECURITY INVOKER wrapper around the private, token-protected bootstrap implementation.
- The bootstrap created one tenant, one company, one app-user mapping, the HR-SOFT permission catalogue, a tenant-owner group, a tenant scope, memberships, non-sensitive permission rules, and an audit event.
- The initial user is active and belongs to `tenant_owner` (عنوان: «مدیر کل سازمان»). The group has 68 configured Allow rules.
- Sensitive-data permissions and selected high-risk administrative capabilities are deliberately not granted by default. The configured Allow count must not be treated as proof that the resolver and every business operation have passed acceptance tests.
- The database stores only a SHA-256 hash of the one-time bootstrap token. The invite was redeemed; do not reuse or disclose the plaintext token.

## Permission resolver status — limited read API deployed; broader acceptance remains open

The internal `hr_internal.evaluate_permission_context` function remains private and is not directly executable by `anon` or `authenticated`. The two public read wrappers call private SECURITY DEFINER implementations that invoke the resolver server-side. The public wrappers are SECURITY INVOKER and executable only by authenticated sessions. The resolver is not wired into broad table-level RLS policies or write APIs.

Before any business API uses it, complete and test at least:

1. Trusted wrappers must load the actual resource and derive tenant/company/org-unit/personnel context; never trust context IDs supplied by the browser.
2. Historical org-unit descendant evaluation must use the hierarchy valid at the record's `effective_at`. The current implementation fails closed for historical descendant checks.
3. Temporary access scope-null semantics, approval/reason constraints, and expiry reason codes must be reconciled exactly with the Stage 6 contract.
4. Add pgTAP or equivalent tests for cross-tenant isolation, multi-group deny-overrides-allow, expired memberships, temporary access, scope boundaries, and sensitive-data audit.
5. Sensitive read/download wrappers must emit audit events in the same trusted transaction.

Do not create permissive RLS policies or connect the resolver to business tables until these acceptance tests pass.

## Deployed hardening and read-only API — 2026-11-20

The following four migration files have been deployed to the hosted project and recorded in migration history:

- `20261120063245_hr_soft_resolver_deny_precedence_hardening_20261119.sql`
- `20261120063501_hr_soft_org_admin_read_api_v1.sql`
- `20261120063528_hr_soft_org_snapshot_reference_redaction_fix.sql`
- `20261120063557_hr_soft_org_api_invoker_wrappers.sql`

The read-only browser page calls `hr_admin_get_context_v1()` and `hr_org_get_admin_snapshot_v1(...)`. It does not access `hr_*` tables directly and contains no write operations. The legacy editor remains localStorage-backed. See the deployment report for ACLs, API contracts, and remaining tests.

The deployed hardening migration:
- removes the operation-flag gate from the deny count while retaining it for allow;
- aligns `current_app_user_id()`, `current_tenant_id()`, and `hr_session_status()` with `archived_at IS NULL`;
- versions the resolver as 2.4.2;
- adds the two missing temporary-access approval CHECK constraints from Stage 18.

Runtime inspection confirmed that the same-system group/permission constraints and append-only login/access-event triggers already exist. The `temporary_access` table has `approved_at` and a same-tenant approver FK; the approval-pair and null-scope approval CHECK constraints were added by the deployed hardening migration and validated. The table contained zero rows during preflight, so no cleanup was needed at inspection time.

The resolver continues to treat NULL scope as non-matching; it is not automatically tenant-wide. Any future tenant-wide temporary access requires explicit semantics and a trusted server-side approval command satisfying SEC-414.

The migration was applied to hosted Supabase on 2026-11-20. The deployed source, ACL checks, constraint preflight, and hosted unauthenticated checks are documented in `HR_SOFT_Supabase_Deployment_Report_v0.3.md`. Earlier disposable PostgreSQL smoke tests are supplemental evidence only; they do not prove every hosted JWT, tenant-scope, deny-precedence, or UI acceptance scenario. The hosted project currently runs PostgreSQL 17.11.

Repeat the local checks from the repository root:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\supabase\tests\validate_resolver_hardening.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\supabase\tests\run_resolver_migration_smoke.ps1
$env:HR_SOFT_POSTGRES_IMAGE = 'public.ecr.aws/docker/library/postgres:17-alpine'
powershell -NoProfile -ExecutionPolicy Bypass -File .\supabase\tests\run_resolver_migration_smoke.ps1
Remove-Item Env:HR_SOFT_POSTGRES_IMAGE
node .\supabase\tests\validate_frontend_security.cjs
# Start the isolated local stack before the JWT/RLS test:
supabase start -x realtime,storage-api,imgproxy,mailpit,postgres-meta,studio,edge-runtime,logflare,vector,supavisor
powershell -NoProfile -ExecutionPolicy Bypass -File .\supabase\tests\run_local_jwt_rls.ps1
supabase stop
```

The smoke runner defaults to `postgres:16-alpine`; set `HR_SOFT_POSTGRES_IMAGE` to run the same suite against another disposable PostgreSQL image. Both PostgreSQL 16.15 and 17.12 runs passed in this review.

A local Supabase stack using PostgreSQL 17.11 applied all nine repository migrations in order. Local verification confirmed 57/57 HR tables have RLS and FORCE RLS, the two new CHECK constraints are validated, and resolver/identity/session function ACLs match the intended grants. The unauthenticated `authenticated` database role receives NULL identity, zero visible tenant/app-user rows, and `is_authenticated=false`/`is_provisioned=false`.

The repeatable `supabase/tests/run_local_jwt_rls.ps1` test then used real Auth-issued JWTs through local PostgREST. Two active test users in separate tenants each saw exactly their own tenant and app-user mapping, with zero rows from the other tenant. An archived account and an authenticated user without an HR mapping saw zero tenant/app-user rows and were not provisioned. All test users saw only active system/permission catalogue rows; the anonymous role was denied access to the authenticated-only test probe. The test removed all temporary Auth users, fixture rows, and the temporary probe function; a follow-up count confirmed zero test artifacts. Detailed evidence and remaining limitations are recorded in `docs/HR-SOFT/Analysis-v0.1/HR_SOFT_Real_JWT_RLS_Test_Report_v0.1.md`.

These real-JWT tests cover the current tenant/app-user/catalogue RLS policies only. They do not prove tenant isolation for every future business API, CRUD, Resolver invocation through all trusted wrappers, sensitive-data audit, or the full ACL/SEC acceptance matrix. The four hosted migrations listed above have been applied; no additional production migration is authorized by this task. The positive browser test of the new organization snapshot page still requires a real authenticated admin session. Do not broaden permissions or deploy additional database changes until the remaining acceptance gaps are resolved and explicitly reviewed.

## Sensitive data and Storage

Sensitive identity and bank details are separated into `hr_sensitive`. The clean-install `hr_core.people` table omits the sensitive cleartext identity columns identified in the design review.

No Storage buckets or file APIs have been provisioned. When implemented, use private buckets, server-side authorization against the owning HR record, short-lived signed URLs, independent download permission, and audit events.

## Browser configuration

The local `supabase-config.js` is ignored by Git. It contains only the project's URL and publishable key. Never put a `service_role` key, secret API key, or database password in browser code or any tracked file.

The tracked `supabase-config.example.js` and `.env.example` contain placeholders only.
