# HR-SOFT — فرهنگ داده و موجودی Schema
## نسخه 2.8 | مرحله دهم

- تاریخ: ۱۸ نوامبر ۲۰۲۶
- مبنا: DDL نسخه 0.1 (baseline و supplemental).
- این سند فرهنگ داده نسخه اولیه است؛ با schema واقعی Supabase تطبیق داده نشده است.
- تعداد جداول استخراج‌شده از DDL: 35

## 1. قواعد خواندن
- نوع و قیدها از تعریف SQL اولیه استخراج شده‌اند.
- هر موردی که با `TODO` یا «نیازمند تصمیم» آمده، برای نهایی‌سازی باید بازبینی شود.
- ستون‌های افزوده‌شده در proposalهای بعدی در این فرهنگ داده اولیه نیستند، مگر در بخش تغییرات پیشنهادی.

## 2. نمای کلی schema
- `hr_core`: `tenants`, `companies`, `people`, `personnel_records`
- `hr_security`: `app_users`, `systems`, `user_groups`, `group_memberships`, `permissions`, `group_permission_rules`, `data_scopes`, `group_scope_assignments`, `temporary_access`
- `hr_org`: `org_layers`, `org_units`, `positions`, `position_relationships`, `position_assignments`
- `hr_audit`: `audit_events`, `permission_change_history`
- `hr_workflow`: `requests`, `steps`, `decisions`, `capacity_change_requests`, `capacity_request_revisions`, `capacity_request_notes`, `capacity_request_files`
- `hr_files`: `file_objects`, `file_versions`, `export_jobs`, `export_job_items`
- `hr_notify`: `user_preferences`, `notifications`
- `hr_sensitive`: `identity_data`, `bank_accounts`

## 3. جداول و ستون‌ها
### `hr_core.tenants`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_key` | `text not null unique` |
| `display_name` | `text not null` |
| `status` | `text not null default 'active'` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `archived_at` | `timestamptz` |
| `archived_by` | `uuid` |
| `archive_reason` | `text` |
| `or` | `(status <> 'archived' and archived_at is null)` |

### `hr_core.companies`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `parent_company_id` | `uuid` |
| `company_code` | `text not null` |
| `legal_name` | `text not null` |
| `display_name` | `text not null` |
| `status` | `text not null default 'active'` |
| `valid_from` | `date not null default current_date` |
| `valid_to` | `date` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `updated_at` | `timestamptz not null default now()` |
| `updated_by` | `uuid` |
| `archived_at` | `timestamptz` |
| `archived_by` | `uuid` |
| `archive_reason` | `text` |
| `references` | `hr_core.companies(tenant_id, id)` |
| `or` | `(status <> 'archived' and archived_at is null))` |

روابط:
- `(tenant_id, parent_company_id)` → `hr_core.companies(tenant_id, id)`

### `hr_core.people`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `first_name` | `text not null` |
| `last_name` | `text not null` |
| `first_name_en` | `text` |
| `last_name_en` | `text` |
| `father_name` | `text` |
| `birth_date` | `date` |
| `gender_code` | `text` |
| `birthplace_code` | `text` |
| `mobile_e164` | `text` |
| `status` | `text not null default 'active'` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `updated_at` | `timestamptz not null default now()` |
| `updated_by` | `uuid` |
| `archived_at` | `timestamptz` |
| `archived_by` | `uuid` |
| `archive_reason` | `text` |
| `or` | `(status <> 'archived' and archived_at is null))` |

### `hr_core.personnel_records`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `person_id` | `uuid not null` |
| `company_id` | `uuid not null` |
| `personnel_no` | `text not null` |
| `employment_status` | `text not null default 'active'` |
| `employment_type_code` | `text` |
| `valid_from` | `date not null default current_date` |
| `valid_to` | `date` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `archived_at` | `timestamptz` |
| `archived_by` | `uuid` |
| `archive_reason` | `text` |
| `references` | `hr_core.people(tenant_id, id)` |
| `references` | `hr_core.companies(tenant_id, id)` |

روابط:
- `(tenant_id, person_id)` → `hr_core.people(tenant_id, id)`
- `(tenant_id, company_id)` → `hr_core.companies(tenant_id, id)`

### `hr_security.app_users`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `auth_user_id` | `uuid not null unique references auth.users(id)` |
| `person_id` | `uuid` |
| `username` | `citext` |
| `status` | `text not null default 'active'` |
| `force_password_change` | `boolean not null default false` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `archived_at` | `timestamptz` |
| `archived_by` | `uuid` |
| `archive_reason` | `text` |
| `references` | `hr_core.people(tenant_id, id)` |
| `or` | `(status <> 'archived' and archived_at is null))` |

روابط:
- `(tenant_id, person_id)` → `hr_core.people(tenant_id, id)`

### `hr_org.org_layers`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `company_id` | `uuid not null` |
| `layer_code` | `text not null` |
| `title` | `text not null` |
| `sort_order` | `integer not null default 0` |
| `is_active` | `boolean not null default true` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `references` | `hr_core.companies(tenant_id, id)` |

روابط:
- `(tenant_id, company_id)` → `hr_core.companies(tenant_id, id)`

### `hr_org.org_units`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `company_id` | `uuid not null` |
| `layer_id` | `uuid` |
| `parent_unit_id` | `uuid` |
| `unit_code` | `text not null` |
| `title` | `text not null` |
| `unit_type_code` | `text` |
| `is_visible` | `boolean not null default true` |
| `is_active` | `boolean not null default true` |
| `valid_from` | `date not null default current_date` |
| `valid_to` | `date` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `archived_at` | `timestamptz` |
| `archived_by` | `uuid` |
| `archive_reason` | `text` |
| `references` | `hr_core.companies(tenant_id, id)` |
| `references` | `hr_org.org_layers(tenant_id, id)` |
| `references` | `hr_org.org_units(tenant_id, id)` |

روابط:
- `(tenant_id, company_id)` → `hr_core.companies(tenant_id, id)`
- `(tenant_id, layer_id)` → `hr_org.org_layers(tenant_id, id)`
- `(tenant_id, parent_unit_id)` → `hr_org.org_units(tenant_id, id)`

### `hr_org.positions`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `company_id` | `uuid not null` |
| `org_unit_id` | `uuid not null` |
| `position_code` | `text not null` |
| `title` | `text not null` |
| `superior_position_id` | `uuid` |
| `approved_capacity` | `integer not null default 1 check (approved_capacity >= 0)` |
| `is_active` | `boolean not null default true` |
| `valid_from` | `date not null default current_date` |
| `valid_to` | `date` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `archived_at` | `timestamptz` |
| `archived_by` | `uuid` |
| `archive_reason` | `text` |
| `references` | `hr_core.companies(tenant_id, id)` |
| `references` | `hr_org.org_units(tenant_id, id)` |
| `references` | `hr_org.positions(tenant_id, id)` |

روابط:
- `(tenant_id, company_id)` → `hr_core.companies(tenant_id, id)`
- `(tenant_id, org_unit_id)` → `hr_org.org_units(tenant_id, id)`
- `(tenant_id, superior_position_id)` → `hr_org.positions(tenant_id, id)`

### `hr_org.position_relationships`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `from_position_id` | `uuid not null` |
| `to_position_id` | `uuid not null` |
| `relationship_type` | `text not null` |
| `valid_from` | `date not null` |
| `valid_to` | `date` |
| `description` | `text` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `references` | `hr_org.positions(tenant_id, id)` |
| `references` | `hr_org.positions(tenant_id, id)` |

روابط:
- `(tenant_id, from_position_id)` → `hr_org.positions(tenant_id, id)`
- `(tenant_id, to_position_id)` → `hr_org.positions(tenant_id, id)`

### `hr_org.position_assignments`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `company_id` | `uuid not null` |
| `position_id` | `uuid not null` |
| `personnel_record_id` | `uuid not null` |
| `assignment_type` | `text not null default 'primary'` |
| `status` | `text not null default 'scheduled'` |
| `valid_from` | `date not null` |
| `valid_to` | `date` |
| `recorded_at` | `timestamptz not null default now()` |
| `recorded_by` | `uuid` |
| `reason` | `text` |
| `ended_at` | `timestamptz` |
| `ended_by` | `uuid` |
| `cancellation_reason` | `text` |
| `references` | `hr_core.companies(tenant_id, id)` |
| `references` | `hr_org.positions(tenant_id, id)` |
| `references` | `hr_core.personnel_records(tenant_id, id)` |

روابط:
- `(tenant_id, company_id)` → `hr_core.companies(tenant_id, id)`
- `(tenant_id, position_id)` → `hr_org.positions(tenant_id, id)`
- `(tenant_id, personnel_record_id)` → `hr_core.personnel_records(tenant_id, id)`

### `hr_security.systems`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `system_key` | `text not null unique` |
| `title` | `text not null` |
| `is_active` | `boolean not null default true` |

### `hr_security.user_groups`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `system_id` | `uuid not null references hr_security.systems(id)` |
| `group_key` | `text not null` |
| `title` | `text not null` |
| `is_active` | `boolean not null default true` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `archived_at` | `timestamptz` |
| `archived_by` | `uuid` |
| `archive_reason` | `text` |

### `hr_security.group_memberships`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `group_id` | `uuid not null` |
| `app_user_id` | `uuid not null` |
| `is_active` | `boolean not null default true` |
| `valid_from` | `timestamptz not null default now()` |
| `valid_to` | `timestamptz` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `ended_at` | `timestamptz` |
| `ended_by` | `uuid` |
| `references` | `hr_security.user_groups(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, group_id)` → `hr_security.user_groups(tenant_id, id)`
- `(tenant_id, app_user_id)` → `hr_security.app_users(tenant_id, id)`

### `hr_security.permissions`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `system_id` | `uuid not null references hr_security.systems(id)` |
| `permission_key` | `text not null` |
| `title` | `text not null` |
| `description` | `text` |

### `hr_security.group_permission_rules`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `group_id` | `uuid not null` |
| `permission_id` | `uuid not null references hr_security.permissions(id)` |
| `can_add` | `boolean not null default false` |
| `can_edit` | `boolean not null default false` |
| `can_delete` | `boolean not null default false` |
| `effect` | `text not null default 'allow'` |
| `changed_at` | `timestamptz not null default now()` |
| `changed_by` | `uuid` |
| `references` | `hr_security.user_groups(tenant_id, id)` |

روابط:
- `(tenant_id, group_id)` → `hr_security.user_groups(tenant_id, id)`

### `hr_security.data_scopes`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `scope_type` | `text not null` |
| `company_id` | `uuid` |
| `org_unit_id` | `uuid` |
| `personnel_record_id` | `uuid` |
| `include_descendants` | `boolean not null default false` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `references` | `hr_core.companies(tenant_id, id)` |
| `references` | `hr_org.org_units(tenant_id, id)` |
| `references` | `hr_core.personnel_records(tenant_id, id)` |
| `or` | `(scope_type = 'company' and company_id is not null and org_unit_id is null and personnel_record_id is null)` |
| `or` | `(scope_type = 'org_unit' and org_unit_id is not null and personnel_record_id is null)` |
| `or` | `(scope_type = 'personnel' and personnel_record_id is not null)` |

روابط:
- `(tenant_id, company_id)` → `hr_core.companies(tenant_id, id)`
- `(tenant_id, org_unit_id)` → `hr_org.org_units(tenant_id, id)`
- `(tenant_id, personnel_record_id)` → `hr_core.personnel_records(tenant_id, id)`

### `hr_security.group_scope_assignments`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `group_id` | `uuid not null` |
| `scope_id` | `uuid not null` |
| `effect` | `text not null default 'allow'` |
| `valid_from` | `timestamptz not null default now()` |
| `valid_to` | `timestamptz` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `references` | `hr_security.user_groups(tenant_id, id)` |
| `references` | `hr_security.data_scopes(tenant_id, id)` |

روابط:
- `(tenant_id, group_id)` → `hr_security.user_groups(tenant_id, id)`
- `(tenant_id, scope_id)` → `hr_security.data_scopes(tenant_id, id)`

### `hr_security.temporary_access`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `app_user_id` | `uuid not null` |
| `permission_id` | `uuid not null references hr_security.permissions(id)` |
| `scope_id` | `uuid` |
| `effect` | `text not null check (effect in ('allow', 'deny'))` |
| `starts_at` | `timestamptz not null` |
| `ends_at` | `timestamptz not null` |
| `reason` | `text not null` |
| `approved_by` | `uuid` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `references` | `hr_security.app_users(tenant_id, id)` |
| `references` | `hr_security.data_scopes(tenant_id, id)` |

روابط:
- `(tenant_id, app_user_id)` → `hr_security.app_users(tenant_id, id)`
- `(tenant_id, scope_id)` → `hr_security.data_scopes(tenant_id, id)`

### `hr_audit.audit_events`
| ستون | تعریف SQL |
|---|---|
| `id` | `bigint generated always as identity primary key` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `actor_app_user_id` | `uuid` |
| `event_type` | `text not null` |
| `entity_schema` | `text not null` |
| `entity_table` | `text not null` |
| `entity_id` | `uuid` |
| `occurred_at` | `timestamptz not null default now()` |
| `effective_at` | `timestamptz` |
| `reason` | `text` |
| `before_state` | `jsonb` |
| `after_state` | `jsonb` |
| `request_id` | `text` |
| `source_ip` | `inet` |
| `user_agent` | `text` |

### `hr_audit.permission_change_history`
| ستون | تعریف SQL |
|---|---|
| `id` | `bigint generated always as identity primary key` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `group_id` | `uuid` |
| `permission_id` | `uuid` |
| `old_values` | `jsonb not null` |
| `new_values` | `jsonb not null` |
| `changed_by` | `uuid` |
| `changed_at` | `timestamptz not null default now()` |
| `change_reason` | `text` |

### `hr_workflow.requests`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `request_no` | `text not null` |
| `request_type` | `text not null` |
| `subject` | `text not null` |
| `description` | `text` |
| `requester_app_user_id` | `uuid not null` |
| `status` | `text not null default 'draft'` |
| `submitted_at` | `timestamptz` |
| `completed_at` | `timestamptz` |
| `created_at` | `timestamptz not null default now()` |
| `updated_at` | `timestamptz not null default now()` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, requester_app_user_id)` → `hr_security.app_users(tenant_id, id)`

### `hr_workflow.steps`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `request_id` | `uuid not null` |
| `step_no` | `integer not null` |
| `approver_app_user_id` | `uuid` |
| `approver_group_id` | `uuid` |
| `status` | `text not null default 'pending'` |
| `assigned_at` | `timestamptz not null default now()` |
| `decided_at` | `timestamptz` |
| `decision_reason` | `text` |
| `references` | `hr_workflow.requests(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |
| `references` | `hr_security.user_groups(tenant_id, id)` |

روابط:
- `(tenant_id, request_id)` → `hr_workflow.requests(tenant_id, id)`
- `(tenant_id, approver_app_user_id)` → `hr_security.app_users(tenant_id, id)`
- `(tenant_id, approver_group_id)` → `hr_security.user_groups(tenant_id, id)`

### `hr_workflow.decisions`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `request_id` | `uuid not null` |
| `step_id` | `uuid` |
| `decision` | `text not null check (decision in ('approved','rejected','returned','cancelled'))` |
| `reason` | `text` |
| `decided_by` | `uuid not null` |
| `decided_at` | `timestamptz not null default now()` |
| `references` | `hr_workflow.requests(tenant_id, id)` |
| `references` | `hr_workflow.steps(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, request_id)` → `hr_workflow.requests(tenant_id, id)`
- `(tenant_id, step_id)` → `hr_workflow.steps(tenant_id, id)`
- `(tenant_id, decided_by)` → `hr_security.app_users(tenant_id, id)`

### `hr_workflow.capacity_change_requests`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `position_id` | `uuid not null` |
| `requested_by` | `uuid not null` |
| `old_capacity` | `integer not null check (old_capacity >= 0)` |
| `proposed_capacity` | `integer not null check (proposed_capacity >= 0)` |
| `approval_mode` | `text not null check (approval_mode in ('org_manager','system_admin'))` |
| `status` | `text not null default 'pending_approval'` |
| `execution_mode` | `text not null default 'immediate'` |
| `planned_execution_date` | `date` |
| `approved_by` | `uuid` |
| `approved_at` | `timestamptz` |
| `rejection_reason` | `text` |
| `cancellation_reason` | `text` |
| `executed_by` | `uuid` |
| `executed_at` | `timestamptz` |
| `created_at` | `timestamptz not null default now()` |
| `updated_at` | `timestamptz not null default now()` |
| `references` | `hr_org.positions(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, position_id)` → `hr_org.positions(tenant_id, id)`
- `(tenant_id, requested_by)` → `hr_security.app_users(tenant_id, id)`
- `(tenant_id, approved_by)` → `hr_security.app_users(tenant_id, id)`
- `(tenant_id, executed_by)` → `hr_security.app_users(tenant_id, id)`

### `hr_workflow.capacity_request_revisions`
| ستون | تعریف SQL |
|---|---|
| `id` | `bigint generated always as identity primary key` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `request_id` | `uuid not null` |
| `revision_no` | `integer not null` |
| `previous_values` | `jsonb not null` |
| `revised_values` | `jsonb not null` |
| `edited_by` | `uuid not null` |
| `edited_at` | `timestamptz not null default now()` |
| `edit_reason` | `text not null` |
| `approval_reset` | `boolean not null default true` |
| `references` | `hr_workflow.capacity_change_requests(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, request_id)` → `hr_workflow.capacity_change_requests(tenant_id, id)`
- `(tenant_id, edited_by)` → `hr_security.app_users(tenant_id, id)`

### `hr_workflow.capacity_request_notes`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `request_id` | `uuid not null` |
| `note_text` | `text not null` |
| `created_by` | `uuid not null` |
| `created_at` | `timestamptz not null default now()` |
| `references` | `hr_workflow.capacity_change_requests(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, request_id)` → `hr_workflow.capacity_change_requests(tenant_id, id)`
- `(tenant_id, created_by)` → `hr_security.app_users(tenant_id, id)`

### `hr_files.file_objects`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `owner_schema` | `text not null` |
| `owner_table` | `text not null` |
| `owner_id` | `uuid not null` |
| `file_category` | `text not null` |
| `display_title` | `text` |
| `description` | `text` |
| `original_filename` | `text not null` |
| `current_version_no` | `integer not null default 1` |
| `uploaded_by` | `uuid not null` |
| `uploaded_at` | `timestamptz not null default now()` |
| `is_archived` | `boolean not null default false` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, uploaded_by)` → `hr_security.app_users(tenant_id, id)`

### `hr_files.file_versions`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `file_object_id` | `uuid not null` |
| `version_no` | `integer not null` |
| `storage_bucket` | `text not null` |
| `storage_object_path` | `text not null` |
| `mime_type` | `text not null` |
| `file_size_bytes` | `bigint not null check (file_size_bytes >= 0)` |
| `checksum_sha256` | `text` |
| `original_filename` | `text not null` |
| `replacement_reason` | `text` |
| `uploaded_by` | `uuid not null` |
| `uploaded_at` | `timestamptz not null default now()` |
| `references` | `hr_files.file_objects(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, file_object_id)` → `hr_files.file_objects(tenant_id, id)`
- `(tenant_id, uploaded_by)` → `hr_security.app_users(tenant_id, id)`

### `hr_workflow.capacity_request_files`
| ستون | تعریف SQL |
|---|---|
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `request_id` | `uuid not null` |
| `file_object_id` | `uuid not null` |
| `attached_by` | `uuid not null` |
| `attached_at` | `timestamptz not null default now()` |
| `references` | `hr_workflow.capacity_change_requests(tenant_id, id)` |
| `references` | `hr_files.file_objects(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, request_id)` → `hr_workflow.capacity_change_requests(tenant_id, id)`
- `(tenant_id, file_object_id)` → `hr_files.file_objects(tenant_id, id)`
- `(tenant_id, attached_by)` → `hr_security.app_users(tenant_id, id)`

### `hr_notify.user_preferences`
| ستون | تعریف SQL |
|---|---|
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `app_user_id` | `uuid not null` |
| `sms_enabled` | `boolean not null default true` |
| `updated_at` | `timestamptz not null default now()` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, app_user_id)` → `hr_security.app_users(tenant_id, id)`

### `hr_notify.notifications`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `recipient_app_user_id` | `uuid not null` |
| `channel` | `text not null check (channel in ('in_app','sms'))` |
| `event_key` | `text not null` |
| `title` | `text not null` |
| `body` | `text not null` |
| `payload` | `jsonb not null default '{}'::jsonb` |
| `status` | `text not null default 'queued'` |
| `created_at` | `timestamptz not null default now()` |
| `sent_at` | `timestamptz` |
| `read_at` | `timestamptz` |
| `provider_message_id` | `text` |
| `failure_detail` | `text` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, recipient_app_user_id)` → `hr_security.app_users(tenant_id, id)`

### `hr_files.export_jobs`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `request_id` | `uuid not null` |
| `created_by` | `uuid not null` |
| `status` | `text not null default 'queued'` |
| `file_count` | `integer` |
| `estimated_size_bytes` | `bigint` |
| `actual_size_bytes` | `bigint` |
| `temporary_storage_path` | `text` |
| `created_at` | `timestamptz not null default now()` |
| `completed_at` | `timestamptz` |
| `expires_at` | `timestamptz` |
| `downloaded_at` | `timestamptz` |
| `failure_detail` | `text` |
| `references` | `hr_workflow.capacity_change_requests(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, request_id)` → `hr_workflow.capacity_change_requests(tenant_id, id)`
- `(tenant_id, created_by)` → `hr_security.app_users(tenant_id, id)`

### `hr_files.export_job_items`
| ستون | تعریف SQL |
|---|---|
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `export_job_id` | `uuid not null` |
| `file_version_id` | `uuid not null` |
| `archive_entry_name` | `text not null` |
| `references` | `hr_files.export_jobs(tenant_id, id)` |
| `references` | `hr_files.file_versions(tenant_id, id)` |

روابط:
- `(tenant_id, export_job_id)` → `hr_files.export_jobs(tenant_id, id)`
- `(tenant_id, file_version_id)` → `hr_files.file_versions(tenant_id, id)`

### `hr_sensitive.identity_data`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `person_id` | `uuid not null` |
| `national_id_ciphertext` | `bytea` |
| `national_id_fingerprint` | `text` |
| `passport_ciphertext` | `bytea` |
| `updated_at` | `timestamptz not null default now()` |
| `updated_by` | `uuid` |
| `references` | `hr_core.people(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, person_id)` → `hr_core.people(tenant_id, id)`
- `(tenant_id, updated_by)` → `hr_security.app_users(tenant_id, id)`

### `hr_sensitive.bank_accounts`
| ستون | تعریف SQL |
|---|---|
| `id` | `uuid primary key default gen_random_uuid()` |
| `tenant_id` | `uuid not null references hr_core.tenants(id)` |
| `personnel_record_id` | `uuid not null` |
| `bank_name` | `text` |
| `account_holder` | `text` |
| `iban_ciphertext` | `bytea` |
| `account_number_ciphertext` | `bytea` |
| `iban_last4` | `text` |
| `is_primary` | `boolean not null default false` |
| `valid_from` | `date not null default current_date` |
| `valid_to` | `date` |
| `created_at` | `timestamptz not null default now()` |
| `created_by` | `uuid` |
| `references` | `hr_core.personnel_records(tenant_id, id)` |
| `references` | `hr_security.app_users(tenant_id, id)` |

روابط:
- `(tenant_id, personnel_record_id)` → `hr_core.personnel_records(tenant_id, id)`
- `(tenant_id, created_by)` → `hr_security.app_users(tenant_id, id)`
