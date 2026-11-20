-- HR-SOFT | Draft PostgreSQL baseline
-- Status: DESIGN ONLY. NOT EXECUTED against Supabase or any database.
-- Version: 0.1 | Date: 2026-11-18
-- Tenant model: one independent customer = one tenant.
-- Apply only after project identity, environment, backup and migration review.

begin;

create extension if not exists pgcrypto;
create extension if not exists citext;

create schema if not exists hr_core;
create schema if not exists hr_org;
create schema if not exists hr_security;
create schema if not exists hr_audit;

-- ---------------------------------------------------------------------------
-- 1. Core tenant and company model
-- ---------------------------------------------------------------------------

create table if not exists hr_core.tenants (
    id uuid primary key default gen_random_uuid(),
    tenant_key text not null unique,
    display_name text not null,
    status text not null default 'active'
        check (status in ('active', 'suspended', 'archived')),
    created_at timestamptz not null default now(),
    created_by uuid,
    archived_at timestamptz,
    archived_by uuid,
    archive_reason text,
    constraint tenants_archive_consistency check (
        (status = 'archived' and archived_at is not null)
        or (status <> 'archived' and archived_at is null)
    )
);

create table if not exists hr_core.companies (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    parent_company_id uuid,
    company_code text not null,
    legal_name text not null,
    display_name text not null,
    status text not null default 'active'
        check (status in ('active', 'inactive', 'archived')),
    valid_from date not null default current_date,
    valid_to date,
    created_at timestamptz not null default now(),
    created_by uuid,
    updated_at timestamptz not null default now(),
    updated_by uuid,
    archived_at timestamptz,
    archived_by uuid,
    archive_reason text,
    unique (tenant_id, id),
    unique (tenant_id, company_code),
    foreign key (tenant_id, parent_company_id)
        references hr_core.companies(tenant_id, id),
    check (valid_to is null or valid_to >= valid_from),
    check ((status = 'archived' and archived_at is not null)
        or (status <> 'archived' and archived_at is null))
);

create index if not exists ix_companies_tenant_parent
    on hr_core.companies(tenant_id, parent_company_id);

-- ---------------------------------------------------------------------------
-- 2. Person, personnel record and application account are separate concepts
-- ---------------------------------------------------------------------------

create table if not exists hr_core.people (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    first_name text not null,
    last_name text not null,
    first_name_en text,
    last_name_en text,
    father_name text,
    birth_date date,
    gender_code text,
    birthplace_code text,
    mobile_e164 text,
    status text not null default 'active'
        check (status in ('active', 'inactive', 'archived')),
    created_at timestamptz not null default now(),
    created_by uuid,
    updated_at timestamptz not null default now(),
    updated_by uuid,
    archived_at timestamptz,
    archived_by uuid,
    archive_reason text,
    unique (tenant_id, id),
    check ((status = 'archived' and archived_at is not null)
        or (status <> 'archived' and archived_at is null))
);

create index if not exists ix_people_tenant_name
    on hr_core.people(tenant_id, last_name, first_name);

create table if not exists hr_core.personnel_records (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    person_id uuid not null,
    company_id uuid not null,
    personnel_no text not null,
    employment_status text not null default 'active',
    employment_type_code text,
    valid_from date not null default current_date,
    valid_to date,
    created_at timestamptz not null default now(),
    created_by uuid,
    archived_at timestamptz,
    archived_by uuid,
    archive_reason text,
    unique (tenant_id, id),
    unique (tenant_id, company_id, personnel_no),
    foreign key (tenant_id, person_id)
        references hr_core.people(tenant_id, id),
    foreign key (tenant_id, company_id)
        references hr_core.companies(tenant_id, id),
    check (valid_to is null or valid_to >= valid_from)
);

create index if not exists ix_personnel_person
    on hr_core.personnel_records(tenant_id, person_id);
create index if not exists ix_personnel_company
    on hr_core.personnel_records(tenant_id, company_id);

-- This table maps an authenticated Supabase Auth identity to an HR-SOFT user.
-- Authorization must never trust user-editable auth user_metadata.
create table if not exists hr_security.app_users (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    auth_user_id uuid not null unique references auth.users(id),
    person_id uuid,
    username citext,
    status text not null default 'active'
        check (status in ('active', 'blocked', 'archived')),
    force_password_change boolean not null default false,
    created_at timestamptz not null default now(),
    created_by uuid,
    archived_at timestamptz,
    archived_by uuid,
    archive_reason text,
    unique (tenant_id, id),
    foreign key (tenant_id, person_id)
        references hr_core.people(tenant_id, id),
    unique (tenant_id, username),
    check ((status = 'archived' and archived_at is not null)
        or (status <> 'archived' and archived_at is null))
);

-- citext is optional; install explicitly before using app_users.username.
-- If citext is unavailable, change username to text and use a normalized index.

-- ---------------------------------------------------------------------------
-- 3. Organization structure
-- ---------------------------------------------------------------------------

create table if not exists hr_org.org_layers (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    company_id uuid not null,
    layer_code text not null,
    title text not null,
    sort_order integer not null default 0,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    created_by uuid,
    unique (tenant_id, id),
    unique (tenant_id, company_id, layer_code),
    foreign key (tenant_id, company_id)
        references hr_core.companies(tenant_id, id)
);

create table if not exists hr_org.org_units (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    company_id uuid not null,
    layer_id uuid,
    parent_unit_id uuid,
    unit_code text not null,
    title text not null,
    unit_type_code text,
    is_visible boolean not null default true,
    is_active boolean not null default true,
    valid_from date not null default current_date,
    valid_to date,
    created_at timestamptz not null default now(),
    created_by uuid,
    archived_at timestamptz,
    archived_by uuid,
    archive_reason text,
    unique (tenant_id, id),
    unique (tenant_id, company_id, unit_code),
    foreign key (tenant_id, company_id)
        references hr_core.companies(tenant_id, id),
    foreign key (tenant_id, layer_id)
        references hr_org.org_layers(tenant_id, id),
    foreign key (tenant_id, parent_unit_id)
        references hr_org.org_units(tenant_id, id),
    check (valid_to is null or valid_to >= valid_from)
);

create index if not exists ix_org_units_tree
    on hr_org.org_units(tenant_id, company_id, parent_unit_id);

create table if not exists hr_org.positions (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    company_id uuid not null,
    org_unit_id uuid not null,
    position_code text not null,
    title text not null,
    superior_position_id uuid,
    approved_capacity integer not null default 1 check (approved_capacity >= 0),
    is_active boolean not null default true,
    valid_from date not null default current_date,
    valid_to date,
    created_at timestamptz not null default now(),
    created_by uuid,
    archived_at timestamptz,
    archived_by uuid,
    archive_reason text,
    unique (tenant_id, id),
    unique (tenant_id, company_id, position_code),
    foreign key (tenant_id, company_id)
        references hr_core.companies(tenant_id, id),
    foreign key (tenant_id, org_unit_id)
        references hr_org.org_units(tenant_id, id),
    foreign key (tenant_id, superior_position_id)
        references hr_org.positions(tenant_id, id),
    check (valid_to is null or valid_to >= valid_from)
);

create index if not exists ix_positions_unit
    on hr_org.positions(tenant_id, org_unit_id);
create index if not exists ix_positions_superior
    on hr_org.positions(tenant_id, superior_position_id);

create table if not exists hr_org.position_relationships (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    from_position_id uuid not null,
    to_position_id uuid not null,
    relationship_type text not null
        check (relationship_type in ('supervisory', 'advisory', 'functional')),
    valid_from date not null,
    valid_to date,
    description text,
    created_at timestamptz not null default now(),
    created_by uuid,
    unique (tenant_id, id),
    foreign key (tenant_id, from_position_id)
        references hr_org.positions(tenant_id, id),
    foreign key (tenant_id, to_position_id)
        references hr_org.positions(tenant_id, id),
    check (from_position_id <> to_position_id),
    check (valid_to is null or valid_to >= valid_from)
);

create table if not exists hr_org.position_assignments (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    company_id uuid not null,
    position_id uuid not null,
    personnel_record_id uuid not null,
    assignment_type text not null default 'primary'
        check (assignment_type in ('primary', 'acting', 'temporary')),
    status text not null default 'scheduled'
        check (status in ('scheduled', 'active', 'ended', 'cancelled')),
    valid_from date not null,
    valid_to date,
    recorded_at timestamptz not null default now(),
    recorded_by uuid,
    reason text,
    ended_at timestamptz,
    ended_by uuid,
    cancellation_reason text,
    unique (tenant_id, id),
    foreign key (tenant_id, company_id)
        references hr_core.companies(tenant_id, id),
    foreign key (tenant_id, position_id)
        references hr_org.positions(tenant_id, id),
    foreign key (tenant_id, personnel_record_id)
        references hr_core.personnel_records(tenant_id, id),
    check (valid_to is null or valid_to >= valid_from),
    check (status <> 'cancelled' or cancellation_reason is not null)
);

create index if not exists ix_assignments_position_dates
    on hr_org.position_assignments(tenant_id, position_id, valid_from, valid_to);
create index if not exists ix_assignments_person_dates
    on hr_org.position_assignments(tenant_id, personnel_record_id, valid_from, valid_to);

-- ---------------------------------------------------------------------------
-- 4. Security: groups, permissions, scopes, temporary access
-- ---------------------------------------------------------------------------

create table if not exists hr_security.systems (
    id uuid primary key default gen_random_uuid(),
    system_key text not null unique,
    title text not null,
    is_active boolean not null default true
);

create table if not exists hr_security.user_groups (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    system_id uuid not null references hr_security.systems(id),
    group_key text not null,
    title text not null,
    is_active boolean not null default true,
    created_at timestamptz not null default now(),
    created_by uuid,
    archived_at timestamptz,
    archived_by uuid,
    archive_reason text,
    unique (tenant_id, id),
    unique (tenant_id, system_id, group_key)
);

create table if not exists hr_security.group_memberships (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    group_id uuid not null,
    app_user_id uuid not null,
    is_active boolean not null default true,
    valid_from timestamptz not null default now(),
    valid_to timestamptz,
    created_at timestamptz not null default now(),
    created_by uuid,
    ended_at timestamptz,
    ended_by uuid,
    unique (tenant_id, id),
    foreign key (tenant_id, group_id)
        references hr_security.user_groups(tenant_id, id),
    foreign key (tenant_id, app_user_id)
        references hr_security.app_users(tenant_id, id),
    check (valid_to is null or valid_to >= valid_from)
);

create index if not exists ix_group_memberships_user
    on hr_security.group_memberships(tenant_id, app_user_id, is_active);
create index if not exists ix_group_memberships_group
    on hr_security.group_memberships(tenant_id, group_id, is_active);

create table if not exists hr_security.permissions (
    id uuid primary key default gen_random_uuid(),
    system_id uuid not null references hr_security.systems(id),
    permission_key text not null,
    title text not null,
    description text,
    unique (system_id, permission_key)
);

create table if not exists hr_security.group_permission_rules (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    group_id uuid not null,
    permission_id uuid not null references hr_security.permissions(id),
    can_add boolean not null default false,
    can_edit boolean not null default false,
    can_delete boolean not null default false,
    effect text not null default 'allow'
        check (effect in ('allow', 'deny')),
    changed_at timestamptz not null default now(),
    changed_by uuid,
    unique (tenant_id, id),
    unique (tenant_id, group_id, permission_id),
    foreign key (tenant_id, group_id)
        references hr_security.user_groups(tenant_id, id)
);

create table if not exists hr_security.data_scopes (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    scope_type text not null
        check (scope_type in ('tenant', 'company', 'org_unit', 'personnel')),
    company_id uuid,
    org_unit_id uuid,
    personnel_record_id uuid,
    include_descendants boolean not null default false,
    created_at timestamptz not null default now(),
    created_by uuid,
    unique (tenant_id, id),
    foreign key (tenant_id, company_id)
        references hr_core.companies(tenant_id, id),
    foreign key (tenant_id, org_unit_id)
        references hr_org.org_units(tenant_id, id),
    foreign key (tenant_id, personnel_record_id)
        references hr_core.personnel_records(tenant_id, id),
    check (
        (scope_type = 'tenant' and company_id is null and org_unit_id is null and personnel_record_id is null)
        or (scope_type = 'company' and company_id is not null and org_unit_id is null and personnel_record_id is null)
        or (scope_type = 'org_unit' and org_unit_id is not null and personnel_record_id is null)
        or (scope_type = 'personnel' and personnel_record_id is not null)
    )
);

create table if not exists hr_security.group_scope_assignments (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    group_id uuid not null,
    scope_id uuid not null,
    effect text not null default 'allow'
        check (effect in ('allow', 'deny')),
    valid_from timestamptz not null default now(),
    valid_to timestamptz,
    created_at timestamptz not null default now(),
    created_by uuid,
    unique (tenant_id, id),
    foreign key (tenant_id, group_id)
        references hr_security.user_groups(tenant_id, id),
    foreign key (tenant_id, scope_id)
        references hr_security.data_scopes(tenant_id, id),
    check (valid_to is null or valid_to >= valid_from)
);

create table if not exists hr_security.temporary_access (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    app_user_id uuid not null,
    permission_id uuid not null references hr_security.permissions(id),
    scope_id uuid,
    effect text not null check (effect in ('allow', 'deny')),
    starts_at timestamptz not null,
    ends_at timestamptz not null,
    reason text not null,
    approved_by uuid,
    created_at timestamptz not null default now(),
    created_by uuid,
    unique (tenant_id, id),
    foreign key (tenant_id, app_user_id)
        references hr_security.app_users(tenant_id, id),
    foreign key (tenant_id, scope_id)
        references hr_security.data_scopes(tenant_id, id),
    check (ends_at > starts_at)
);

-- ---------------------------------------------------------------------------
-- 5. Immutable audit/history foundations
-- ---------------------------------------------------------------------------

create table if not exists hr_audit.audit_events (
    id bigint generated always as identity primary key,
    tenant_id uuid not null references hr_core.tenants(id),
    actor_app_user_id uuid,
    event_type text not null,
    entity_schema text not null,
    entity_table text not null,
    entity_id uuid,
    occurred_at timestamptz not null default now(),
    effective_at timestamptz,
    reason text,
    before_state jsonb,
    after_state jsonb,
    request_id text,
    source_ip inet,
    user_agent text
);

create index if not exists ix_audit_tenant_time
    on hr_audit.audit_events(tenant_id, occurred_at desc);
create index if not exists ix_audit_entity
    on hr_audit.audit_events(tenant_id, entity_schema, entity_table, entity_id);

create table if not exists hr_audit.permission_change_history (
    id bigint generated always as identity primary key,
    tenant_id uuid not null references hr_core.tenants(id),
    group_id uuid,
    permission_id uuid,
    old_values jsonb not null,
    new_values jsonb not null,
    changed_by uuid,
    changed_at timestamptz not null default now(),
    change_reason text
);

create index if not exists ix_permission_history_tenant_time
    on hr_audit.permission_change_history(tenant_id, changed_at desc);

-- No update/delete grants or policies should be given to application roles
-- for audit tables. Append-only enforcement triggers are part of the next
-- hardening migration and must be tested before production.

commit;
