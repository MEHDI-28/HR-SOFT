$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$migrationPath = Join-Path $repoRoot 'supabase\migrations\20261119090000_hr_soft_resolver_deny_precedence_hardening.sql'
if (-not (Test-Path -LiteralPath $migrationPath)) {
    throw "Migration not found: $migrationPath"
}

# Optional image override enables the same disposable suite on another PostgreSQL major version.
$postgresImage = if ([string]::IsNullOrWhiteSpace($env:HR_SOFT_POSTGRES_IMAGE)) {
    'postgres:16-alpine'
} else {
    $env:HR_SOFT_POSTGRES_IMAGE.Trim()
}

$containerName = 'hr-soft-migration-smoke-' + (Get-Date -Format 'yyyyMMddHHmmss')
$bootstrapPath = Join-Path $env:TEMP ($containerName + '-bootstrap.sql')
$smokePath = Join-Path $env:TEMP ($containerName + '-smoke.sql')
$utf8NoBom = New-Object System.Text.UTF8Encoding($false)

$bootstrapSql = @'
create role anon nologin;
create role authenticated nologin;
create schema auth;
create schema hr_security;
create schema hr_internal;
create schema hr_core;
create schema hr_org;

create table hr_security.app_users (
  id uuid, tenant_id uuid, auth_user_id uuid, status text, archived_at timestamptz
);
create table hr_security.data_scopes (
  id uuid, tenant_id uuid, scope_type text, company_id uuid,
  org_unit_id uuid, personnel_record_id uuid, include_descendants boolean
);
create table hr_security.temporary_access (
  tenant_id uuid, app_user_id uuid, system_id uuid, permission_id uuid,
  scope_id uuid, effect text, starts_at timestamptz, ends_at timestamptz,
  approved_by uuid, approved_at timestamptz,
  constraint temporary_access_check1
    check (effect <> 'allow' or (scope_id is not null and approved_by is not null and approved_at is not null))
);
create table hr_security.group_memberships (
  tenant_id uuid, app_user_id uuid, group_id uuid, is_active boolean,
  valid_from timestamptz, valid_to timestamptz
);
create table hr_security.user_groups (
  tenant_id uuid, id uuid, system_id uuid, is_active boolean, archived_at timestamptz
);
create table hr_security.group_permission_rules (
  tenant_id uuid, system_id uuid, group_id uuid, permission_id uuid,
  can_add boolean, can_edit boolean, can_delete boolean, effect text
);
create table hr_security.group_scope_assignments (
  tenant_id uuid, group_id uuid, scope_id uuid, effect text,
  valid_from timestamptz, valid_to timestamptz
);
create table hr_security.systems (id uuid, system_key text, is_active boolean);
create table hr_security.permissions (
  id uuid, system_id uuid, permission_key text, is_active boolean
);
create table hr_core.companies (
  id uuid, tenant_id uuid, archived_at timestamptz, valid_from date, valid_to date
);
create table hr_core.personnel_records (
  id uuid, tenant_id uuid, company_id uuid, valid_from date, valid_to date
);
create table hr_org.org_units (
  id uuid, tenant_id uuid, company_id uuid, parent_unit_id uuid,
  valid_from date, valid_to date
);

create function auth.uid() returns uuid
language sql stable as $$ select null::uuid $$;

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
'@

$smokeSql = @'
begin;

do $auth_test$
declare
  v_authenticated boolean;
  v_provisioned boolean;
  v_reason text;
  v_app_user_id uuid;
  v_tenant_id uuid;
begin
  select is_authenticated, is_provisioned
    into v_authenticated, v_provisioned
    from public.hr_session_status();
  if v_authenticated is distinct from false or v_provisioned is distinct from false then
    raise exception 'Unauthenticated session-status check failed.';
  end if;

  select reason_code into v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','view',null);
  if v_reason <> 'AUTH_REQUIRED' then
    raise exception 'Expected AUTH_REQUIRED, got %', v_reason;
  end if;

  select hr_security.current_app_user_id(), hr_security.current_tenant_id()
    into v_app_user_id, v_tenant_id;
  if v_app_user_id is not null or v_tenant_id is not null then
    raise exception 'Unauthenticated identity helpers must return NULL.';
  end if;

  raise notice 'PASS: unauthenticated session, resolver, and identity helpers fail closed.';
end
$auth_test$;

-- Isolated unit simulation: an Auth identity maps to an app_user that is
-- still marked active but has been archived. This is not a real JWT test.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select '00000000-0000-0000-0000-000000000301'::uuid
$$;

insert into hr_security.app_users(id, tenant_id, auth_user_id, status, archived_at)
values (
  '00000000-0000-0000-0000-000000000101',
  '00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000301',
  'active',
  now()
);

do $archived_test$
declare
  v_authenticated boolean;
  v_provisioned boolean;
  v_reason text;
  v_app_user_id uuid;
  v_tenant_id uuid;
begin
  select is_authenticated, is_provisioned
    into v_authenticated, v_provisioned
    from public.hr_session_status();
  if v_authenticated is distinct from true or v_provisioned is distinct from false then
    raise exception 'Archived account must not be provisioned.';
  end if;

  select reason_code into v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'view', '00000000-0000-0000-0000-000000000201'
  );
  if v_reason <> 'APP_USER_INACTIVE' then
    raise exception 'Expected APP_USER_INACTIVE for archived account, got %', v_reason;
  end if;

  select hr_security.current_app_user_id(), hr_security.current_tenant_id()
    into v_app_user_id, v_tenant_id;
  if v_app_user_id is not null or v_tenant_id is not null then
    raise exception 'Archived account identity helpers must return NULL.';
  end if;

  raise notice 'PASS: archived-but-active app_user is not provisioned or resolved.';
end
$archived_test$;

-- Isolated resolver logic unit test. auth.uid() is stubbed in this disposable
-- database; scope_matches() is copied from the deployed source migration and
-- exercised with fixture tables. This is not a real JWT or RLS boundary test.
create or replace function auth.uid() returns uuid
language sql stable as $$
  select '00000000-0000-0000-0000-000000000302'::uuid
$$;

insert into hr_security.data_scopes(id, tenant_id, scope_type)
values (
  '00000000-0000-0000-0000-000000000602',
  '00000000-0000-0000-0000-000000000201',
  'tenant'
);

insert into hr_core.companies(id, tenant_id, archived_at, valid_from, valid_to)
values
  ('00000000-0000-0000-0000-000000000701','00000000-0000-0000-0000-000000000201',null,current_date - 30,null),
  ('00000000-0000-0000-0000-000000000702','00000000-0000-0000-0000-000000000201',null,current_date - 30,null);

insert into hr_security.data_scopes(id, tenant_id, scope_type, company_id)
values (
  '00000000-0000-0000-0000-000000000603',
  '00000000-0000-0000-0000-000000000201',
  'company',
  '00000000-0000-0000-0000-000000000701'
);

insert into hr_org.org_units(id, tenant_id, company_id, parent_unit_id, valid_from, valid_to)
values
  ('00000000-0000-0000-0000-000000000703','00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000701',null,current_date - 30,null),
  ('00000000-0000-0000-0000-000000000704','00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000701','00000000-0000-0000-0000-000000000703',current_date - 30,null);

insert into hr_security.data_scopes(
  id, tenant_id, scope_type, company_id, org_unit_id, include_descendants
)
values (
  '00000000-0000-0000-0000-000000000604',
  '00000000-0000-0000-0000-000000000201',
  'org_unit',
  '00000000-0000-0000-0000-000000000701',
  '00000000-0000-0000-0000-000000000703',
  true
);

insert into hr_security.app_users(id, tenant_id, auth_user_id, status, archived_at)
values (
  '00000000-0000-0000-0000-000000000102',
  '00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000302',
  'active',
  null
);

insert into hr_security.systems(id, system_key, is_active)
values (
  '00000000-0000-0000-0000-000000000402',
  'HR-SOFT',
  true
);

insert into hr_security.permissions(id, system_id, permission_key, is_active)
values
  ('00000000-0000-0000-0000-000000000502','00000000-0000-0000-0000-000000000402','org.chart.view',true),
  ('00000000-0000-0000-0000-000000000503','00000000-0000-0000-0000-000000000402','personnel.view',true),
  ('00000000-0000-0000-0000-000000000504','00000000-0000-0000-0000-000000000402','sensitive.identity.view',true),
  ('00000000-0000-0000-0000-000000000505','00000000-0000-0000-0000-000000000402','sensitive.bank.view',true),
  ('00000000-0000-0000-0000-000000000506','00000000-0000-0000-0000-000000000402','sensitive.documents.view',true),
  ('00000000-0000-0000-0000-000000000507','00000000-0000-0000-0000-000000000402','sensitive.documents.download',true);

insert into hr_security.user_groups(tenant_id, id, system_id, is_active, archived_at)
values
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000402',true,null),
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000402',true,null);

insert into hr_security.group_memberships(
  tenant_id, app_user_id, group_id, is_active, valid_from, valid_to
)
values
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000202',true,now() - interval '1 day',null),
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000102','00000000-0000-0000-0000-000000000203',true,now() - interval '1 day',null);

insert into hr_security.group_permission_rules(
  tenant_id, system_id, group_id, permission_id,
  can_add, can_edit, can_delete, effect
)
values
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000502',true,true,true,'allow'),
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000502',false,false,false,'deny');

insert into hr_security.group_permission_rules(
  tenant_id, system_id, group_id, permission_id,
  can_add, can_edit, can_delete, effect
)
values
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000503',true,true,true,'allow'),
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000402','00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000506',true,true,true,'allow');

insert into hr_security.group_scope_assignments(
  tenant_id, group_id, scope_id, effect, valid_from, valid_to
)
values
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000202','00000000-0000-0000-0000-000000000602','allow',now() - interval '1 day',null),
  ('00000000-0000-0000-0000-000000000201','00000000-0000-0000-0000-000000000203','00000000-0000-0000-0000-000000000602','allow',now() - interval '1 day',null);

do $resolver_test$
declare
  v_allowed boolean;
  v_reason text;
begin
  -- ACL-128: the caller cannot substitute another tenant context.
  select reason_code into v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000299'
  );
  if v_reason <> 'TENANT_MISMATCH' then
    raise exception 'ACL-128 failed: expected TENANT_MISMATCH, got %', v_reason;
  end if;
  raise notice 'PASS: ACL-128 tenant context mismatch is rejected before scope evaluation.';

  -- ACL-101 + ACL-118: group A allow and group B deny; deny flags are all false.
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','add','00000000-0000-0000-0000-000000000201');
  if v_allowed is distinct from false or v_reason <> 'EXPLICIT_DENY' then
    raise exception 'ACL-101/118 failed: expected EXPLICIT_DENY, got allowed=%, reason=%', v_allowed, v_reason;
  end if;
  raise notice 'PASS: ACL-101/118 multi-group deny overrides allow with all deny flags false.';

  -- ACL-102: inactive group B is ignored; group A allow remains.
  update hr_security.user_groups set is_active=false where id='00000000-0000-0000-0000-000000000203';
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','add','00000000-0000-0000-0000-000000000201');
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'ACL-102 failed: inactive group deny was not ignored.';
  end if;
  raise notice 'PASS: ACL-102 inactive group deny is ignored.';

  -- ACL-103: expired membership B is ignored.
  update hr_security.user_groups set is_active=true where id='00000000-0000-0000-0000-000000000203';
  update hr_security.group_memberships set valid_to=now() - interval '1 second' where group_id='00000000-0000-0000-0000-000000000203';
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','add','00000000-0000-0000-0000-000000000201');
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'ACL-103 failed: expired membership deny was not ignored.';
  end if;
  raise notice 'PASS: ACL-103 expired membership is ignored.';

  -- ACL-104: a group from another system cannot contribute a deny.
  update hr_security.group_memberships
     set valid_to=null
   where group_id='00000000-0000-0000-0000-000000000203';
  update hr_security.user_groups
     set system_id='00000000-0000-0000-0000-000000000499'
   where id='00000000-0000-0000-0000-000000000203';
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','add','00000000-0000-0000-0000-000000000201');
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'ACL-104 failed: cross-system group affected authorization.';
  end if;
  raise notice 'PASS: ACL-104 cross-system group is ignored.';
  update hr_security.user_groups
     set system_id='00000000-0000-0000-0000-000000000402'
   where id='00000000-0000-0000-0000-000000000203';

  -- ACL-105: an allow rule without an active matching scope does not grant.
  update hr_security.user_groups set is_active=false where id='00000000-0000-0000-0000-000000000203';
  update hr_security.group_scope_assignments
     set valid_to=now() - interval '1 second'
   where group_id='00000000-0000-0000-0000-000000000202';
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','add','00000000-0000-0000-0000-000000000201');
  if v_allowed is distinct from false or v_reason <> 'SCOPE_NOT_GRANTED' then
    raise exception 'ACL-105 failed: allow without matching scope was accepted.';
  end if;
  raise notice 'PASS: ACL-105 allow without matching scope is rejected.';
  update hr_security.group_scope_assignments
     set valid_to=null
   where group_id='00000000-0000-0000-0000-000000000202';

  -- ACL-106: scope deny in group B overrides scope allow in group A.
  update hr_security.user_groups set is_active=true where id='00000000-0000-0000-0000-000000000203';
  update hr_security.group_memberships set valid_to=null where group_id='00000000-0000-0000-0000-000000000203';
  update hr_security.group_permission_rules set effect='allow', can_add=true where group_id='00000000-0000-0000-0000-000000000203';
  update hr_security.group_scope_assignments set effect='deny' where group_id='00000000-0000-0000-0000-000000000203';
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','add','00000000-0000-0000-0000-000000000201');
  if v_allowed is distinct from false or v_reason <> 'EXPLICIT_DENY' then
    raise exception 'ACL-106 failed: expected scope deny to override allow.';
  end if;
  raise notice 'PASS: ACL-106 cross-group scope deny overrides allow.';

  -- ACL-121: scope deny still applies when the operation flag is false.
  update hr_security.group_permission_rules set can_add=false where group_id='00000000-0000-0000-0000-000000000203';
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','add','00000000-0000-0000-0000-000000000201');
  if v_allowed is distinct from false or v_reason <> 'EXPLICIT_DENY' then
    raise exception 'ACL-121 failed: scope deny was gated by can_add.';
  end if;
  raise notice 'PASS: ACL-121 scope deny is independent of can_add.';

  -- ACL-124: allow flags remain operation-specific.
  update hr_security.user_groups set is_active=false where id='00000000-0000-0000-0000-000000000203';
  update hr_security.group_scope_assignments set effect='allow' where group_id='00000000-0000-0000-0000-000000000203';
  update hr_security.group_permission_rules set can_add=false where group_id='00000000-0000-0000-0000-000000000202';
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','add','00000000-0000-0000-0000-000000000201');
  if v_allowed is distinct from false or v_reason <> 'PERMISSION_NOT_GRANTED' then
    raise exception 'ACL-124 failed: disabled allow operation flag unexpectedly granted access.';
  end if;
  raise notice 'PASS: ACL-124 disabled allow operation flag remains enforced.';

  update hr_security.group_permission_rules set can_add=true where group_id='00000000-0000-0000-0000-000000000202';
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context('org.chart.view','add','00000000-0000-0000-0000-000000000201');
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'Valid allow failed: expected ALLOWED_BY_GROUP, got allowed=%, reason=%', v_allowed, v_reason;
  end if;
  raise notice 'PASS: valid allow with enabled operation flag succeeds.';
  raise notice 'PASS: ACL-114 permission change is reflected on the next evaluation.';
end
$resolver_test$;

do $scope_test$
declare
  v_allowed boolean;
  v_reason text;
begin
  -- ACL-107: company scope must not match a different company in the same tenant.
  update hr_security.group_scope_assignments
     set scope_id='00000000-0000-0000-0000-000000000603'
   where group_id='00000000-0000-0000-0000-000000000202';

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000702'
  );
  if v_allowed is distinct from false or v_reason <> 'SCOPE_NOT_GRANTED' then
    raise exception 'ACL-107 failed: company A scope leaked to company B.';
  end if;
  raise notice 'PASS: ACL-107 company scope does not cross company boundary.';

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000701'
  );
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'Company scope exact match failed.';
  end if;
  raise notice 'PASS: company scope allows the matching company.';

  -- ACL-108: parent org-unit scope includes a valid descendant when enabled.
  update hr_security.group_scope_assignments
     set scope_id='00000000-0000-0000-0000-000000000604'
   where group_id='00000000-0000-0000-0000-000000000202';

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000701',
    '00000000-0000-0000-0000-000000000704'
  );
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'ACL-108 failed: valid descendant was not included.';
  end if;
  raise notice 'PASS: ACL-108 current descendant is included when configured.';

  update hr_security.data_scopes
     set include_descendants=false
   where id='00000000-0000-0000-0000-000000000604';

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000701',
    '00000000-0000-0000-0000-000000000704'
  );
  if v_allowed is distinct from false or v_reason <> 'SCOPE_NOT_GRANTED' then
    raise exception 'ACL-108 failed: descendant was included when disabled.';
  end if;
  raise notice 'PASS: ACL-108 descendant is excluded when disabled.';

  -- ACL-109: historical descendant lookup remains fail-closed.
  update hr_security.data_scopes
     set include_descendants=true
   where id='00000000-0000-0000-0000-000000000604';

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000701',
    '00000000-0000-0000-0000-000000000704',
    null,
    (current_date - 2)::timestamptz
  );
  if v_allowed is distinct from false or v_reason <> 'SCOPE_NOT_GRANTED' then
    raise exception 'ACL-109 failed: historical descendant access was not fail-closed.';
  end if;
  raise notice 'PASS: ACL-109 historical descendant lookup fails closed.';

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000701',
    '00000000-0000-0000-0000-000000000703'
  );
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'Exact org-unit scope failed.';
  end if;
  raise notice 'PASS: exact org-unit scope remains valid.';
end
$scope_test$;

-- ACL-127: a NULL-scope temporary deny is not interpreted as tenant-wide.
update hr_security.group_scope_assignments
   set scope_id='00000000-0000-0000-0000-000000000602'
 where group_id='00000000-0000-0000-0000-000000000202';

insert into hr_security.temporary_access(
  tenant_id, app_user_id, system_id, permission_id, scope_id, effect,
  starts_at, ends_at, approved_by, approved_at
)
values (
  '00000000-0000-0000-0000-000000000201',
  '00000000-0000-0000-0000-000000000102',
  '00000000-0000-0000-0000-000000000402',
  '00000000-0000-0000-0000-000000000502',
  null,
  'deny',
  now() - interval '1 hour',
  now() + interval '1 hour',
  '00000000-0000-0000-0000-000000000999',
  now()
);

do $null_scope_test$
declare
  v_allowed boolean;
  v_reason text;
begin
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201'
  );
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'ACL-127 failed: NULL-scope deny was treated as tenant-wide.';
  end if;
  raise notice 'PASS: ACL-127 NULL scope is not implicitly tenant-wide.';
end
$null_scope_test$;

do $sensitive_permission_test$
declare
  v_allowed boolean;
  v_reason text;
begin
  -- ACL-115: ordinary personnel view does not imply sensitive identity access.
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'personnel.view', 'view', '00000000-0000-0000-0000-000000000201'
  );
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'ACL-115 baseline personnel permission should be allowed.';
  end if;

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'sensitive.identity.view', 'view', '00000000-0000-0000-0000-000000000201'
  );
  if v_allowed is distinct from false or v_reason <> 'PERMISSION_NOT_GRANTED' then
    raise exception 'ACL-115 sensitive identity was implicitly granted.';
  end if;
  raise notice 'PASS: ACL-115 personnel view does not grant sensitive identity access.';

  -- ACL-116: document view does not imply document download.
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'sensitive.documents.view', 'view', '00000000-0000-0000-0000-000000000201'
  );
  if v_allowed is distinct from true or v_reason <> 'ALLOWED_BY_GROUP' then
    raise exception 'ACL-116 document metadata view should be allowed.';
  end if;

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'sensitive.documents.download', 'download', '00000000-0000-0000-0000-000000000201'
  );
  if v_allowed is distinct from false or v_reason <> 'PERMISSION_NOT_GRANTED' then
    raise exception 'ACL-116 document download was implicitly granted.';
  end if;
  raise notice 'PASS: ACL-116 document view does not grant document download.';

  -- ACL-117: an administrator-like group still needs the explicit bank permission.
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'sensitive.bank.view', 'view', '00000000-0000-0000-0000-000000000201'
  );
  if v_allowed is distinct from false or v_reason <> 'PERMISSION_NOT_GRANTED' then
    raise exception 'ACL-117 sensitive bank permission was implicitly granted.';
  end if;
  raise notice 'PASS: ACL-117 sensitive bank access requires its own permission.';
end
$sensitive_permission_test$;

do $temporary_access_test$
declare
  v_allowed boolean;
  v_reason text;
begin
  -- ACL-110: future temporary allow is not active yet.
  update hr_security.user_groups
     set is_active=false
   where id='00000000-0000-0000-0000-000000000202';
  insert into hr_security.temporary_access(
    tenant_id, app_user_id, system_id, permission_id, scope_id, effect,
    starts_at, ends_at, approved_by, approved_at
  )
  values (
    '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000102',
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-000000000502',
    '00000000-0000-0000-0000-000000000602',
    'allow',
    now() + interval '1 hour',
    now() + interval '2 hours',
    '00000000-0000-0000-0000-000000000999',
    now()
  );

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201'
  );
  if v_allowed is distinct from false or v_reason <> 'TEMPORARY_ACCESS_NOT_ACTIVE_OR_SCOPE_MISMATCH' then
    raise exception 'ACL-110 failed: future temporary allow became active early.';
  end if;
  raise notice 'PASS: ACL-110 future temporary allow is not active early.';

  delete from hr_security.temporary_access;

  -- ACL-120: no active membership and no temporary access means deny.
  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201'
  );
  if v_allowed is distinct from false or v_reason <> 'NO_ACTIVE_MEMBERSHIP' then
    raise exception 'ACL-120 failed: expected NO_ACTIVE_MEMBERSHIP, got %', v_reason;
  end if;
  raise notice 'PASS: ACL-120 no active membership is denied.';

  -- ACL-111: active temporary deny overrides a group allow.
  update hr_security.user_groups
     set is_active=true
   where id='00000000-0000-0000-0000-000000000202';
  insert into hr_security.temporary_access(
    tenant_id, app_user_id, system_id, permission_id, scope_id, effect,
    starts_at, ends_at, approved_by, approved_at
  )
  values (
    '00000000-0000-0000-0000-000000000201',
    '00000000-0000-0000-0000-000000000102',
    '00000000-0000-0000-0000-000000000402',
    '00000000-0000-0000-0000-000000000502',
    '00000000-0000-0000-0000-000000000602',
    'deny',
    now() - interval '1 hour',
    now() + interval '1 hour',
    '00000000-0000-0000-0000-000000000999',
    now()
  );

  select allowed, reason_code into v_allowed, v_reason
  from hr_internal.evaluate_permission_context(
    'org.chart.view', 'add', '00000000-0000-0000-0000-000000000201'
  );
  if v_allowed is distinct from false or v_reason <> 'EXPLICIT_DENY' then
    raise exception 'ACL-111 failed: temporary deny did not override group allow.';
  end if;
  raise notice 'PASS: ACL-111 active temporary deny overrides group allow.';
end
$temporary_access_test$;

select conname, convalidated
from pg_constraint
where conrelid='hr_security.temporary_access'::regclass
  and conname in (
    'ck_temporary_access_approval_pair_v18',
    'ck_temporary_access_global_scope_approval_v18'
  )
order by conname;

do $test$
begin
  begin
    insert into hr_security.temporary_access(scope_id, effect, approved_by, approved_at)
    values (null, 'deny', null, null);
    raise exception 'expected null-scope approval check to reject the row';
  exception when check_violation then
    null;
  end;
  raise notice 'PASS: SEC-405 null scope requires approval metadata.';

  begin
    insert into hr_security.temporary_access(scope_id, effect, approved_by, approved_at)
    values (gen_random_uuid(), 'deny', gen_random_uuid(), null);
    raise exception 'expected approval-pair check to reject mismatched metadata';
  exception when check_violation then
    null;
  end;
  raise notice 'PASS: SEC-404 approval metadata must be paired.';

  begin
    insert into hr_security.temporary_access(scope_id, effect, approved_by, approved_at)
    values (null, 'allow', gen_random_uuid(), now());
    raise exception 'expected existing allow-scope check to reject NULL scope';
  exception when check_violation then
    null;
  end;
  raise notice 'PASS: NULL-scope temporary allow remains prohibited.';

  insert into hr_security.temporary_access(scope_id, effect, approved_by, approved_at)
  values (gen_random_uuid(), 'allow', gen_random_uuid(), now());

  insert into hr_security.temporary_access(scope_id, effect, approved_by, approved_at)
  values (null, 'deny', gen_random_uuid(), now());
  raise notice 'PASS: explicit scoped allow and approved NULL-scope deny satisfy integrity checks.';
end
$test$;

rollback;
'@

try {
    [System.IO.File]::WriteAllText($bootstrapPath, $bootstrapSql, $utf8NoBom)
    [System.IO.File]::WriteAllText($smokePath, $smokeSql, $utf8NoBom)

    docker run --rm -d --name $containerName -e POSTGRES_PASSWORD=local_test_only -e POSTGRES_DB=hrsoft_test $postgresImage | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "Could not start disposable PostgreSQL container from image: $postgresImage" }

    $ready = $false
    for ($i = 0; $i -lt 30; $i++) {
        docker exec $containerName pg_isready -U postgres -d hrsoft_test *> $null
        if ($LASTEXITCODE -eq 0) {
            $ready = $true
            break
        }
        Start-Sleep -Seconds 1
    }
    if (-not $ready) { throw 'Disposable PostgreSQL container did not become ready.' }

    $serverVersion = docker exec $containerName psql -U postgres -d hrsoft_test -Atqc 'show server_version'
    if ($LASTEXITCODE -ne 0) { throw 'Could not read disposable PostgreSQL server version.' }
    Write-Output "Disposable PostgreSQL server: $serverVersion (image: $postgresImage)"

    Get-Content -Raw $bootstrapPath | docker exec -i $containerName psql -v ON_ERROR_STOP=1 -U postgres -d hrsoft_test
    if ($LASTEXITCODE -ne 0) { throw 'Bootstrap schema setup failed.' }

    Get-Content -Raw $migrationPath | docker exec -i $containerName psql -v ON_ERROR_STOP=1 -U postgres -d hrsoft_test
    if ($LASTEXITCODE -ne 0) { throw "Migration failed on disposable PostgreSQL server $serverVersion." }

    Get-Content -Raw $smokePath | docker exec -i $containerName psql -v ON_ERROR_STOP=1 -U postgres -d hrsoft_test
    if ($LASTEXITCODE -ne 0) { throw 'Migration smoke checks failed.' }

    Write-Output 'DISPOSABLE POSTGRESQL MIGRATION AND LOGIC SMOKE: PASS'
    Write-Output 'Covered: AUTH_REQUIRED, archived app_user, ACL-101/102/103/104/105/106/107/108/109/110/111/114/115/116/117/118/120/121/123/124/127/128, and SEC-404/405 approval constraints.'
    Write-Output 'auth.uid() is stubbed; scope_matches() is the actual source implementation. This is not real Supabase JWT, RLS-role, or full tenant-isolation testing.'
}
finally {
    docker rm -f $containerName *> $null
    Remove-Item -LiteralPath $bootstrapPath, $smokePath -Force -ErrorAction SilentlyContinue
}
