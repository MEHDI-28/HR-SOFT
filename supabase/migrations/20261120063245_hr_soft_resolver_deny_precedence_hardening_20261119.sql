-- HR-SOFT: harden deny precedence and active-user context consistency.
-- Follow-up migration; do not edit already-applied historical migrations.
-- Deny rules are independent of operation allow flags. Allow rules remain operation-gated.
create or replace function hr_internal.evaluate_permission_context(
  p_permission_key text,
  p_operation text,
  p_tenant_id uuid,
  p_company_id uuid default null,
  p_org_unit_id uuid default null,
  p_personnel_record_id uuid default null,
  p_effective_at timestamptz default now()
)
returns table (
  allowed boolean,
  reason_code text,
  policy_version text,
  evaluated_at timestamptz,
  matched_allow_count integer,
  matched_deny_count integer
)
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_app_user_id uuid;
  v_user_tenant_id uuid;
  v_system_id uuid;
  v_permission_id uuid;
  v_eval_at timestamptz := pg_catalog.clock_timestamp();
  v_effective_at timestamptz := coalesce(p_effective_at, pg_catalog.clock_timestamp());
  v_membership_count integer := 0;
  v_rule_count integer := 0;
  v_temp_count integer := 0;
  v_group_allow integer := 0;
  v_group_deny integer := 0;
  v_temp_allow integer := 0;
  v_temp_deny integer := 0;
  v_allow integer := 0;
  v_deny integer := 0;
begin
  if auth.uid() is null then
    return query select false, 'AUTH_REQUIRED'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  select au.id, au.tenant_id
    into v_app_user_id, v_user_tenant_id
    from hr_security.app_users au
   where au.auth_user_id = auth.uid()
     and au.status = 'active'
     and au.archived_at is null
   limit 1;

  if v_app_user_id is null then
    return query select false, 'APP_USER_INACTIVE'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  if p_tenant_id is null or p_tenant_id is distinct from v_user_tenant_id then
    return query select false, 'TENANT_MISMATCH'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  if p_operation is null
     or p_operation not in ('view','add','edit','delete','download','view_sensitive','correct_history','approve','execute') then
    return query select false, 'INVALID_OPERATION'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  if p_company_id is not null and not exists (
    select 1 from hr_core.companies c
     where c.tenant_id = v_user_tenant_id
       and c.id = p_company_id
       and c.archived_at is null
       and c.valid_from <= v_effective_at::date
       and (c.valid_to is null or c.valid_to >= v_effective_at::date)
  ) then
    return query select false, 'RESOURCE_NOT_FOUND'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  if p_org_unit_id is not null and (
    p_company_id is null or not exists (
      select 1 from hr_org.org_units u
       where u.tenant_id = v_user_tenant_id
         and u.company_id = p_company_id
         and u.id = p_org_unit_id
         and u.valid_from <= v_effective_at::date
         and (u.valid_to is null or u.valid_to >= v_effective_at::date)
    )
  ) then
    return query select false, 'RESOURCE_NOT_FOUND'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  if p_personnel_record_id is not null and (
    p_company_id is null or not exists (
      select 1 from hr_core.personnel_records pr
       where pr.tenant_id = v_user_tenant_id
         and pr.company_id = p_company_id
         and pr.id = p_personnel_record_id
         and pr.valid_from <= v_effective_at::date
         and (pr.valid_to is null or pr.valid_to >= v_effective_at::date)
    )
  ) then
    return query select false, 'RESOURCE_NOT_FOUND'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  select s.id
    into v_system_id
    from hr_security.systems s
   where s.system_key = 'HR-SOFT'
     and s.is_active;

  if v_system_id is null then
    return query select false, 'SYSTEM_INACTIVE'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  select p.id
    into v_permission_id
    from hr_security.permissions p
   where p.system_id = v_system_id
     and p.permission_key = p_permission_key
     and p.is_active;

  if v_permission_id is null then
    return query select false, 'PERMISSION_NOT_GRANTED'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  select count(*)::integer
    into v_membership_count
    from hr_security.group_memberships gm
    join hr_security.user_groups ug
      on ug.tenant_id = gm.tenant_id
     and ug.id = gm.group_id
   where gm.tenant_id = v_user_tenant_id
     and gm.app_user_id = v_app_user_id
     and gm.is_active
     and gm.valid_from <= v_eval_at
     and (gm.valid_to is null or v_eval_at < gm.valid_to)
     and ug.system_id = v_system_id
     and ug.is_active
     and ug.archived_at is null;

  select count(*)::integer
    into v_rule_count
    from hr_security.group_memberships gm
    join hr_security.user_groups ug
      on ug.tenant_id = gm.tenant_id
     and ug.id = gm.group_id
    join hr_security.group_permission_rules r
      on r.tenant_id = gm.tenant_id
     and r.system_id = ug.system_id
     and r.group_id = gm.group_id
     and r.permission_id = v_permission_id
   where gm.tenant_id = v_user_tenant_id
     and gm.app_user_id = v_app_user_id
     and gm.is_active
     and gm.valid_from <= v_eval_at
     and (gm.valid_to is null or v_eval_at < gm.valid_to)
     and ug.system_id = v_system_id
     and ug.is_active
     and ug.archived_at is null
     and case p_operation
       when 'add' then r.can_add
       when 'edit' then r.can_edit
       when 'delete' then r.can_delete
       else true
     end;

  select count(*)::integer
    into v_group_allow
    from hr_security.group_memberships gm
    join hr_security.user_groups ug
      on ug.tenant_id = gm.tenant_id
     and ug.id = gm.group_id
    join hr_security.group_permission_rules r
      on r.tenant_id = gm.tenant_id
     and r.system_id = ug.system_id
     and r.group_id = gm.group_id
     and r.permission_id = v_permission_id
    join hr_security.group_scope_assignments gsa
      on gsa.tenant_id = gm.tenant_id
     and gsa.group_id = gm.group_id
   where gm.tenant_id = v_user_tenant_id
     and gm.app_user_id = v_app_user_id
     and gm.is_active
     and gm.valid_from <= v_eval_at
     and (gm.valid_to is null or v_eval_at < gm.valid_to)
     and ug.system_id = v_system_id
     and ug.is_active
     and ug.archived_at is null
     and gsa.valid_from <= v_eval_at
     and (gsa.valid_to is null or v_eval_at < gsa.valid_to)
     and r.effect = 'allow'
     and gsa.effect = 'allow'
     and case p_operation
       when 'add' then r.can_add
       when 'edit' then r.can_edit
       when 'delete' then r.can_delete
       else true
     end
     and hr_internal.scope_matches(
       gsa.scope_id, v_user_tenant_id, p_company_id,
       p_org_unit_id, p_personnel_record_id, v_effective_at
     );

  select count(*)::integer
    into v_group_deny
    from hr_security.group_memberships gm
    join hr_security.user_groups ug
      on ug.tenant_id = gm.tenant_id
     and ug.id = gm.group_id
    join hr_security.group_permission_rules r
      on r.tenant_id = gm.tenant_id
     and r.system_id = ug.system_id
     and r.group_id = gm.group_id
     and r.permission_id = v_permission_id
    join hr_security.group_scope_assignments gsa
      on gsa.tenant_id = gm.tenant_id
     and gsa.group_id = gm.group_id
   where gm.tenant_id = v_user_tenant_id
     and gm.app_user_id = v_app_user_id
     and gm.is_active
     and gm.valid_from <= v_eval_at
     and (gm.valid_to is null or v_eval_at < gm.valid_to)
     and ug.system_id = v_system_id
     and ug.is_active
     and ug.archived_at is null
     and gsa.valid_from <= v_eval_at
     and (gsa.valid_to is null or v_eval_at < gsa.valid_to)
     and (r.effect = 'deny' or gsa.effect = 'deny')
     and hr_internal.scope_matches(
       gsa.scope_id, v_user_tenant_id, p_company_id,
       p_org_unit_id, p_personnel_record_id, v_effective_at
     );

  select count(*)::integer
    into v_temp_allow
    from hr_security.temporary_access ta
   where ta.tenant_id = v_user_tenant_id
     and ta.app_user_id = v_app_user_id
     and ta.system_id = v_system_id
     and ta.permission_id = v_permission_id
     and ta.effect = 'allow'
     and ta.approved_by is not null
     and ta.approved_at is not null
     and ta.starts_at <= v_eval_at
     and v_eval_at < ta.ends_at
     and hr_internal.scope_matches(
       ta.scope_id, v_user_tenant_id, p_company_id,
       p_org_unit_id, p_personnel_record_id, v_effective_at
     );

  select count(*)::integer
    into v_temp_deny
    from hr_security.temporary_access ta
   where ta.tenant_id = v_user_tenant_id
     and ta.app_user_id = v_app_user_id
     and ta.system_id = v_system_id
     and ta.permission_id = v_permission_id
     and ta.effect = 'deny'
     and ta.starts_at <= v_eval_at
     and v_eval_at < ta.ends_at
     and ta.scope_id is not null
     and hr_internal.scope_matches(
       ta.scope_id, v_user_tenant_id, p_company_id,
       p_org_unit_id, p_personnel_record_id, v_effective_at
     );

  select count(*)::integer
    into v_temp_count
    from hr_security.temporary_access ta
   where ta.tenant_id = v_user_tenant_id
     and ta.app_user_id = v_app_user_id
     and ta.system_id = v_system_id
     and ta.permission_id = v_permission_id;

  v_allow := v_group_allow + v_temp_allow;
  v_deny := v_group_deny + v_temp_deny;

  if v_deny > 0 then
    return query select false, 'EXPLICIT_DENY'::text, '2.4.2'::text, v_eval_at, v_allow, v_deny;
    return;
  end if;

  if v_allow > 0 then
    return query select true,
      case when v_group_allow > 0 then 'ALLOWED_BY_GROUP' else 'ALLOWED_BY_TEMPORARY_ACCESS' end,
      '2.4.2'::text, v_eval_at, v_allow, v_deny;
    return;
  end if;

  if v_membership_count = 0 and v_temp_count = 0 then
    return query select false, 'NO_ACTIVE_MEMBERSHIP'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  if v_temp_count > 0 then
    return query select false, 'TEMPORARY_ACCESS_NOT_ACTIVE_OR_SCOPE_MISMATCH'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  if v_rule_count = 0 then
    return query select false, 'PERMISSION_NOT_GRANTED'::text, '2.4.2'::text, v_eval_at, 0, 0;
    return;
  end if;

  return query select false, 'SCOPE_NOT_GRANTED'::text, '2.4.2'::text, v_eval_at, 0, 0;
end;
$$;

comment on function hr_internal.evaluate_permission_context(text,text,uuid,uuid,uuid,uuid,timestamptz) is
  'Internal HR-SOFT permission resolver v2.4.2; deny-overrides-allow; validates tenant/resource context and explicit scope. Deny is independent of operation allow flags.';

create or replace function hr_security.current_app_user_id()
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
    and au.archived_at is null
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
  from hr_security.app_users au
  where au.auth_user_id = auth.uid()
    and au.status = 'active'
    and au.archived_at is null
  limit 1
$$;


create or replace function public.hr_session_status()
returns table (is_authenticated boolean, is_provisioned boolean)
language sql
stable
security invoker
set search_path = ''
as $$
  select auth.uid() is not null,
         exists (
           select 1
           from hr_security.app_users au
           where au.auth_user_id = auth.uid()
             and au.status = 'active'
             and au.archived_at is null
         );
$$;


-- Complete the two Stage 18 temporary-access integrity checks that are
-- absent from the currently deployed table definition. The existing
-- same-tenant approver FK and approved_at column are already present.
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

-- Read-only preflight found zero temporary_access rows in the active project.
-- Validation is retained here so the migration cannot leave unvalidated checks.
alter table hr_security.temporary_access
  validate constraint ck_temporary_access_approval_pair_v18;

alter table hr_security.temporary_access
  validate constraint ck_temporary_access_global_scope_approval_v18;
