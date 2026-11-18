-- HR-SOFT / Supabase Org-Ch clean-install foundation


-- Source: stages 2-7, 12-14, 16; adapted for a new empty project.


-- Stage 6 resolver SQL is excluded because it is explicitly a non-deployable skeleton.


-- No tenant, company, Auth user, permission catalogue or business data is seeded.


-- Business tables are RLS-enabled, forced and default-deny; no business API grants are opened.



-- HR-SOFT | Draft PostgreSQL baseline
-- Source baseline was design-only; this curated migration has been applied to Org-Ch development.
-- Version: 0.1 | Date: 2026-11-18
-- Tenant model: one independent customer = one tenant.
-- Applied after verifying the Org-Ch development project was empty and reviewing its schema inventory.

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
    unique (tenant_id, system_id, id),
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
    is_active boolean not null default true,
    unique (system_id, permission_key),
    unique (system_id, id)
);

create table if not exists hr_security.group_permission_rules (
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

-- HR-SOFT | Supplemental workflow, capacity, notification, file and sensitive data tables
-- Source supplemental design; incorporated into the curated Org-Ch development migration.
-- Depends on HR_SOFT_Postgres_Baseline_v0.1.sql.

create schema if not exists hr_workflow;
create schema if not exists hr_files;
create schema if not exists hr_notify;
create schema if not exists hr_sensitive;

-- Generic workflow envelope
create table if not exists hr_workflow.requests (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    request_no text not null,
    request_type text not null,
    subject text not null,
    description text,
    requester_app_user_id uuid not null,
    status text not null default 'draft'
        check (status in ('draft','submitted','in_review','approved','rejected','cancelled','completed')),
    submitted_at timestamptz,
    completed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (tenant_id, id),
    unique (tenant_id, request_no),
    foreign key (tenant_id, requester_app_user_id)
        references hr_security.app_users(tenant_id, id)
);

create table if not exists hr_workflow.steps (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    request_id uuid not null,
    step_no integer not null,
    approver_app_user_id uuid,
    approver_group_id uuid,
    status text not null default 'pending'
        check (status in ('pending','approved','rejected','skipped','cancelled')),
    assigned_at timestamptz not null default now(),
    decided_at timestamptz,
    decision_reason text,
    unique (tenant_id, id),
    unique (tenant_id, request_id, step_no),
    foreign key (tenant_id, request_id)
        references hr_workflow.requests(tenant_id, id),
    foreign key (tenant_id, approver_app_user_id)
        references hr_security.app_users(tenant_id, id),
    foreign key (tenant_id, approver_group_id)
        references hr_security.user_groups(tenant_id, id),
    check (approver_app_user_id is not null or approver_group_id is not null)
);

create table if not exists hr_workflow.decisions (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    request_id uuid not null,
    step_id uuid,
    decision text not null check (decision in ('approved','rejected','returned','cancelled')),
    reason text,
    decided_by uuid not null,
    decided_at timestamptz not null default now(),
    unique (tenant_id, id),
    foreign key (tenant_id, request_id)
        references hr_workflow.requests(tenant_id, id),
    foreign key (tenant_id, step_id)
        references hr_workflow.steps(tenant_id, id),
    foreign key (tenant_id, decided_by)
        references hr_security.app_users(tenant_id, id),
    check (decision <> 'rejected' or nullif(trim(reason), '') is not null)
);

-- Capacity requests are separate from generic workflow to preserve HR rules.
create table if not exists hr_workflow.capacity_change_requests (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    position_id uuid not null,
    requested_by uuid not null,
    old_capacity integer not null check (old_capacity >= 0),
    proposed_capacity integer not null check (proposed_capacity >= 0),
    approval_mode text not null check (approval_mode in ('org_manager','system_admin')),
    status text not null default 'pending_approval'
        check (status in ('pending_approval','approved_awaiting_execution','rejected','cancelled','scheduled','overdue','executed','awaiting_reapproval')),
    execution_mode text not null default 'immediate'
        check (execution_mode in ('immediate','scheduled')),
    planned_execution_date date,
    approved_by uuid,
    approved_at timestamptz,
    rejection_reason text,
    cancellation_reason text,
    executed_by uuid,
    executed_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (tenant_id, id),
    foreign key (tenant_id, position_id)
        references hr_org.positions(tenant_id, id),
    foreign key (tenant_id, requested_by)
        references hr_security.app_users(tenant_id, id),
    foreign key (tenant_id, approved_by)
        references hr_security.app_users(tenant_id, id),
    foreign key (tenant_id, executed_by)
        references hr_security.app_users(tenant_id, id),
    check (status <> 'rejected' or nullif(trim(rejection_reason), '') is not null),
    check (status <> 'cancelled' or nullif(trim(cancellation_reason), '') is not null),
    check (execution_mode <> 'scheduled' or planned_execution_date is not null)
);

create index if not exists ix_capacity_requests_status_due
    on hr_workflow.capacity_change_requests(tenant_id, status, planned_execution_date);

create table if not exists hr_workflow.capacity_request_revisions (
    id bigint generated always as identity primary key,
    tenant_id uuid not null references hr_core.tenants(id),
    request_id uuid not null,
    revision_no integer not null,
    previous_values jsonb not null,
    revised_values jsonb not null,
    edited_by uuid not null,
    edited_at timestamptz not null default now(),
    edit_reason text not null,
    approval_reset boolean not null default true,
    unique (tenant_id, request_id, revision_no),
    foreign key (tenant_id, request_id)
        references hr_workflow.capacity_change_requests(tenant_id, id),
    foreign key (tenant_id, edited_by)
        references hr_security.app_users(tenant_id, id)
);

create table if not exists hr_workflow.capacity_request_notes (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    request_id uuid not null,
    note_text text not null,
    created_by uuid not null,
    created_at timestamptz not null default now(),
    unique (tenant_id, id),
    foreign key (tenant_id, request_id)
        references hr_workflow.capacity_change_requests(tenant_id, id),
    foreign key (tenant_id, created_by)
        references hr_security.app_users(tenant_id, id)
);

-- File record and immutable versions; object bytes live in private Storage bucket.
create table if not exists hr_files.file_objects (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    owner_schema text not null,
    owner_table text not null,
    owner_id uuid not null,
    file_category text not null,
    display_title text,
    description text,
    original_filename text not null,
    current_version_no integer not null default 1,
    uploaded_by uuid not null,
    uploaded_at timestamptz not null default now(),
    is_archived boolean not null default false,
    unique (tenant_id, id),
    foreign key (tenant_id, uploaded_by)
        references hr_security.app_users(tenant_id, id)
);

create table if not exists hr_files.file_versions (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    file_object_id uuid not null,
    version_no integer not null,
    storage_bucket text not null,
    storage_object_path text not null,
    mime_type text not null,
    file_size_bytes bigint not null check (file_size_bytes >= 0),
    checksum_sha256 text,
    original_filename text not null,
    replacement_reason text,
    uploaded_by uuid not null,
    uploaded_at timestamptz not null default now(),
    unique (tenant_id, id),
    unique (tenant_id, file_object_id, version_no),
    foreign key (tenant_id, file_object_id)
        references hr_files.file_objects(tenant_id, id),
    foreign key (tenant_id, uploaded_by)
        references hr_security.app_users(tenant_id, id),
    check (version_no = 1 or nullif(trim(replacement_reason), '') is not null)
);

create table if not exists hr_workflow.capacity_request_files (
    tenant_id uuid not null references hr_core.tenants(id),
    request_id uuid not null,
    file_object_id uuid not null,
    attached_by uuid not null,
    attached_at timestamptz not null default now(),
    primary key (tenant_id, request_id, file_object_id),
    foreign key (tenant_id, request_id)
        references hr_workflow.capacity_change_requests(tenant_id, id),
    foreign key (tenant_id, file_object_id)
        references hr_files.file_objects(tenant_id, id),
    foreign key (tenant_id, attached_by)
        references hr_security.app_users(tenant_id, id)
);

-- Notifications: in-app delivery cannot be opted out; SMS may be disabled per recipient.
create table if not exists hr_notify.user_preferences (
    tenant_id uuid not null references hr_core.tenants(id),
    app_user_id uuid not null,
    sms_enabled boolean not null default true,
    updated_at timestamptz not null default now(),
    primary key (tenant_id, app_user_id),
    foreign key (tenant_id, app_user_id)
        references hr_security.app_users(tenant_id, id)
);

create table if not exists hr_notify.notifications (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    recipient_app_user_id uuid not null,
    channel text not null check (channel in ('in_app','sms')),
    event_key text not null,
    title text not null,
    body text not null,
    payload jsonb not null default '{}'::jsonb,
    status text not null default 'queued'
        check (status in ('queued','sent','failed','read','cancelled')),
    created_at timestamptz not null default now(),
    sent_at timestamptz,
    read_at timestamptz,
    provider_message_id text,
    failure_detail text,
    unique (tenant_id, id),
    foreign key (tenant_id, recipient_app_user_id)
        references hr_security.app_users(tenant_id, id)
);

create index if not exists ix_notifications_recipient
    on hr_notify.notifications(tenant_id, recipient_app_user_id, created_at desc);

-- ZIP export jobs retain policy metadata; generated ZIP bytes are temporary.
create table if not exists hr_files.export_jobs (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    request_id uuid not null,
    created_by uuid not null,
    status text not null default 'queued'
        check (status in ('queued','building','ready','downloaded','failed','cancelled','expired')),
    file_count integer,
    estimated_size_bytes bigint,
    actual_size_bytes bigint,
    temporary_storage_path text,
    created_at timestamptz not null default now(),
    completed_at timestamptz,
    expires_at timestamptz,
    downloaded_at timestamptz,
    failure_detail text,
    unique (tenant_id, id),
    foreign key (tenant_id, request_id)
        references hr_workflow.capacity_change_requests(tenant_id, id),
    foreign key (tenant_id, created_by)
        references hr_security.app_users(tenant_id, id)
);

create table if not exists hr_files.export_job_items (
    tenant_id uuid not null references hr_core.tenants(id),
    export_job_id uuid not null,
    file_version_id uuid not null,
    archive_entry_name text not null,
    primary key (tenant_id, export_job_id, file_version_id),
    foreign key (tenant_id, export_job_id)
        references hr_files.export_jobs(tenant_id, id),
    foreign key (tenant_id, file_version_id)
        references hr_files.file_versions(tenant_id, id)
);

-- Sensitive records store ciphertext only; encryption keys must remain outside DB.
create table if not exists hr_sensitive.identity_data (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    person_id uuid not null,
    national_id_ciphertext bytea,
    national_id_fingerprint text,
    passport_ciphertext bytea,
    updated_at timestamptz not null default now(),
    updated_by uuid,
    unique (tenant_id, id),
    unique (tenant_id, person_id),
    foreign key (tenant_id, person_id)
        references hr_core.people(tenant_id, id),
    foreign key (tenant_id, updated_by)
        references hr_security.app_users(tenant_id, id)
);

create table if not exists hr_sensitive.bank_accounts (
    id uuid primary key default gen_random_uuid(),
    tenant_id uuid not null references hr_core.tenants(id),
    personnel_record_id uuid not null,
    bank_name text,
    account_holder text,
    iban_ciphertext bytea,
    account_number_ciphertext bytea,
    iban_last4 text,
    is_primary boolean not null default false,
    valid_from date not null default current_date,
    valid_to date,
    created_at timestamptz not null default now(),
    created_by uuid,
    unique (tenant_id, id),
    foreign key (tenant_id, personnel_record_id)
        references hr_core.personnel_records(tenant_id, id),
    foreign key (tenant_id, created_by)
        references hr_security.app_users(tenant_id, id),
    check (valid_to is null or valid_to >= valid_from)
);

-- HR-SOFT Stage 4 / v2.2
-- Source Stage 4 patch; incorporated into the curated Org-Ch development migration.
-- Source prerequisites were checked against the verified empty Org-Ch development database;
-- SQL syntax was parsed and the migration applied; pgTAP tests remain pending.

create schema if not exists hr_audit;

-- 1) Dedicated sensitive-access audit stream.
create table if not exists hr_audit.sensitive_access_events (
    id bigint generated always as identity primary key,
    tenant_id uuid not null references hr_core.tenants(id),
    actor_app_user_id uuid,
    event_key text not null,
    subject_type text not null,
    subject_id uuid not null,
    object_id uuid,
    file_version_id uuid,
    outcome text not null check (outcome in ('allowed','denied','error')),
    purpose text,
    policy_version text not null default '2.2',
    request_id text,
    source_ip inet,
    user_agent text,
    occurred_at timestamptz not null default now(),
    metadata jsonb not null default '{}'::jsonb,
    foreign key (tenant_id, actor_app_user_id)
      references hr_security.app_users(tenant_id, id)
);

create index if not exists ix_sensitive_access_tenant_time
  on hr_audit.sensitive_access_events(tenant_id, occurred_at desc);
create index if not exists ix_sensitive_access_subject
  on hr_audit.sensitive_access_events(tenant_id, subject_type, subject_id, occurred_at desc);
create index if not exists ix_sensitive_access_actor
  on hr_audit.sensitive_access_events(tenant_id, actor_app_user_id, occurred_at desc);

alter table hr_audit.sensitive_access_events enable row level security;

-- No direct authenticated write/read grants are added here.
-- Insert must happen through a narrowly granted server-side function.
-- Read is restricted to a separately permission-checked audit endpoint.

-- 2) File storage path uniqueness.
-- Before applying, detect and resolve existing duplicates:
-- SELECT storage_bucket, storage_object_path, count(*)
-- FROM hr_files.file_versions
-- GROUP BY 1,2 HAVING count(*) > 1;
create unique index if not exists uq_file_version_storage_object
  on hr_files.file_versions(storage_bucket, storage_object_path);

-- 3) Complete scope target shape validation.
-- Existing rows must be checked before validating this constraint.
alter table hr_security.data_scopes
  drop constraint if exists data_scopes_target_shape_v2;
alter table hr_security.data_scopes
  add constraint data_scopes_target_shape_v2 check (
    (scope_type = 'tenant'
      and company_id is null and org_unit_id is null and personnel_record_id is null)
    or
    (scope_type = 'company'
      and company_id is not null and org_unit_id is null and personnel_record_id is null)
    or
    (scope_type = 'org_unit'
      and company_id is not null and org_unit_id is not null and personnel_record_id is null)
    or
    (scope_type = 'personnel'
      and company_id is not null and org_unit_id is null and personnel_record_id is not null)
  ) not valid;

-- Validate only after correcting legacy rows:
-- ALTER TABLE hr_security.data_scopes VALIDATE CONSTRAINT data_scopes_target_shape_v2;

-- 4) Append-only enforcement for sensitive access log.
create or replace function hr_audit.reject_sensitive_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'sensitive access events are append-only';
end;
$$;

drop trigger if exists trg_sensitive_events_no_update on hr_audit.sensitive_access_events;
create trigger trg_sensitive_events_no_update
before update or delete on hr_audit.sensitive_access_events
for each row execute function hr_audit.reject_sensitive_event_mutation();

-- 5) Tenant-safe helper for current app user.
-- Mirrors baseline columns; verify auth schema and function ownership in target.
create or replace function hr_security.current_app_user_id_v2()
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
  limit 1
$$;

revoke all on function hr_security.current_app_user_id_v2() from public;
revoke all on function hr_security.current_app_user_id_v2() from anon;
grant execute on function hr_security.current_app_user_id_v2() to authenticated;

-- 6) Explicit TODOs, intentionally not generated as permissive policies:
-- a) Build authoritative permission/scope resolver after permission keys are frozen.
-- b) Add company-consistency triggers for org_units, positions and assignments.
-- c) Add owner registry for file_objects; reject unknown owner_schema/owner_table.
-- d) Add Storage policies only after resolver can validate file + owner record.
-- e) Add server-side API grants/RPC allowlist; keep internal tables unexposed.
-- f) Convert audit_events, permission_change_history, decisions, revisions,
--    notes and file_versions to append-only where applicable.
-- g) Add one-open-capacity-request partial unique index after status refactor.

-- pgTAP test skeleton is in HR_SOFT_RLS_Test_Plan_v2.2.md.

-- HR-SOFT Stage 5 / Proposed migration v0.2
-- Source Stage 5 proposal; adapted for the verified empty Org-Ch development database.
-- Assumes baseline v0.1 + supplemental v0.1 have been applied.
-- Review all existing data and run in a disposable development database first.

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
  when 'cancelled' then 'cancelled'
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
    'pending_approval','approved','rejected','awaiting_reapproval','cancelled'
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

-- POST-MIGRATION MANUAL VALIDATION:
-- 1. Validate all *_v02 foreign keys and CHECK constraints.
-- 2. Inspect orphan/duplicate records and the capacity partial unique index.
-- 3. Verify every file_objects row has exactly one recognized owner.
-- 4. Update API dual-write before relying on new capacity statuses.
-- 5. Add RLS policies only after permission resolver and tests are implemented.
-- 6. Run pgTAP plan and two-tenant integration suite.

-- HR-SOFT Stage 7 / v2.5
-- Source Stage 7 proposal; reviewed and incorporated into the Org-Ch development migration.

create schema if not exists hr_events;

create table if not exists hr_events.outbox_events (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  event_key text not null,
  aggregate_type text not null,
  aggregate_id uuid not null,
  payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default now(),
  available_at timestamptz not null default now(),
  attempts integer not null default 0 check (attempts >= 0),
  locked_at timestamptz,
  locked_by text,
  processed_at timestamptz,
  last_error text,
  idempotency_key text not null,
  unique (tenant_id, id),
  unique (tenant_id, idempotency_key)
);

create index if not exists ix_outbox_ready
  on hr_events.outbox_events(available_at, occurred_at)
  where processed_at is null;

alter table hr_events.outbox_events enable row level security;
-- No direct client grants; worker-only access via tightly scoped role/RPC.

create table if not exists hr_org.position_assignment_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references hr_core.tenants(id),
  assignment_id uuid not null,
  event_type text not null check (event_type in (
    'created','scheduled','activated','changed','ended','cancelled','corrected'
  )),
  actor_app_user_id uuid,
  recorded_at timestamptz not null default now(),
  effective_at timestamptz,
  reason text,
  before_state jsonb,
  after_state jsonb,
  correction_of_event_id bigint,
  request_id text,
  foreign key (tenant_id, assignment_id)
    references hr_org.position_assignments(tenant_id, id),
  foreign key (tenant_id, actor_app_user_id)
    references hr_security.app_users(tenant_id, id),
  foreign key (correction_of_event_id)
    references hr_org.position_assignment_events(id)
);

create index if not exists ix_assignment_events_history
  on hr_org.position_assignment_events(tenant_id, assignment_id, recorded_at desc);

alter table hr_org.position_assignment_events enable row level security;

create or replace function hr_audit.reject_temporal_event_mutation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  raise exception 'temporal event is append-only';
end;
$$;

drop trigger if exists trg_assignment_events_append_only
  on hr_org.position_assignment_events;
create trigger trg_assignment_events_append_only
before update or delete on hr_org.position_assignment_events
for each row execute function hr_audit.reject_temporal_event_mutation();

drop trigger if exists trg_outbox_events_no_delete
  on hr_events.outbox_events;
create trigger trg_outbox_events_no_delete
before delete on hr_events.outbox_events
for each row execute function hr_audit.reject_temporal_event_mutation();

-- TODO:
-- 1) Add position_assignments recorded/effective columns and correction reference.
-- 2) Implement command functions with row locks and permission resolver.
-- 3) Implement outbox worker role and SKIP LOCKED claim function.
-- 4) Add unique idempotency constraints for reminder event keys/date.
-- 5) Add assignment activation scheduler and manager-chain resolution.
-- 6) Add company timezone settings and timezone-aware due-time logic.
-- 7) Do not grant client access to outbox or temporal event tables.

-- HR-SOFT Stage 12 / proposed organization extension v0.3
-- Source Stage 12 proposal; corrected mapping: base values are not headcount capacity.
-- Depends on reviewed baseline v0.1 and company-safe
-- constraints proposed in Stage 5; incorporated in the curated Org-Ch development migration.

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
  approved_base_value numeric(14,3),
  temporary_base_value numeric(14,3),
  base_effective_date date,
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
  check (approved_base_value is null or approved_base_value >= 0),
  check (temporary_base_value is null or temporary_base_value >= 0),
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

-- TODO before use:
-- - Validate company-safe unique indexes from Stage 5 exist.
-- - Determine whether profile fields should be code tables or controlled text.
-- - Resolve organization reference semantics.
-- - Resolve candidate target type for succession.
-- - Add RLS and permission keys for each new table.
-- - Add append-only profile/succession event strategy.
-- - Add overlap rules for successor categories and profile effective periods.
-- - Do not grant direct table access to authenticated.

-- HR-SOFT Stage 13 / proposed user security extension v0.4
-- Source Stage 13 proposal; Auth integration and proxy trust still require review before public release.

-- Add account authentication identifiers. No plaintext password fields.
alter table hr_security.app_users
  add column if not exists ad_username text,
  add column if not exists auth_mode text not null default 'local';

alter table hr_security.app_users
  add constraint ck_app_users_auth_mode_v04
  check (auth_mode in ('local','active_directory','both')) not valid;

create unique index if not exists uq_app_users_tenant_ad_username
  on hr_security.app_users(tenant_id, lower(ad_username))
  where ad_username is not null;

-- Default group mapping: one default group per user per system.
create table if not exists hr_security.user_default_groups (
  tenant_id uuid not null references hr_core.tenants(id),
  app_user_id uuid not null,
  system_id uuid not null references hr_security.systems(id),
  group_id uuid not null,
  set_at timestamptz not null default now(),
  set_by uuid,
  archived_at timestamptz,
  primary key (tenant_id, app_user_id, system_id),
  foreign key (tenant_id, app_user_id)
    references hr_security.app_users(tenant_id, id),
  foreign key (tenant_id, group_id)
    references hr_security.user_groups(tenant_id, id),
  foreign key (tenant_id, set_by)
    references hr_security.app_users(tenant_id, id)
);

-- IP policy. `cidr` supports IPv4 and IPv6 networks.
create table if not exists hr_security.user_ip_rules (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  app_user_id uuid,
  network cidr not null,
  effect text not null check (effect in ('allow','deny')),
  valid_from timestamptz not null default now(),
  valid_to timestamptz,
  reason text not null,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  archived_at timestamptz,
  unique (tenant_id, id),
  foreign key (tenant_id, app_user_id)
    references hr_security.app_users(tenant_id, id),
  foreign key (tenant_id, created_by)
    references hr_security.app_users(tenant_id, id),
  check (valid_to is null or valid_to > valid_from)
);

create index if not exists ix_user_ip_rules_lookup
  on hr_security.user_ip_rules(tenant_id, app_user_id, effect, valid_from, valid_to)
  where archived_at is null;

-- Login event history. This table records identity-provider events, not secrets.
create table if not exists hr_audit.user_login_events (
  id bigint generated always as identity primary key,
  tenant_id uuid,
  app_user_id uuid,
  auth_user_id uuid,
  event_type text not null check (event_type in (
    'login_success','login_failure','logout','lockout',
    'password_reset_required','password_reset_completed',
    'ad_assertion_success','ad_assertion_failure'
  )),
  occurred_at timestamptz not null default now(),
  source_ip inet,
  user_agent text,
  provider text,
  outcome text not null check (outcome in ('success','failure','blocked')),
  failure_code text,
  request_id text,
  foreign key (tenant_id, app_user_id)
    references hr_security.app_users(tenant_id, id)
);

create index if not exists ix_login_events_tenant_time
  on hr_audit.user_login_events(tenant_id, occurred_at desc);
create index if not exists ix_login_events_user_time
  on hr_audit.user_login_events(tenant_id, app_user_id, occurred_at desc);

-- Access event log, separate from sensitive-access event stream.
create table if not exists hr_audit.user_access_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references hr_core.tenants(id),
  app_user_id uuid,
  event_key text not null,
  resource_type text,
  resource_id uuid,
  operation text,
  outcome text not null check (outcome in ('allowed','denied','error')),
  policy_version text,
  occurred_at timestamptz not null default now(),
  source_ip inet,
  user_agent text,
  request_id text,
  metadata jsonb not null default '{}'::jsonb,
  foreign key (tenant_id, app_user_id)
    references hr_security.app_users(tenant_id, id)
);

create index if not exists ix_access_events_tenant_time
  on hr_audit.user_access_events(tenant_id, occurred_at desc);

-- Bulletin board.
create table if not exists hr_notify.bulletins (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  title text not null,
  body text not null,
  display_on_login boolean not null default false,
  display_on_home boolean not null default false,
  display_on_monthly_performance boolean not null default false,
  starts_at timestamptz not null,
  ends_at timestamptz,
  prevent_repeat boolean not null default false,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  created_by uuid not null,
  archived_at timestamptz,
  unique (tenant_id, id),
  foreign key (tenant_id, created_by)
    references hr_security.app_users(tenant_id, id),
  check (ends_at is null or ends_at > starts_at),
  check (display_on_login or display_on_home or display_on_monthly_performance)
);

create unique index if not exists uq_bulletins_tenant_id
  on hr_notify.bulletins(tenant_id, id);

create table if not exists hr_notify.bulletin_acknowledgements (
  tenant_id uuid not null references hr_core.tenants(id),
  bulletin_id uuid not null,
  app_user_id uuid not null,
  acknowledged_at timestamptz not null default now(),
  placement text not null check (placement in (
    'login','home','monthly_performance'
  )),
  primary key (tenant_id, bulletin_id, app_user_id, placement),
  foreign key (tenant_id, bulletin_id)
    references hr_notify.bulletins(tenant_id, id),
  foreign key (tenant_id, app_user_id)
    references hr_security.app_users(tenant_id, id)
);

-- RLS enabled; no direct client grants are added by this draft.
alter table hr_security.user_default_groups enable row level security;
alter table hr_security.user_ip_rules enable row level security;
alter table hr_audit.user_login_events enable row level security;
alter table hr_audit.user_access_events enable row level security;
alter table hr_notify.bulletins enable row level security;
alter table hr_notify.bulletin_acknowledgements enable row level security;

-- TODO:
-- - Implement IP check in trusted auth/API gateway; do not trust spoofable headers.
-- - Implement AD/SSO identity broker and issuer/audience validation.
-- - Add append-only triggers for login/access event tables.
-- - Add policies and permission keys for each table.
-- - Decide if default group is per system or one global default; current proposal is per system.
-- - Add timezone-aware login schedule if that Admino feature is later confirmed.

-- HR-SOFT Stage 14 / proposed personnel extension v0.5
-- Source Stage 14 proposal; included in the curated Org-Ch development foundation.

-- Global reference catalogs based on the observed country/city forms.
create table if not exists hr_core.countries (
  id uuid primary key default gen_random_uuid(),
  country_code text,
  title text not null,
  iso_alpha2 char(2),
  iso_alpha3 char(3),
  iso_numeric char(3),
  is_active boolean not null default true,
  unique (id),
  unique (iso_alpha2),
  unique (iso_alpha3),
  unique (iso_numeric)
);

create table if not exists hr_core.cities (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references hr_core.countries(id),
  city_code text,
  title text not null,
  is_active boolean not null default true,
  unique (id),
  unique (country_id, city_code)
);

-- Person names remain in the base person record.
alter table hr_core.people
  add column if not exists first_name_en text,
  add column if not exists last_name_en text;

-- Private demographic details are separated from the basic directory row.
create table if not exists hr_sensitive.person_private_details (
  tenant_id uuid not null references hr_core.tenants(id),
  person_id uuid not null,
  father_name text,
  mother_name text,
  birth_date date,
  gender_code text,
  birth_city_id uuid references hr_core.cities(id),
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key (tenant_id, person_id),
  foreign key (tenant_id, person_id)
    references hr_core.people(tenant_id, id),
  foreign key (tenant_id, updated_by)
    references hr_security.app_users(tenant_id, id)
);

-- Private contact channel. Store ciphertext, not cleartext mobile.
create table if not exists hr_sensitive.person_contact_data (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  person_id uuid not null,
  mobile_ciphertext bytea,
  mobile_fingerprint text,
  mobile_last4 text,
  is_primary boolean not null default true,
  valid_from date not null default current_date,
  valid_to date,
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  foreign key (tenant_id, person_id)
    references hr_core.people(tenant_id, id),
  foreign key (tenant_id, created_by)
    references hr_security.app_users(tenant_id, id),
  check (valid_to is null or valid_to >= valid_from)
);

create index if not exists ix_person_contact_lookup
  on hr_sensitive.person_contact_data(tenant_id, mobile_fingerprint)
  where mobile_fingerprint is not null;

-- Add tenant-scoped access and append-only event history for employment changes.
create table if not exists hr_core.personnel_record_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references hr_core.tenants(id),
  personnel_record_id uuid not null,
  event_type text not null check (event_type in (
    'created','status_changed','employment_type_changed',
    'company_transfer_out','company_transfer_in',
    'ended','reactivated','corrected'
  )),
  recorded_at timestamptz not null default now(),
  effective_at timestamptz,
  actor_app_user_id uuid,
  reason text,
  before_state jsonb,
  after_state jsonb,
  foreign key (tenant_id, personnel_record_id)
    references hr_core.personnel_records(tenant_id, id),
  foreign key (tenant_id, actor_app_user_id)
    references hr_security.app_users(tenant_id, id)
);

create index if not exists ix_personnel_record_events_history
  on hr_core.personnel_record_events(tenant_id, personnel_record_id, recorded_at desc);

alter table hr_sensitive.person_private_details enable row level security;
alter table hr_sensitive.person_contact_data enable row level security;
alter table hr_core.personnel_record_events enable row level security;

-- Clean-install override: birth_date exists only in hr_sensitive.person_private_details.
-- No legacy people.birth_date column or backfill is created in this new project;
-- existing databases require a separate reviewed migration.

-- TODO:
-- - Decide whether country/city catalogs need source/import provenance.
-- - Define permitted gender codes and localization.
-- - Define mobile encryption/HMAC key management outside DB.
-- - Add sensitive permission keys and audit events for view/update.
-- - Add append-only trigger for personnel_record_events.
-- - Add migration path for legacy birth_date values.
-- - Do not create contract/order fields until their actual forms are analyzed.

-- HR-SOFT Stage 16 / SQL correction snippets v0.6
-- Stage 16 corrections incorporated after inspecting the empty Org-Ch schema.
-- These snippets correct proposal defects; they are not a full migration.

-- A) Bulletin composite FK target key.
create unique index if not exists uq_bulletins_tenant_id
  on hr_notify.bulletins(tenant_id, id);

-- B) Ensure default group belongs to selected system.
create unique index if not exists uq_user_groups_tenant_system_id
  on hr_security.user_groups(tenant_id, system_id, id);

alter table hr_security.user_default_groups
  add constraint fk_default_group_same_system_v06
  foreign key (tenant_id, system_id, group_id)
  references hr_security.user_groups(tenant_id, system_id, id)
  not valid;

-- C) Correct NULL-permissive file owner constraints.
alter table hr_files.file_objects
  add constraint ck_file_owner_not_null_v06
  check (owner_type is not null) not valid;

alter table hr_files.file_objects
  add constraint ck_file_owner_reference_v06
  check (
    (owner_type = 'capacity_request' and capacity_request_id is not null)
  ) not valid;

-- D) Remove default execute from SECURITY DEFINER trigger functions.
revoke all on function hr_audit.reject_mutation_append_only() from public;
revoke all on function hr_audit.reject_mutation_append_only() from anon;
revoke all on function hr_audit.reject_mutation_append_only() from authenticated;

revoke all on function hr_audit.reject_sensitive_event_mutation() from public;
revoke all on function hr_audit.reject_sensitive_event_mutation() from anon;
revoke all on function hr_audit.reject_sensitive_event_mutation() from authenticated;

revoke all on function hr_audit.reject_temporal_event_mutation() from public;
revoke all on function hr_audit.reject_temporal_event_mutation() from anon;
revoke all on function hr_audit.reject_temporal_event_mutation() from authenticated;

-- Validate constraints after data cleanup:
-- ALTER TABLE hr_security.user_default_groups VALIDATE CONSTRAINT fk_default_group_same_system_v06;
-- ALTER TABLE hr_files.file_objects VALIDATE CONSTRAINT ck_file_owner_not_null_v06;
-- ALTER TABLE hr_files.file_objects VALIDATE CONSTRAINT ck_file_owner_reference_v06;

-- Clean-install override: cancellation mapping is corrected; birth_date is stored in hr_sensitive.
-- No legacy rows existed, so no legacy-data backfill was required.

-- HR-SOFT | RLS lockdown foundation
-- Version 0.1 | source RLS design incorporated in the curated migration.
-- Source warning resolved: baseline and supplemental SQL were reviewed for empty Org-Ch development.
-- This migration deliberately uses default-deny for business tables.
-- It does NOT yet grant business-data access by company/org/personnel scope.

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
using (is_active = true);

-- No policies are created for companies, people, personnel, organization,
-- memberships, workflow, audit, files, notifications, or sensitive data.
-- With RLS enabled and no policy, authenticated users cannot access those
-- tables. Later migrations must add permission + data-scope-aware policies.

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
