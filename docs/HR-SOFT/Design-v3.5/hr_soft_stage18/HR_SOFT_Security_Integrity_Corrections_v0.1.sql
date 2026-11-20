-- HR-SOFT Stage 18 / Security integrity corrections v0.1
-- PROPOSAL ONLY. NOT EXECUTED.
-- Preconditions:
--   1) Baseline v0.1 and supplemental v0.1 exist in a disposable DB.
--   2) Stage 13 user security migration v0.4 has been corrected so that
--      bulletins has UNIQUE(tenant_id,id) BEFORE bulletin_acknowledgements FK.
--   3) Stage 16 correction snippets v0.6 have been reviewed.
--   4) Run preflight queries and resolve existing invalid rows before VALIDATE.
--
-- This file does not create permissive RLS policies or grant client access.

begin;

-- ---------------------------------------------------------------------------
-- A. Enforce that each group permission rule belongs to the group's system
--    and the permission catalogue entry's system.
-- ---------------------------------------------------------------------------

alter table hr_security.group_permission_rules
  add column if not exists system_id uuid;

-- Derive the authoritative system from the referenced group, never the client.
update hr_security.group_permission_rules r
set system_id = g.system_id
from hr_security.user_groups g
where g.tenant_id = r.tenant_id
  and g.id = r.group_id
  and r.system_id is distinct from g.system_id;

alter table hr_security.group_permission_rules
  alter column system_id set not null;

create unique index if not exists uq_user_groups_tenant_system_id
  on hr_security.user_groups(tenant_id, system_id, id);

create unique index if not exists uq_permissions_system_id_v18
  on hr_security.permissions(system_id, id);

alter table hr_security.group_permission_rules
  add constraint fk_group_permission_rule_group_system_v18
  foreign key (tenant_id, system_id, group_id)
  references hr_security.user_groups(tenant_id, system_id, id)
  not valid;

alter table hr_security.group_permission_rules
  add constraint fk_group_permission_rule_permission_system_v18
  foreign key (system_id, permission_id)
  references hr_security.permissions(system_id, id)
  not valid;

-- Preflight: must return zero rows before validating the permission FK.
-- SELECT r.id, r.system_id, p.system_id AS permission_system_id
-- FROM hr_security.group_permission_rules r
-- JOIN hr_security.permissions p ON p.id = r.permission_id
-- WHERE r.system_id <> p.system_id;

-- Validate only after the preflight returns zero rows:
-- ALTER TABLE hr_security.group_permission_rules
--   VALIDATE CONSTRAINT fk_group_permission_rule_group_system_v18;
-- ALTER TABLE hr_security.group_permission_rules
--   VALIDATE CONSTRAINT fk_group_permission_rule_permission_system_v18;

-- ---------------------------------------------------------------------------
-- B. Enforce approval metadata for tenant-wide temporary access.
--    A NULL scope is never interpreted as an implicit allow.
-- ---------------------------------------------------------------------------

alter table hr_security.temporary_access
  add column if not exists approved_at timestamptz;

alter table hr_security.temporary_access
  add constraint fk_temporary_access_approver_v18
  foreign key (tenant_id, approved_by)
  references hr_security.app_users(tenant_id, id)
  not valid;

alter table hr_security.temporary_access
  add constraint ck_temporary_access_approval_pair_v18
  check (
    (approved_by is null and approved_at is null)
    or
    (approved_by is not null and approved_at is not null)
  ) not valid;

alter table hr_security.temporary_access
  add constraint ck_temporary_access_global_scope_approval_v18
  check (
    scope_id is not null
    or
    (approved_by is not null and approved_at is not null)
  ) not valid;

-- Preflight: rows with NULL scope must have approver and approval timestamp.
-- SELECT id, tenant_id FROM hr_security.temporary_access
-- WHERE scope_id IS NULL AND (approved_by IS NULL OR approved_at IS NULL);

-- Validate only after cleanup:
-- ALTER TABLE hr_security.temporary_access
--   VALIDATE CONSTRAINT fk_temporary_access_approver_v18;
-- ALTER TABLE hr_security.temporary_access
--   VALIDATE CONSTRAINT ck_temporary_access_approval_pair_v18;
-- ALTER TABLE hr_security.temporary_access
--   VALIDATE CONSTRAINT ck_temporary_access_global_scope_approval_v18;

-- ---------------------------------------------------------------------------
-- C. Make account login/access event records append-only.
--    Requires hr_audit.reject_mutation_append_only() from Stage 5 v0.2.
-- ---------------------------------------------------------------------------

drop trigger if exists trg_user_login_events_append_only
  on hr_audit.user_login_events;
create trigger trg_user_login_events_append_only
before update or delete on hr_audit.user_login_events
for each row execute function hr_audit.reject_mutation_append_only();

drop trigger if exists trg_user_access_events_append_only
  on hr_audit.user_access_events;
create trigger trg_user_access_events_append_only
before update or delete on hr_audit.user_access_events
for each row execute function hr_audit.reject_mutation_append_only();

commit;

-- POST-MIGRATION:
-- 1) Validate all *_v18 constraints after preflight cleanup.
-- 2) Test that same-system group/permission links succeed and cross-system
--    links fail for both INSERT and UPDATE.
-- 3) Test NULL-scope temporary access without approval fails.
-- 4) Test approver must be an app_user in the same Tenant.
-- 5) Test UPDATE/DELETE of login/access events fails for application roles.
-- 6) Keep all RLS business policies fail-closed until resolver and wrapper tests pass.
