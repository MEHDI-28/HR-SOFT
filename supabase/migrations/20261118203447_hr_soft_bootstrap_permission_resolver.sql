-- HR-SOFT Org-Ch: one-time first-admin bootstrap and permission resolver.
-- No user, tenant, company or permission grants are created until the authenticated owner redeems the one-time token.
-- The initial tenant_owner group deliberately excludes sensitive-data, permission-edit and temporary-access grants.

alter table hr_security.group_permission_rules
  add constraint fk_group_permission_rules_changed_by_v1
  foreign key (tenant_id, changed_by)
  references hr_security.app_users(tenant_id, id)
  not valid;
create index if not exists ix_group_permission_rules_changed_by_v1
  on hr_security.group_permission_rules(tenant_id, changed_by);
alter table hr_security.group_permission_rules
  validate constraint fk_group_permission_rules_changed_by_v1;

alter table hr_org.position_profiles
  add column if not exists custom_attributes jsonb not null default '{}'::jsonb;
alter table hr_org.position_profiles
  add constraint ck_position_profiles_custom_attributes_object_v1
  check (jsonb_typeof(custom_attributes) = 'object') not valid;
alter table hr_org.position_profiles
  validate constraint ck_position_profiles_custom_attributes_object_v1;

create schema if not exists hr_internal;
revoke all on schema hr_internal from public, anon, authenticated;

create table hr_security.bootstrap_invites (
  token_hash bytea primary key,
  expires_at timestamptz not null,
  redeemed_at timestamptz,
  redeemed_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  check (
    (redeemed_at is null and redeemed_by is null)
    or (redeemed_at is not null and redeemed_by is not null)
  )
);
alter table hr_security.bootstrap_invites enable row level security;
alter table hr_security.bootstrap_invites force row level security;
revoke all on table hr_security.bootstrap_invites from public, anon, authenticated;
create index ix_bootstrap_invites_redeemed_by on hr_security.bootstrap_invites(redeemed_by);

-- Store only the SHA-256 hash. The one-time plaintext token is delivered separately to the project owner.
insert into hr_security.bootstrap_invites(token_hash, expires_at)
values (
  decode('856a0c6582177cb16158e6bfd1db77d18d046c42bac4005bb9965408a49af0d1', 'hex'),
  now() + interval '14 days'
);

create or replace function hr_internal.scope_matches(
  p_scope_id uuid,
  p_tenant_id uuid,
  p_company_id uuid,
  p_org_unit_id uuid,
  p_personnel_record_id uuid,
  p_effective_at timestamptz
)
returns boolean
language plpgsql
stable
set search_path = ''
as $$
declare
  v_scope hr_security.data_scopes%rowtype;
  v_effective_date date := coalesce(p_effective_at, pg_catalog.now())::date;
begin
  select *
    into v_scope
    from hr_security.data_scopes s
   where s.tenant_id = p_tenant_id
     and s.id = p_scope_id;

  if not found then
    return false;
  end if;

  case v_scope.scope_type
    when 'tenant' then
      return true;

    when 'company' then
      return p_company_id is not null
         and v_scope.company_id = p_company_id;

    when 'org_unit' then
      if p_company_id is null
         or p_org_unit_id is null
         or v_scope.company_id is distinct from p_company_id then
        return false;
      end if;

      if v_scope.org_unit_id = p_org_unit_id then
        return true;
      end if;

      -- Historical descendant access is fail-closed until temporal hierarchy history exists.
      if not v_scope.include_descendants or v_effective_date <> current_date then
        return false;
      end if;

      return exists (
        with recursive descendants(id, path) as (
          select u.id, array[u.id]::uuid[]
            from hr_org.org_units u
           where u.tenant_id = p_tenant_id
             and u.company_id = v_scope.company_id
             and u.id = v_scope.org_unit_id
             and u.valid_from <= v_effective_date
             and (u.valid_to is null or u.valid_to >= v_effective_date)

          union all

          select child.id, d.path || child.id
            from hr_org.org_units child
            join descendants d on child.parent_unit_id = d.id
           where child.tenant_id = p_tenant_id
             and child.company_id = v_scope.company_id
             and child.valid_from <= v_effective_date
             and (child.valid_to is null or child.valid_to >= v_effective_date)
             and not child.id = any(d.path)
        )
        select 1 from descendants d where d.id = p_org_unit_id
      );

    when 'personnel' then
      return p_personnel_record_id is not null
         and v_scope.personnel_record_id = p_personnel_record_id;

    else
      return false;
  end case;
end;
$$;

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
    return query select false, 'AUTH_REQUIRED'::text, '2.4.1'::text, v_eval_at, 0, 0;
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
    return query select false, 'APP_USER_INACTIVE'::text, '2.4.1'::text, v_eval_at, 0, 0;
    return;
  end if;

  if p_tenant_id is null or p_tenant_id is distinct from v_user_tenant_id then
    return query select false, 'TENANT_MISMATCH'::text, '2.4.1'::text, v_eval_at, 0, 0;
    return;
  end if;

  if p_operation is null
     or p_operation not in ('view','add','edit','delete','download','view_sensitive','correct_history','approve','execute') then
    return query select false, 'INVALID_OPERATION'::text, '2.4.1'::text, v_eval_at, 0, 0;
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
    return query select false, 'RESOURCE_NOT_FOUND'::text, '2.4.1'::text, v_eval_at, 0, 0;
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
    return query select false, 'RESOURCE_NOT_FOUND'::text, '2.4.1'::text, v_eval_at, 0, 0;
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
    return query select false, 'RESOURCE_NOT_FOUND'::text, '2.4.1'::text, v_eval_at, 0, 0;
    return;
  end if;

  select s.id
    into v_system_id
    from hr_security.systems s
   where s.system_key = 'HR-SOFT'
     and s.is_active;

  if v_system_id is null then
    return query select false, 'SYSTEM_INACTIVE'::text, '2.4.1'::text, v_eval_at, 0, 0;
    return;
  end if;

  select p.id
    into v_permission_id
    from hr_security.permissions p
   where p.system_id = v_system_id
     and p.permission_key = p_permission_key
     and p.is_active;

  if v_permission_id is null then
    return query select false, 'PERMISSION_NOT_GRANTED'::text, '2.4.1'::text, v_eval_at, 0, 0;
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
    return query select false, 'EXPLICIT_DENY'::text, '2.4.1'::text, v_eval_at, v_allow, v_deny;
    return;
  end if;

  if v_allow > 0 then
    return query select true,
      case when v_group_allow > 0 then 'ALLOWED_BY_GROUP' else 'ALLOWED_BY_TEMPORARY_ACCESS' end,
      '2.4.1'::text, v_eval_at, v_allow, v_deny;
    return;
  end if;

  if v_membership_count = 0 and v_temp_count = 0 then
    return query select false, 'NO_ACTIVE_MEMBERSHIP'::text, '2.4.1'::text, v_eval_at, 0, 0;
    return;
  end if;

  if v_temp_count > 0 then
    return query select false, 'TEMPORARY_ACCESS_NOT_ACTIVE_OR_SCOPE_MISMATCH'::text, '2.4.1'::text, v_eval_at, 0, 0;
    return;
  end if;

  if v_rule_count = 0 then
    return query select false, 'PERMISSION_NOT_GRANTED'::text, '2.4.1'::text, v_eval_at, 0, 0;
    return;
  end if;

  return query select false, 'SCOPE_NOT_GRANTED'::text, '2.4.1'::text, v_eval_at, 0, 0;
end;
$$;

revoke all on function hr_internal.scope_matches(uuid,uuid,uuid,uuid,uuid,timestamptz)
  from public, anon, authenticated;
revoke all on function hr_internal.evaluate_permission_context(text,text,uuid,uuid,uuid,uuid,timestamptz)
  from public, anon, authenticated;

create or replace function public.hr_bootstrap_first_admin(
  p_token text,
  p_tenant_key text,
  p_tenant_name text,
  p_company_code text,
  p_company_name text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_auth_user_id uuid := auth.uid();
  v_token_hash bytea;
  v_tenant_id uuid;
  v_company_id uuid;
  v_app_user_id uuid;
  v_system_id uuid;
  v_group_id uuid;
  v_scope_id uuid;
  v_permission_count integer := 0;
  v_assigned_permission_count integer := 0;
  v_permission_keys text[] := array[
    'system.dashboard.view',
    'system.settings.view',
    'system.settings.edit',
    'security.users.view',
    'security.users.add',
    'security.users.edit',
    'security.users.block',
    'security.groups.view',
    'security.groups.add',
    'security.groups.edit',
    'security.groups.archive',
    'security.memberships.view',
    'security.memberships.add',
    'security.memberships.edit',
    'security.permissions.view',
    'security.permissions.edit',
    'security.permission_history.view',
    'security.permission_history.export',
    'security.temporary_access.add',
    'security.temporary_access.revoke',
    'org.company.view',
    'org.company.add',
    'org.company.edit',
    'org.unit.view',
    'org.unit.add',
    'org.unit.edit',
    'org.unit.archive',
    'org.position.view',
    'org.position.add',
    'org.position.edit',
    'org.position.archive',
    'org.relationship.view',
    'org.relationship.add',
    'org.relationship.edit',
    'org.chart.view',
    'org.chart.export',
    'personnel.view',
    'personnel.add',
    'personnel.edit',
    'personnel.archive',
    'personnel.assignment.view',
    'personnel.assignment.add',
    'personnel.assignment.edit',
    'personnel.assignment.history.view',
    'personnel.history.correct',
    'sensitive.identity.view',
    'sensitive.identity.edit',
    'sensitive.bank.view',
    'sensitive.bank.add',
    'sensitive.bank.edit',
    'sensitive.documents.view',
    'sensitive.documents.upload',
    'sensitive.documents.replace',
    'sensitive.documents.download',
    'workflow.inbox.view',
    'workflow.request.submit',
    'workflow.request.view',
    'workflow.request.approve',
    'workflow.request.reject',
    'capacity.request.add',
    'capacity.request.view',
    'capacity.request.edit',
    'capacity.request.approve',
    'capacity.request.reject',
    'capacity.request.execute',
    'capacity.request.cancel',
    'capacity.request.notes.view',
    'capacity.request.notes.add',
    'capacity.request.files.view',
    'capacity.request.files.manage',
    'capacity.request.export.create',
    'capacity.request.export.download',
    'notification.view',
    'notification.preferences.edit',
    'report.personnel.view',
    'report.personnel.export',
    'report.organization.view',
    'report.organization.export',
    'report.security.view',
    'report.security.export'
  ];
  v_tenant_key text := pg_catalog.lower(pg_catalog.btrim(p_tenant_key));
  v_company_code text := pg_catalog.upper(pg_catalog.btrim(p_company_code));
begin
  if v_auth_user_id is null then
    raise exception 'Authentication required' using errcode = '42501';
  end if;

  if p_token is null or pg_catalog.length(p_token) < 32 then
    raise exception 'Invalid bootstrap token' using errcode = '42501';
  end if;

  if p_tenant_key is null
     or p_company_code is null
     or p_tenant_name is null
     or p_company_name is null
     or v_tenant_key !~ '^[a-z0-9][a-z0-9_-]{2,62}$'
     or v_company_code !~ '^[A-Z0-9][A-Z0-9_-]{1,31}$'
     or pg_catalog.length(pg_catalog.btrim(p_tenant_name)) not between 2 and 160
     or pg_catalog.length(pg_catalog.btrim(p_company_name)) not between 2 and 160 then
    raise exception 'Invalid tenant or company details' using errcode = '22023';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('hr_soft_first_admin_bootstrap', 0)
  );

  select i.token_hash
    into v_token_hash
    from hr_security.bootstrap_invites i
   where i.token_hash = extensions.digest(pg_catalog.convert_to(p_token, 'UTF8'), 'sha256')
     and i.redeemed_at is null
     and i.expires_at > pg_catalog.clock_timestamp()
   for update;

  if v_token_hash is null then
    raise exception 'Bootstrap token is invalid, expired or already used' using errcode = '42501';
  end if;

  if exists (select 1 from hr_core.tenants)
     or exists (select 1 from hr_security.app_users) then
    raise exception 'First-admin bootstrap has already been completed' using errcode = '42501';
  end if;

  insert into hr_security.systems(system_key, title, is_active)
  values ('HR-SOFT', 'HR-SOFT', true)
  on conflict (system_key) do update
    set title = excluded.title,
        is_active = true
  returning id into v_system_id;

  insert into hr_core.tenants(tenant_key, display_name, status)
  values (v_tenant_key, pg_catalog.btrim(p_tenant_name), 'active')
  returning id into v_tenant_id;

  insert into hr_core.companies(tenant_id, company_code, legal_name, display_name, status)
  values (v_tenant_id, v_company_code, pg_catalog.btrim(p_company_name),
          pg_catalog.btrim(p_company_name), 'active')
  returning id into v_company_id;

  insert into hr_security.app_users(tenant_id, auth_user_id, status, force_password_change, auth_mode)
  values (v_tenant_id, v_auth_user_id, 'active', false, 'local')
  returning id into v_app_user_id;

  update hr_core.tenants set created_by = v_app_user_id where id = v_tenant_id;
  update hr_core.companies set created_by = v_app_user_id, updated_by = v_app_user_id where id = v_company_id;

  insert into hr_security.permissions(system_id, permission_key, title, description, is_active)
  select v_system_id, k.permission_key, k.permission_key,
         'HR-SOFT permission catalogue v0.1', true
    from pg_catalog.unnest(v_permission_keys) as k(permission_key)
  on conflict (system_id, permission_key) do update
    set title = excluded.title,
        description = excluded.description,
        is_active = true;

  select count(*)::integer into v_permission_count
    from hr_security.permissions p
   where p.system_id = v_system_id
     and p.is_active;

  insert into hr_security.user_groups(tenant_id, system_id, group_key, title, is_active, created_by)
  values (v_tenant_id, v_system_id, 'tenant_owner', 'مدیر کل سازمان', true, v_app_user_id)
  returning id into v_group_id;

  insert into hr_security.data_scopes(tenant_id, scope_type, created_by)
  values (v_tenant_id, 'tenant', v_app_user_id)
  returning id into v_scope_id;

  insert into hr_security.group_scope_assignments(
    tenant_id, group_id, scope_id, effect, valid_from, created_by
  )
  values (v_tenant_id, v_group_id, v_scope_id, 'allow', pg_catalog.now(), v_app_user_id);

  insert into hr_security.group_memberships(
    tenant_id, group_id, app_user_id, is_active, valid_from, created_by
  )
  values (v_tenant_id, v_group_id, v_app_user_id, true, pg_catalog.now(), v_app_user_id);

  insert into hr_security.user_default_groups(
    tenant_id, app_user_id, system_id, group_id, set_at, set_by
  )
  values (v_tenant_id, v_app_user_id, v_system_id, v_group_id, pg_catalog.now(), v_app_user_id);

  insert into hr_security.group_permission_rules(
    tenant_id, system_id, group_id, permission_id,
    can_add, can_edit, can_delete, effect, changed_by
  )
  select v_tenant_id, v_system_id, v_group_id, p.id,
         true, true, true, 'allow', v_app_user_id
    from hr_security.permissions p
   where p.system_id = v_system_id
     and p.is_active
     and p.permission_key not like 'sensitive.%'
     and p.permission_key not in (
       'security.permissions.edit',
       'security.temporary_access.add',
       'security.temporary_access.revoke'
     )
  on conflict (tenant_id, group_id, permission_id) do nothing;

  get diagnostics v_assigned_permission_count = row_count;

  insert into hr_audit.audit_events(
    tenant_id, actor_app_user_id, event_type, entity_schema, entity_table,
    entity_id, occurred_at, effective_at, reason, after_state
  )
  values (
    v_tenant_id, v_app_user_id, 'hr_soft.bootstrap.completed',
    'hr_core', 'tenants', v_tenant_id, pg_catalog.now(), pg_catalog.now(),
    'One-time first administrator bootstrap',
    pg_catalog.jsonb_build_object(
      'tenant_id', v_tenant_id,
      'company_id', v_company_id,
      'group_id', v_group_id,
      'permission_catalogue_count', v_permission_count,
      'assigned_permission_count', v_assigned_permission_count,
      'sensitive_permissions_assigned', false
    )
  );

  update hr_security.bootstrap_invites
     set redeemed_at = pg_catalog.now(),
         redeemed_by = v_auth_user_id
   where token_hash = v_token_hash;

  return pg_catalog.jsonb_build_object(
    'created', true,
    'tenant_id', v_tenant_id,
    'company_id', v_company_id,
    'app_user_id', v_app_user_id,
    'permission_catalogue_count', v_permission_count,
    'assigned_permission_count', v_assigned_permission_count,
    'sensitive_permissions_assigned', false
  );
end;
$$;

revoke all on function public.hr_bootstrap_first_admin(text,text,text,text,text)
  from public, anon;
grant execute on function public.hr_bootstrap_first_admin(text,text,text,text,text)
  to authenticated;

comment on function public.hr_bootstrap_first_admin(text,text,text,text,text) is
  'One-time token-protected first tenant owner bootstrap. Does not grant sensitive-data, permission-edit or temporary-access permissions.';

comment on function hr_internal.evaluate_permission_context(text,text,uuid,uuid,uuid,uuid,timestamptz) is
  'Internal HR-SOFT permission resolver v2.4.1; deny-overrides-allow; validates tenant/resource context and explicit scope.';

notify pgrst, 'reload schema';
