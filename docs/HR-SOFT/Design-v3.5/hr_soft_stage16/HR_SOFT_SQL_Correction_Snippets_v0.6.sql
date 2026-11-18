-- HR-SOFT Stage 16 / SQL correction snippets v0.6
-- Apply only to a disposable DB after inspecting actual schema.
-- These snippets correct proposal defects; they are not a full migration.

begin;

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

commit;

-- Validate constraints after data cleanup:
-- ALTER TABLE hr_security.user_default_groups VALIDATE CONSTRAINT fk_default_group_same_system_v06;
-- ALTER TABLE hr_files.file_objects VALIDATE CONSTRAINT ck_file_owner_not_null_v06;
-- ALTER TABLE hr_files.file_objects VALIDATE CONSTRAINT ck_file_owner_reference_v06;

-- NOTE: cancellation status mapping and people.birth_date backfill are NOT
-- automated here; they require inspecting real rows and preserving history.
