from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
DESIGN = ROOT / "docs" / "HR-SOFT" / "Design-v3.5"
OUT = ROOT / "supabase" / "migrations" / "20261118201829_hr_soft_foundation.sql"

def read(rel):
    return (DESIGN / rel).read_text(encoding="utf-8-sig")

def strip_tx(sql):
    sql = re.sub(r"(?im)^\s*begin(?:\s+transaction)?\s*;\s*$", "", sql)
    sql = re.sub(r"(?im)^\s*commit\s*;\s*$", "", sql)
    return sql.strip()

def replace_once(source, old, new, label):
    count = source.count(old)
    if count != 1:
        raise RuntimeError(f"{label}: expected one exact match, found {count}")
    return source.replace(old, new, 1)

baseline = read("hr_soft_stage2/HR_SOFT_Postgres_Baseline_v0.1.sql")
baseline, n = re.subn(
    r"(?m)^\s*father_name text,\n\s*birth_date date,\n\s*gender_code text,\n\s*birthplace_code text,\n\s*mobile_e164 text,\n",
    "", baseline
)
if n != 1:
    raise RuntimeError(f"people PII columns: expected one block, found {n}")

baseline = replace_once(
    baseline,
    "    unique (tenant_id, id),\n    unique (tenant_id, system_id, group_key)\n",
    "    unique (tenant_id, id),\n    unique (tenant_id, system_id, id),\n    unique (tenant_id, system_id, group_key)\n",
    "user_groups composite key"
)
baseline = replace_once(
    baseline,
    "    description text,\n    unique (system_id, permission_key)\n",
    "    description text,\n    is_active boolean not null default true,\n    unique (system_id, permission_key),\n    unique (system_id, id)\n",
    "permissions active/system key"
)

group_rules = """create table if not exists hr_security.group_permission_rules (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    system_id uuid not null,
    group_id uuid not null,
    permission_id uuid not null,
    can_add boolean not null default false,
    can_edit boolean not null default false,
    can_delete boolean not null default false,
    effect text not null default 'allow'
        check (effect in ('allow', 'deny')),
    changed_at timestamptz not null default now(),
    changed_by uuid,
    unique (tenant_id, id),
    unique (tenant_id, group_id, permission_id),
    foreign key (tenant_id, system_id, group_id)
        references hr_security.user_groups(tenant_id, system_id, id),
    foreign key (system_id, permission_id)
        references hr_security.permissions(system_id, id)
);"""
baseline, n = re.subn(
    r"create table if not exists hr_security\.group_permission_rules \(.*?\n\);",
    group_rules, baseline, count=1, flags=re.S
)
if n != 1:
    raise RuntimeError("group_permission_rules block not replaced")

temporary_access = """create table if not exists hr_security.temporary_access (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    app_user_id uuid not null,
    system_id uuid not null,
    permission_id uuid not null,
    scope_id uuid,
    effect text not null check (effect in ('allow', 'deny')),
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    reason text not null,
    approved_by uuid,
    approved_at timestamptz,
    created_at timestamptz not null default now(),
    created_by uuid,
    unique (tenant_id, id),
    foreign key (tenant_id, app_user_id)
        references hr_security.app_users(tenant_id, id),
    foreign key (system_id, permission_id)
        references hr_security.permissions(system_id, id),
    foreign key (tenant_id, scope_id)
        references hr_security.data_scopes(tenant_id, id),
    foreign key (tenant_id, approved_by)
        references hr_security.app_users(tenant_id, id),
    foreign key (tenant_id, created_by)
        references hr_security.app_users(tenant_id, id),
    check (ends_at > starts_at),
    check (
      effect <> 'allow'
      or (scope_id is not null and approved_by is not null and approved_at is not null)
    )
);"""
baseline, n = re.subn(
    r"create table if not exists hr_security\.temporary_access \(.*?\n\);",
    temporary_access, baseline, count=1, flags=re.S
)
if n != 1:
    raise RuntimeError("temporary_access block not replaced")

supplemental = read("hr_soft_stage2/HR_SOFT_Workflow_Files_Sensitive_v0.1.sql")
stage4 = read("hr_soft_stage4/HR_SOFT_Stage4_Design_Patch_v2.2.sql")
stage5 = read("hr_soft_stage5/HR_SOFT_Migration_Proposal_v0.2.sql")
stage7 = read("hr_soft_stage7/HR_SOFT_Temporal_Outbox_Proposal_v2.5.sql")
stage12 = read("LATEST/HR_SOFT_Organization_Extension_v0.3.1.sql")
stage13 = read("hr_soft_stage13/HR_SOFT_User_Security_Bulletin_Migration_v0.4.sql")
stage14 = read("hr_soft_stage14/HR_SOFT_Personnel_Extension_v0.5.sql")
stage16 = read("hr_soft_stage16/HR_SOFT_SQL_Correction_Snippets_v0.6.sql")
stage3 = read("hr_soft_stage3/HR_SOFT_RLS_Lockdown_v0.1.sql")

stage5 = replace_once(stage5, "  when 'cancelled' then 'rejected'\n",
                      "  when 'cancelled' then 'cancelled'\n", "cancelled approval mapping")
stage5 = replace_once(stage5, "'pending_approval','approved','rejected','awaiting_reapproval'\n",
                      "'pending_approval','approved','rejected','awaiting_reapproval','cancelled'\n",
                      "cancelled approval status check")
stage5, n = re.subn(
    r"-- File path must be unique across all versions\.\ncreate unique index if not exists uq_file_version_storage_object_v02\n  on hr_files\.file_versions\(storage_bucket, storage_object_path\);\n",
    "", stage5
)
if n != 1:
    raise RuntimeError("duplicate file-version index block not found")

stage13 = replace_once(
    stage13,
    "create table if not exists hr_notify.bulletin_acknowledgements (\n",
    "create unique index if not exists uq_bulletins_tenant_id\n  on hr_notify.bulletins(tenant_id, id);\n\ncreate table if not exists hr_notify.bulletin_acknowledgements (\n",
    "bulletin FK target index order"
)
stage3 = replace_once(
    stage3,
    "create policy permission_catalogue_read\non hr_security.permissions\nfor select to authenticated\nusing (true);",
    "create policy permission_catalogue_read\non hr_security.permissions\nfor select to authenticated\nusing (is_active = true);",
    "permission catalogue policy"
)

hardening = r"""
-- ---------------------------------------------------------------------------
-- HR-SOFT clean-install hardening (2026-11-18)
-- Verified empty Org-Ch development database; no tenant or user data is seeded.
-- ---------------------------------------------------------------------------

alter table hr_security.data_scopes
  add constraint fk_data_scopes_org_unit_company_v1
  foreign key (tenant_id, company_id, org_unit_id)
  references hr_org.org_units(tenant_id, company_id, id) not valid;

alter table hr_security.data_scopes
  add constraint fk_data_scopes_personnel_company_v1
  foreign key (tenant_id, company_id, personnel_record_id)
  references hr_core.personnel_records(tenant_id, company_id, id) not valid;

alter table hr_files.file_objects
  add constraint ck_file_owner_matches_legacy_reference_v1
  check (
    owner_schema = 'hr_workflow'
    and owner_table = 'capacity_change_requests'
    and owner_id = capacity_request_id
  );

drop trigger if exists trg_personnel_record_events_append_only on hr_core.personnel_record_events;
create trigger trg_personnel_record_events_append_only
before update or delete on hr_core.personnel_record_events
for each row execute function hr_audit.reject_mutation_append_only();

drop trigger if exists trg_user_login_events_append_only on hr_audit.user_login_events;
create trigger trg_user_login_events_append_only
before update or delete on hr_audit.user_login_events
for each row execute function hr_audit.reject_mutation_append_only();

drop trigger if exists trg_user_access_events_append_only on hr_audit.user_access_events;
create trigger trg_user_access_events_append_only
before update or delete on hr_audit.user_access_events
for each row execute function hr_audit.reject_mutation_append_only();

drop trigger if exists trg_position_profiles_append_only on hr_org.position_profiles;
create trigger trg_position_profiles_append_only
before update or delete on hr_org.position_profiles
for each row execute function hr_audit.reject_mutation_append_only();

do $$
declare
  t record;
begin
  for t in
    select n.nspname as schema_name, c.relname as table_name
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = any (array[
      'hr_core','hr_org','hr_security','hr_audit',
      'hr_workflow','hr_files','hr_notify','hr_sensitive','hr_events'
    ])
      and c.relkind in ('r','p')
  loop
    execute format('alter table %I.%I enable row level security', t.schema_name, t.table_name);
    execute format('alter table %I.%I force row level security', t.schema_name, t.table_name);
  end loop;
end $$;

revoke all on all tables in schema
  hr_core, hr_org, hr_security, hr_audit, hr_workflow,
  hr_files, hr_notify, hr_sensitive, hr_events
from public, anon, authenticated;

revoke all on all sequences in schema
  hr_core, hr_org, hr_security, hr_audit, hr_workflow,
  hr_files, hr_notify, hr_sensitive, hr_events
from public, anon, authenticated;

revoke all on all functions in schema
  hr_core, hr_org, hr_security, hr_audit, hr_workflow,
  hr_files, hr_notify, hr_sensitive, hr_events
from public, anon, authenticated;

grant usage on schema hr_core, hr_org, hr_security, hr_audit,
  hr_workflow, hr_files, hr_notify, hr_sensitive to authenticated;
grant select on hr_core.tenants to authenticated;
grant select on hr_security.app_users to authenticated;
grant select on hr_security.systems to authenticated;
grant select on hr_security.permissions to authenticated;
grant execute on function hr_security.current_app_user_id() to authenticated;
grant execute on function hr_security.current_tenant_id() to authenticated;

do $$
declare
  s text;
begin
  foreach s in array array[
    'hr_core','hr_org','hr_security','hr_audit',
    'hr_workflow','hr_files','hr_notify','hr_sensitive','hr_events'
  ]
  loop
    execute format(
      'alter default privileges for role postgres in schema %I revoke all on tables from public, anon, authenticated',
      s
    );
    execute format(
      'alter default privileges for role postgres in schema %I revoke all on sequences from public, anon, authenticated',
      s
    );
    execute format(
      'alter default privileges for role postgres in schema %I revoke execute on functions from public, anon, authenticated',
      s
    );
  end loop;
end $$;

create or replace function public.hr_session_status()
returns table (is_authenticated boolean, is_provisioned boolean)
language sql
stable
security definer
set search_path = ''
as $$
  select
    auth.uid() is not null,
    exists (
      select 1 from hr_security.app_users au
      where au.auth_user_id = auth.uid()
        and au.status = 'active'
    );
$$;
revoke all on function public.hr_session_status() from public, anon;
grant execute on function public.hr_session_status() to authenticated;
comment on function public.hr_session_status() is
  'Returns only whether the caller has an active HR-SOFT app_users mapping; exposes no tenant or personnel data.';

alter table hr_org.org_units validate constraint fk_org_units_layer_same_company_v02;
alter table hr_org.org_units validate constraint fk_org_units_parent_same_company_v02;
alter table hr_org.positions validate constraint fk_positions_unit_same_company_v02;
alter table hr_org.positions validate constraint fk_positions_superior_same_company_v02;
alter table hr_org.position_assignments validate constraint fk_assignments_position_same_company_v02;
alter table hr_org.position_assignments validate constraint fk_assignments_personnel_same_company_v02;
alter table hr_org.position_relationships validate constraint fk_position_relationship_from_company_v02;
alter table hr_org.position_relationships validate constraint fk_position_relationship_to_company_v02;
alter table hr_workflow.capacity_change_requests validate constraint ck_capacity_approval_status_v02;
alter table hr_workflow.capacity_change_requests validate constraint ck_capacity_execution_status_v02;
alter table hr_workflow.capacity_change_requests validate constraint ck_capacity_approved_revision_v02;
alter table hr_files.file_objects validate constraint ck_file_owner_type_v02;
alter table hr_files.file_objects validate constraint ck_file_exactly_one_owner_v02;
alter table hr_files.file_objects validate constraint fk_file_capacity_request_owner_v02;
alter table hr_security.data_scopes validate constraint data_scopes_target_shape_v2;
alter table hr_org.positions validate constraint fk_positions_org_position_v03;
alter table hr_security.user_default_groups validate constraint fk_default_group_same_system_v06;
alter table hr_files.file_objects validate constraint ck_file_owner_not_null_v06;
alter table hr_files.file_objects validate constraint ck_file_owner_reference_v06;
alter table hr_security.data_scopes validate constraint fk_data_scopes_org_unit_company_v1;
alter table hr_security.data_scopes validate constraint fk_data_scopes_personnel_company_v1;
"""

parts = [
    "-- HR-SOFT / Supabase Org-Ch clean-install foundation\n",
    "-- Source: stages 2-7, 12-14, 16; adapted for a new empty project.\n",
    "-- Stage 6 resolver SQL is excluded because it is explicitly a non-deployable skeleton.\n",
    "-- No tenant, company, Auth user, permission catalogue or business data is seeded.\n",
    "-- Business tables are RLS-enabled, forced and default-deny; no business API grants are opened.\n\n",
    strip_tx(baseline), strip_tx(supplemental), strip_tx(stage4), strip_tx(stage5),
    strip_tx(stage7), strip_tx(stage12), strip_tx(stage13), strip_tx(stage14),
    strip_tx(stage16), strip_tx(stage3), hardening.strip()
]
sql = "\n\n".join(parts) + "\n"

comment_replacements = [
    ("-- Status: DESIGN ONLY. NOT EXECUTED against Supabase or any database.",
     "-- Source baseline was design-only; this curated migration has been applied to Org-Ch development."),
    ("-- Apply only after project identity, environment, backup and migration review.",
     "-- Applied after verifying the Org-Ch development project was empty and reviewing its schema inventory."),
    ("-- Status: DESIGN ONLY. NOT EXECUTED.",
     "-- Source supplemental design; incorporated into the curated Org-Ch development migration."),
    ("-- DESIGN PATCH ONLY. DO NOT RUN IN PRODUCTION.",
     "-- Source Stage 4 patch; incorporated into the curated Org-Ch development migration."),
    ("-- Prerequisites: inspect current schema, apply baseline in disposable dev DB,",
     "-- Source prerequisites were checked against the verified empty Org-Ch development database;"),
    ("-- resolve all TODOs, then run migrations in a transaction and execute pgTAP.",
     "-- SQL syntax was parsed and the migration applied; pgTAP tests remain pending."),
    ("-- DESIGN DRAFT ONLY. DO NOT RUN against production.",
     "-- Source Stage 5 proposal; adapted for the verified empty Org-Ch development database."),
    ("-- DESIGN DRAFT ONLY. Requires schema review and migrations before use.",
     "-- Source Stage 7 proposal; reviewed and incorporated into the Org-Ch development migration."),
    ("-- DESIGN DRAFT ONLY. Corrected mapping: base values are not headcount capacity.",
     "-- Source Stage 12 proposal; corrected mapping: base values are not headcount capacity."),
    ("-- constraints proposed in Stage 5. Do not run in production.",
     "-- constraints proposed in Stage 5; incorporated in the curated Org-Ch development migration."),
    ("-- DESIGN DRAFT ONLY. Review auth integration and proxy trust before use.",
     "-- Source Stage 13 proposal; Auth integration and proxy trust still require review before public release."),
    ("-- DESIGN DRAFT ONLY. No production execution.",
     "-- Source Stage 14 proposal; included in the curated Org-Ch development foundation."),
    ("-- Version 0.1 | DESIGN / REVIEW DRAFT ONLY",
     "-- Version 0.1 | source RLS design incorporated in the curated migration."),
    ("-- DO NOT RUN until the baseline and supplemental migrations have been reviewed.",
     "-- Source warning resolved: baseline and supplemental SQL were reviewed for empty Org-Ch development."),
    ("-- Apply only to a disposable DB after inspecting actual schema.",
     "-- Stage 16 corrections incorporated after inspecting the empty Org-Ch schema."),
    ("-- NOTE: cancellation status mapping and people.birth_date backfill are NOT",
     "-- Clean-install override: cancellation mapping is corrected; birth_date is stored in hr_sensitive."),
    ("-- automated here; they require inspecting real rows and preserving history.",
     "-- No legacy rows existed, so no legacy-data backfill was required."),
    ("-- Legacy hr_core.people.birth_date is retained during transition.",
     "-- Clean-install override: birth_date exists only in hr_sensitive.person_private_details."),
    ("-- After data migration and all API consumers switch to person_private_details,",
     "-- No legacy people.birth_date column or backfill is created in this new project;"),
    ("-- deprecate it in a later migration; do not drop in this proposal.",
     "-- existing databases require a separate reviewed migration."),
]
for old, new in comment_replacements:
    if old not in sql:
        raise RuntimeError("Missing source comment to normalize: " + old)
    sql = sql.replace(old, new, 1)
OUT.parent.mkdir(parents=True, exist_ok=True)
OUT.write_text(sql, encoding="utf-8", newline="\n")
print(f"Wrote {OUT}")
print(f"Bytes: {OUT.stat().st_size:,}")
print(f"Lines: {len(sql.splitlines()):,}")
