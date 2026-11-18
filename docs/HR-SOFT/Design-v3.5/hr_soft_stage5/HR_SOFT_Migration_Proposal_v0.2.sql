-- HR-SOFT Stage 5 / Proposed migration v0.2
-- DESIGN DRAFT ONLY. DO NOT RUN against production.
-- Assumes baseline v0.1 + supplemental v0.1 have been applied.
-- Review all existing data and run in a disposable development database first.

begin;

-- ---------------------------------------------------------------------------
-- A. Company-scoped candidate keys and foreign keys
-- ---------------------------------------------------------------------------

create unique index if not exists uq_org_layers_tenant_company_id
  on hr_org.org_layers(tenant_id, company_id, id);

create unique index if not exists uq_org_units_tenant_company_id
  on hr_org.org_units(tenant_id, company_id, id);

create unique index if not exists uq_positions_tenant_company_id
  on hr_org.positions(tenant_id, company_id, id);

create unique index if not exists uq_personnel_records_tenant_company_id
  on hr_core.personnel_records(tenant_id, company_id, id);

-- Org unit layer must be in same company.
alter table hr_org.org_units
  add constraint fk_org_units_layer_same_company_v02
  foreign key (tenant_id, company_id, layer_id)
  references hr_org.org_layers(tenant_id, company_id, id)
  not valid;

-- Parent unit must be in same company.
alter table hr_org.org_units
  add constraint fk_org_units_parent_same_company_v02
  foreign key (tenant_id, company_id, parent_unit_id)
  references hr_org.org_units(tenant_id, company_id, id)
  not valid;

-- Position's org unit and superior position must be in same company.
alter table hr_org.positions
  add constraint fk_positions_unit_same_company_v02
  foreign key (tenant_id, company_id, org_unit_id)
  references hr_org.org_units(tenant_id, company_id, id)
  not valid;

alter table hr_org.positions
  add constraint fk_positions_superior_same_company_v02
  foreign key (tenant_id, company_id, superior_position_id)
  references hr_org.positions(tenant_id, company_id, id)
  not valid;

-- Assignment's position and personnel record must belong to same company.
alter table hr_org.position_assignments
  add constraint fk_assignments_position_same_company_v02
  foreign key (tenant_id, company_id, position_id)
  references hr_org.positions(tenant_id, company_id, id)
  not valid;

alter table hr_org.position_assignments
  add constraint fk_assignments_personnel_same_company_v02
  foreign key (tenant_id, company_id, personnel_record_id)
  references hr_core.personnel_records(tenant_id, company_id, id)
  not valid;

-- Position relationships: same-company policy for v1.
alter table hr_org.position_relationships
  add column if not exists company_id uuid;

update hr_org.position_relationships pr
set company_id = p.company_id
from hr_org.positions p
where p.tenant_id = pr.tenant_id
  and p.id = pr.from_position_id
  and pr.company_id is null;

alter table hr_org.position_relationships
  alter column company_id set not null;

alter table hr_org.position_relationships
  add constraint fk_position_relationship_from_company_v02
  foreign key (tenant_id, company_id, from_position_id)
  references hr_org.positions(tenant_id, company_id, id)
  not valid;

alter table hr_org.position_relationships
  add constraint fk_position_relationship_to_company_v02
  foreign key (tenant_id, company_id, to_position_id)
  references hr_org.positions(tenant_id, company_id, id)
  not valid;

-- Validate these constraints only after fixing any reported rows:
-- ALTER TABLE ... VALIDATE CONSTRAINT ...;

-- ---------------------------------------------------------------------------
-- B. File owner registry: restrict owner types and use real FK
-- ---------------------------------------------------------------------------

alter table hr_files.file_objects
  add column if not exists owner_type text,
  add column if not exists capacity_request_id uuid;

-- Backfill only records whose legacy owner is a capacity request.
update hr_files.file_objects fo
set owner_type = 'capacity_request',
    capacity_request_id = fo.owner_id
where fo.owner_type is null
  and fo.owner_schema = 'hr_workflow'
  and fo.owner_table = 'capacity_change_requests';

-- Other existing polymorphic owners must be inventoried and migrated manually.
-- Do not infer an owner type for unrecognized legacy values.

alter table hr_files.file_objects
  add constraint ck_file_owner_type_v02
  check (owner_type in ('capacity_request')) not valid;

alter table hr_files.file_objects
  add constraint ck_file_exactly_one_owner_v02
  check (
    (owner_type = 'capacity_request' and capacity_request_id is not null)
  ) not valid;

alter table hr_files.file_objects
  add constraint fk_file_capacity_request_owner_v02
  foreign key (tenant_id, capacity_request_id)
  references hr_workflow.capacity_change_requests(tenant_id, id)
  not valid;

-- File path must be unique across all versions.
create unique index if not exists uq_file_version_storage_object_v02
  on hr_files.file_versions(storage_bucket, storage_object_path);

-- Do not drop legacy owner_schema/table/id until all owners are migrated,
-- application reads/writes switched, and validation is complete.

-- ---------------------------------------------------------------------------
-- C. Capacity request dual status model
-- ---------------------------------------------------------------------------

alter table hr_workflow.capacity_change_requests
  add column if not exists approval_status text,
  add column if not exists execution_status text,
  add column if not exists current_revision_no integer not null default 1,
  add column if not exists last_approved_revision_no integer;

update hr_workflow.capacity_change_requests
set approval_status = case status
  when 'pending_approval' then 'pending_approval'
  when 'approved_awaiting_execution' then 'approved'
  when 'scheduled' then 'approved'
  when 'overdue' then 'approved'
  when 'awaiting_reapproval' then 'awaiting_reapproval'
  when 'rejected' then 'rejected'
  when 'cancelled' then 'rejected'
  when 'executed' then 'approved'
  else 'pending_approval'
end
where approval_status is null;

update hr_workflow.capacity_change_requests
set execution_status = case status
  when 'approved_awaiting_execution' then
    case when execution_mode = 'scheduled' then 'scheduled' else 'due' end
  when 'scheduled' then 'scheduled'
  when 'overdue' then 'overdue'
  when 'executed' then 'executed'
  when 'cancelled' then 'cancelled'
  when 'rejected' then 'blocked'
  when 'awaiting_reapproval' then 'blocked'
  else 'blocked'
end
where execution_status is null;

update hr_workflow.capacity_change_requests
set last_approved_revision_no = current_revision_no
where approval_status = 'approved'
  and last_approved_revision_no is null;

alter table hr_workflow.capacity_change_requests
  add constraint ck_capacity_approval_status_v02
  check (approval_status in (
    'pending_approval','approved','rejected','awaiting_reapproval'
  )) not valid;

alter table hr_workflow.capacity_change_requests
  add constraint ck_capacity_execution_status_v02
  check (execution_status in (
    'blocked','scheduled','due','overdue','executed','cancelled'
  )) not valid;

alter table hr_workflow.capacity_change_requests
  add constraint ck_capacity_approved_revision_v02
  check (
    approval_status <> 'approved'
    or last_approved_revision_no is not null
  ) not valid;

-- Open request uniqueness. Rows rejected/cancelled/executed are excluded.
create unique index if not exists uq_capacity_one_open_request_per_position_v02
  on hr_workflow.capacity_change_requests(tenant_id, position_id)
  where approval_status in (
    'pending_approval','approved','awaiting_reapproval'
  )
  and execution_status in ('blocked','scheduled','due','overdue');

-- Keep legacy status during dual-write transition. Remove only in a later
-- migration after all application code uses approval_status/execution_status.

-- ---------------------------------------------------------------------------
-- D. Append-only triggers for immutable records
-- ---------------------------------------------------------------------------

create or replace function hr_audit.reject_mutation_append_only()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'append-only record cannot be updated or deleted';
end;
$$;

-- Apply to immutable history tables. If operational correction is required,
-- insert a compensating event instead of updating the original row.
do $$
declare
  t record;
begin
  for t in
    select * from (values
      ('hr_audit','audit_events'),
      ('hr_audit','permission_change_history'),
      ('hr_workflow','decisions'),
      ('hr_workflow','capacity_request_revisions'),
      ('hr_workflow','capacity_request_notes'),
      ('hr_files','file_versions')
    ) as x(schema_name, table_name)
  loop
    execute format(
      'drop trigger if exists %I on %I.%I',
      'trg_' || t.table_name || '_append_only', t.schema_name, t.table_name
    );
    execute format(
      'create trigger %I before update or delete on %I.%I for each row execute function hr_audit.reject_mutation_append_only()',
      'trg_' || t.table_name || '_append_only', t.schema_name, t.table_name
    );
  end loop;
end $$;

commit;

-- POST-MIGRATION MANUAL VALIDATION:
-- 1. Validate all *_v02 foreign keys and CHECK constraints.
-- 2. Inspect orphan/duplicate records and the capacity partial unique index.
-- 3. Verify every file_objects row has exactly one recognized owner.
-- 4. Update API dual-write before relying on new capacity statuses.
-- 5. Add RLS policies only after permission resolver and tests are implemented.
-- 6. Run pgTAP plan and two-tenant integration suite.
