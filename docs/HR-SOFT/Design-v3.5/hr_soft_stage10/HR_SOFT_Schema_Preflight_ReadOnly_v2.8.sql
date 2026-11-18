-- HR-SOFT Stage 10 / read-only preflight checks
-- Run only in a disposable development database after applying draft schemas.
-- All statements are read-only diagnostics.

-- A. Count objects
select schemaname, count(*) as table_count
from pg_tables
where schemaname like 'hr_%'
group by schemaname
order by schemaname;

-- B. Find org unit parent company mismatch
select child.id, child.company_id, parent.company_id as parent_company_id
from hr_org.org_units child
join hr_org.org_units parent
  on parent.tenant_id = child.tenant_id
 and parent.id = child.parent_unit_id
where child.company_id <> parent.company_id;

-- C. Find position/company mismatch
select p.id, p.company_id, u.company_id as unit_company_id
from hr_org.positions p
join hr_org.org_units u
  on u.tenant_id = p.tenant_id and u.id = p.org_unit_id
where p.company_id <> u.company_id;

-- D. Find assignment company mismatch
select pa.id, pa.company_id, p.company_id as position_company_id,
       pr.company_id as personnel_company_id
from hr_org.position_assignments pa
join hr_org.positions p
  on p.tenant_id = pa.tenant_id and p.id = pa.position_id
join hr_core.personnel_records pr
  on pr.tenant_id = pa.tenant_id and pr.id = pa.personnel_record_id
where pa.company_id <> p.company_id
   or pa.company_id <> pr.company_id;

-- E. Find cross-company position relationships
select rel.id, fp.company_id as from_company, tp.company_id as to_company
from hr_org.position_relationships rel
join hr_org.positions fp
  on fp.tenant_id=rel.tenant_id and fp.id=rel.from_position_id
join hr_org.positions tp
  on tp.tenant_id=rel.tenant_id and tp.id=rel.to_position_id
where fp.company_id <> tp.company_id;

-- F. Find malformed scopes
select *
from hr_security.data_scopes
where not (
  (scope_type='tenant' and company_id is null and org_unit_id is null and personnel_record_id is null)
  or (scope_type='company' and company_id is not null and org_unit_id is null and personnel_record_id is null)
  or (scope_type='org_unit' and company_id is not null and org_unit_id is not null and personnel_record_id is null)
  or (scope_type='personnel' and company_id is not null and org_unit_id is null and personnel_record_id is not null)
);

-- G. Find duplicate file object paths
select storage_bucket, storage_object_path, count(*)
from hr_files.file_versions
group by 1,2
having count(*) > 1;

-- H. Find legacy polymorphic file owners that are not capacity requests
select owner_schema, owner_table, count(*)
from hr_files.file_objects
where not (owner_schema='hr_workflow' and owner_table='capacity_change_requests')
group by 1,2;

-- I. Find multiple open capacity requests after status backfill
select tenant_id, position_id, count(*)
from hr_workflow.capacity_change_requests
where approval_status in ('pending_approval','approved','awaiting_reapproval')
  and execution_status in ('blocked','scheduled','due','overdue')
group by 1,2
having count(*) > 1;
