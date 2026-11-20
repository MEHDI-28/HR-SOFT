-- HR-SOFT | Supplemental workflow, capacity, notification, file and sensitive data tables
-- Status: DESIGN ONLY. NOT EXECUTED.
-- Depends on HR_SOFT_Postgres_Baseline_v0.1.sql.

begin;

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

commit;
