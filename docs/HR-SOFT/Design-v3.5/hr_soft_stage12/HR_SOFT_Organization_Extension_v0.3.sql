-- HR-SOFT Stage 12 / proposed organization extension v0.3
-- DESIGN DRAFT ONLY. Depends on reviewed baseline v0.1 and company-safe
-- constraints proposed in Stage 5. Do not run in production.

begin;

create schema if not exists hr_org;

-- 1) Organizational position: separate from a staffed position.
create table if not exists hr_org.organizational_positions (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  company_id uuid not null,
  position_key text not null,
  title text not null,
  priority integer not null default 0,
  level_code text,
  is_visible boolean not null default true,
  is_active boolean not null default true,
  valid_from date not null default current_date,
  valid_to date,
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, company_id, id),
  unique (tenant_id, company_id, position_key),
  foreign key (tenant_id, company_id)
    references hr_core.companies(tenant_id, id),
  check (valid_to is null or valid_to >= valid_from)
);

alter table hr_org.positions
  add column if not exists organizational_position_id uuid;

alter table hr_org.positions
  add constraint fk_positions_org_position_v03
  foreign key (tenant_id, company_id, organizational_position_id)
  references hr_org.organizational_positions(tenant_id, company_id, id)
  not valid;

-- 2) Versioned organizational establishment profile.
create table if not exists hr_org.position_profiles (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  company_id uuid not null,
  position_id uuid not null,
  profile_version integer not null,
  organization_ref text,
  org_layer_id uuid,
  position_number text not null,
  position_title text not null,
  approval_date date,
  superior_position_id uuid,
  gender_code text,
  satellite_type_code text,
  region_code text,
  position_type_code text,
  shift_type_code text,
  execution_date date,
  language_level_code text,
  job_group_code text,
  grade_number text,
  job_family_code text,
  is_formal_position boolean,
  classification_position_title text,
  is_active boolean not null default true,
  approved_capacity integer,
  temporary_capacity integer,
  capacity_effective_date date,
  profile_notes text,
  recorded_at timestamptz not null default now(),
  recorded_by uuid,
  effective_from date not null,
  effective_to date,
  unique (tenant_id, id),
  unique (tenant_id, position_id, profile_version),
  foreign key (tenant_id, company_id, position_id)
    references hr_org.positions(tenant_id, company_id, id),
  foreign key (tenant_id, company_id, org_layer_id)
    references hr_org.org_layers(tenant_id, company_id, id),
  foreign key (tenant_id, company_id, superior_position_id)
    references hr_org.positions(tenant_id, company_id, id),
  foreign key (tenant_id, recorded_by)
    references hr_security.app_users(tenant_id, id),
  check (approved_capacity is null or approved_capacity >= 0),
  check (temporary_capacity is null or temporary_capacity >= 0),
  check (effective_to is null or effective_to >= effective_from)
);

create index if not exists ix_position_profiles_effective
  on hr_org.position_profiles(tenant_id, position_id, effective_from, effective_to);

-- 3) Duties catalogue and position links.
create table if not exists hr_org.duties (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  duty_code text not null,
  name text not null,
  description text,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, duty_code),
  foreign key (tenant_id, created_by)
    references hr_security.app_users(tenant_id, id)
);

create table if not exists hr_org.position_duties (
  tenant_id uuid not null references hr_core.tenants(id),
  company_id uuid not null,
  position_id uuid not null,
  duty_id uuid not null,
  valid_from date not null,
  valid_to date,
  priority integer not null default 0,
  created_at timestamptz not null default now(),
  created_by uuid,
  primary key (tenant_id, position_id, duty_id, valid_from),
  foreign key (tenant_id, company_id, position_id)
    references hr_org.positions(tenant_id, company_id, id),
  foreign key (tenant_id, duty_id)
    references hr_org.duties(tenant_id, id),
  foreign key (tenant_id, created_by)
    references hr_security.app_users(tenant_id, id),
  check (valid_to is null or valid_to >= valid_from)
);

-- 4) Offices / administrative portfolios.
create table if not exists hr_org.offices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  company_id uuid not null,
  office_code text not null,
  title text not null,
  display_priority integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  unique (tenant_id, company_id, id),
  unique (tenant_id, company_id, office_code),
  foreign key (tenant_id, company_id)
    references hr_core.companies(tenant_id, id),
  foreign key (tenant_id, created_by)
    references hr_security.app_users(tenant_id, id)
);

create table if not exists hr_org.position_office_assignments (
  tenant_id uuid not null references hr_core.tenants(id),
  company_id uuid not null,
  position_id uuid not null,
  office_id uuid not null,
  valid_from date not null,
  valid_to date,
  created_at timestamptz not null default now(),
  created_by uuid,
  primary key (tenant_id, position_id, office_id, valid_from),
  foreign key (tenant_id, company_id, position_id)
    references hr_org.positions(tenant_id, company_id, id),
  foreign key (tenant_id, company_id, office_id)
    references hr_org.offices(tenant_id, company_id, id),
  foreign key (tenant_id, created_by)
    references hr_security.app_users(tenant_id, id),
  check (valid_to is null or valid_to >= valid_from)
);

-- 5) Succession candidates. Candidate-as-personnel is a design proposal,
-- not a confirmed fact from the source; review before implementation.
create table if not exists hr_org.succession_candidates (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  company_id uuid not null,
  target_position_id uuid not null,
  candidate_personnel_record_id uuid not null,
  candidate_type text not null
    check (candidate_type in ('primary','acting','potential')),
  priority integer not null default 1,
  valid_from date not null,
  valid_to date,
  reason text,
  status text not null default 'active'
    check (status in ('active','expired','cancelled')),
  recorded_at timestamptz not null default now(),
  recorded_by uuid,
  unique (tenant_id, id),
  foreign key (tenant_id, company_id, target_position_id)
    references hr_org.positions(tenant_id, company_id, id),
  foreign key (tenant_id, company_id, candidate_personnel_record_id)
    references hr_core.personnel_records(tenant_id, company_id, id),
  foreign key (tenant_id, recorded_by)
    references hr_security.app_users(tenant_id, id),
  check (valid_to is null or valid_to >= valid_from)
);

create index if not exists ix_succession_target_priority
  on hr_org.succession_candidates(
    tenant_id, target_position_id, candidate_type, priority, valid_from
  );

commit;

-- TODO before use:
-- - Validate company-safe unique indexes from Stage 5 exist.
-- - Determine whether profile fields should be code tables or controlled text.
-- - Resolve organization reference semantics.
-- - Resolve candidate target type for succession.
-- - Add RLS and permission keys for each new table.
-- - Add append-only profile/succession event strategy.
-- - Add overlap rules for successor categories and profile effective periods.
-- - Do not grant direct table access to authenticated.
