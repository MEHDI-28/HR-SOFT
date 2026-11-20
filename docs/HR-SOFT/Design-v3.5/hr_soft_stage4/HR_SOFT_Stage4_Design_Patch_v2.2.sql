-- HR-SOFT Stage 4 / v2.2
-- DESIGN PATCH ONLY. DO NOT RUN IN PRODUCTION.
-- Prerequisites: inspect current schema, apply baseline in disposable dev DB,
-- resolve all TODOs, then run migrations in a transaction and execute pgTAP.

begin;

create schema if not exists hr_audit;

-- 1) Dedicated sensitive-access audit stream.
create table if not exists hr_audit.sensitive_access_events (
    id bigint generated always as identity primary key,
    tenant_id uuid not null references hr_core.tenants(id),
    actor_app_user_id uuid,
    event_key text not null,
    subject_type text not null,
    subject_id uuid not null,
    object_id uuid,
    file_version_id uuid,
    outcome text not null check (outcome in ('allowed','denied','error')),
    purpose text,
    policy_version text not null default '2.2',
    request_id text,
    source_ip inet,
    user_agent text,
    occurred_at timestamptz not null default now(),
    metadata jsonb not null default '{}'::jsonb,
    foreign key (tenant_id, actor_app_user_id)
      references hr_security.app_users(tenant_id, id)
);

create index if not exists ix_sensitive_access_tenant_time
  on hr_audit.sensitive_access_events(tenant_id, occurred_at desc);
create index if not exists ix_sensitive_access_subject
  on hr_audit.sensitive_access_events(tenant_id, subject_type, subject_id, occurred_at desc);
create index if not exists ix_sensitive_access_actor
  on hr_audit.sensitive_access_events(tenant_id, actor_app_user_id, occurred_at desc);

alter table hr_audit.sensitive_access_events enable row level security;

-- No direct authenticated write/read grants are added here.
-- Insert must happen through a narrowly granted server-side function.
-- Read is restricted to a separately permission-checked audit endpoint.

-- 2) File storage path uniqueness.
-- Before applying, detect and resolve existing duplicates:
-- SELECT storage_bucket, storage_object_path, count(*)
-- FROM hr_files.file_versions
-- GROUP BY 1,2 HAVING count(*) > 1;
create unique index if not exists uq_file_version_storage_object
  on hr_files.file_versions(storage_bucket, storage_object_path);

-- 3) Complete scope target shape validation.
-- Existing rows must be checked before validating this constraint.
alter table hr_security.data_scopes
  drop constraint if exists data_scopes_target_shape_v2;
alter table hr_security.data_scopes
  add constraint data_scopes_target_shape_v2 check (
    (scope_type = 'tenant'
      and company_id is null and org_unit_id is null and personnel_record_id is null)
    or
    (scope_type = 'company'
      and company_id is not null and org_unit_id is null and personnel_record_id is null)
    or
    (scope_type = 'org_unit'
      and company_id is not null and org_unit_id is not null and personnel_record_id is null)
    or
    (scope_type = 'personnel'
      and company_id is not null and org_unit_id is null and personnel_record_id is not null)
  ) not valid;

-- Validate only after correcting legacy rows:
-- ALTER TABLE hr_security.data_scopes VALIDATE CONSTRAINT data_scopes_target_shape_v2;

-- 4) Append-only enforcement for sensitive access log.
create or replace function hr_audit.reject_sensitive_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'sensitive access events are append-only';
end;
$$;

drop trigger if exists trg_sensitive_events_no_update on hr_audit.sensitive_access_events;
create trigger trg_sensitive_events_no_update
before update or delete on hr_audit.sensitive_access_events
for each row execute function hr_audit.reject_sensitive_event_mutation();

-- 5) Tenant-safe helper for current app user.
-- Mirrors baseline columns; verify auth schema and function ownership in target.
create or replace function hr_security.current_app_user_id_v2()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select au.id
  from hr_security.app_users au
  where au.auth_user_id = auth.uid()
    and au.status = 'active'
  limit 1
$$;

revoke all on function hr_security.current_app_user_id_v2() from public;
revoke all on function hr_security.current_app_user_id_v2() from anon;
grant execute on function hr_security.current_app_user_id_v2() to authenticated;

-- 6) Explicit TODOs, intentionally not generated as permissive policies:
-- a) Build authoritative permission/scope resolver after permission keys are frozen.
-- b) Add company-consistency triggers for org_units, positions and assignments.
-- c) Add owner registry for file_objects; reject unknown owner_schema/owner_table.
-- d) Add Storage policies only after resolver can validate file + owner record.
-- e) Add server-side API grants/RPC allowlist; keep internal tables unexposed.
-- f) Convert audit_events, permission_change_history, decisions, revisions,
--    notes and file_versions to append-only where applicable.
-- g) Add one-open-capacity-request partial unique index after status refactor.

commit;

-- pgTAP test skeleton is in HR_SOFT_RLS_Test_Plan_v2.2.md.
