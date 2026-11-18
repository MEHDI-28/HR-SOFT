-- HR-SOFT | RLS lockdown foundation
-- Version 0.1 | DESIGN / REVIEW DRAFT ONLY
-- DO NOT RUN until the baseline and supplemental migrations have been reviewed.
-- This migration deliberately uses default-deny for business tables.
-- It does NOT yet grant business-data access by company/org/personnel scope.

begin;

-- Helper functions are SECURITY DEFINER because they must resolve the current
-- internal account while app_users itself is protected by RLS.
-- Keep ownership with postgres (or another tightly controlled BYPASSRLS owner).
create or replace function hr_security.current_app_user_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select au.id
  from hr_security.app_users as au
  where au.auth_user_id = auth.uid()
    and au.status = 'active'
  limit 1
$$;

create or replace function hr_security.current_tenant_id()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select au.tenant_id
  from hr_security.app_users as au
  where au.auth_user_id = auth.uid()
    and au.status = 'active'
  limit 1
$$;

revoke all on function hr_security.current_app_user_id() from public;
revoke all on function hr_security.current_tenant_id() from public;
revoke all on function hr_security.current_app_user_id() from anon;
revoke all on function hr_security.current_tenant_id() from anon;
grant execute on function hr_security.current_app_user_id() to authenticated;
grant execute on function hr_security.current_tenant_id() to authenticated;

-- Keep these schemas out of the exposed Data API schema list.
-- Schema USAGE is not equivalent to table access; table grants remain absent
-- except for the narrow self-profile and global read-only catalogue below.
grant usage on schema hr_core, hr_org, hr_security, hr_audit,
    hr_workflow, hr_files, hr_notify, hr_sensitive to authenticated;

-- Enable RLS on every table in the baseline and supplemental model.
alter table hr_core.tenants enable row level security;
alter table hr_core.companies enable row level security;
alter table hr_core.people enable row level security;
alter table hr_core.personnel_records enable row level security;
alter table hr_security.app_users enable row level security;
alter table hr_org.org_layers enable row level security;
alter table hr_org.org_units enable row level security;
alter table hr_org.positions enable row level security;
alter table hr_org.position_relationships enable row level security;
alter table hr_org.position_assignments enable row level security;
alter table hr_security.systems enable row level security;
alter table hr_security.user_groups enable row level security;
alter table hr_security.group_memberships enable row level security;
alter table hr_security.permissions enable row level security;
alter table hr_security.group_permission_rules enable row level security;
alter table hr_security.data_scopes enable row level security;
alter table hr_security.group_scope_assignments enable row level security;
alter table hr_security.temporary_access enable row level security;
alter table hr_audit.audit_events enable row level security;
alter table hr_audit.permission_change_history enable row level security;
alter table hr_workflow.requests enable row level security;
alter table hr_workflow.steps enable row level security;
alter table hr_workflow.decisions enable row level security;
alter table hr_workflow.capacity_change_requests enable row level security;
alter table hr_workflow.capacity_request_revisions enable row level security;
alter table hr_workflow.capacity_request_notes enable row level security;
alter table hr_files.file_objects enable row level security;
alter table hr_files.file_versions enable row level security;
alter table hr_workflow.capacity_request_files enable row level security;
alter table hr_notify.user_preferences enable row level security;
alter table hr_notify.notifications enable row level security;
alter table hr_files.export_jobs enable row level security;
alter table hr_files.export_job_items enable row level security;
alter table hr_sensitive.identity_data enable row level security;
alter table hr_sensitive.bank_accounts enable row level security;

-- Revoke broad table access. Explicit grants are added only when a matching
-- policy and tests exist. This is intentionally fail-closed.
revoke all on all tables in schema hr_core from public, anon, authenticated;
revoke all on all tables in schema hr_org from public, anon, authenticated;
revoke all on all tables in schema hr_security from public, anon, authenticated;
revoke all on all tables in schema hr_audit from public, anon, authenticated;
revoke all on all tables in schema hr_workflow from public, anon, authenticated;
revoke all on all tables in schema hr_files from public, anon, authenticated;
revoke all on all tables in schema hr_notify from public, anon, authenticated;
revoke all on all tables in schema hr_sensitive from public, anon, authenticated;

-- Narrow bootstrap reads only.
grant select on hr_core.tenants to authenticated;
grant select on hr_security.app_users to authenticated;
grant select on hr_security.systems to authenticated;
grant select on hr_security.permissions to authenticated;

create policy tenant_self_read
on hr_core.tenants
for select to authenticated
using (id = (select hr_security.current_tenant_id()));

create policy app_user_self_read
on hr_security.app_users
for select to authenticated
using (auth_user_id = (select auth.uid())
   and id = (select hr_security.current_app_user_id())
   and status = 'active');

-- Global catalogues only; no tenant-specific data is exposed here.
create policy active_system_catalogue_read
on hr_security.systems
for select to authenticated
using (is_active = true);

create policy permission_catalogue_read
on hr_security.permissions
for select to authenticated
using (true);

-- No policies are created for companies, people, personnel, organization,
-- memberships, workflow, audit, files, notifications, or sensitive data.
-- With RLS enabled and no policy, authenticated users cannot access those
-- tables. Later migrations must add permission + data-scope-aware policies.

commit;
