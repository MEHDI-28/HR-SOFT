-- HR-SOFT Org-Ch follow-up hardening
-- Fix extension placement and SECURITY INVOKER diagnostic; index uncovered FK columns.
alter extension citext set schema extensions;

create or replace function public.hr_session_status()
returns table (is_authenticated boolean, is_provisioned boolean)
language sql
stable
security invoker
set search_path = ''
as $$
  select auth.uid() is not null,
         exists (select 1 from hr_security.app_users au
                 where au.auth_user_id = auth.uid() and au.status = 'active');
$$;
revoke all on function public.hr_session_status() from public, anon;
grant execute on function public.hr_session_status() to authenticated;

drop index if exists hr_notify.uq_bulletins_tenant_id;
drop index if exists hr_security.uq_user_groups_tenant_system_id;

create index if not exists "ix_fk_user_access_events_f75c5996" on "hr_audit"."user_access_events" ("tenant_id", "app_user_id");
create index if not exists "ix_fk_personnel_record_events_d3f663cc" on "hr_core"."personnel_record_events" ("tenant_id", "actor_app_user_id");
create index if not exists "ix_fk_export_job_items_9e84d502" on "hr_files"."export_job_items" ("tenant_id", "file_version_id");
create index if not exists "ix_fk_export_jobs_36c310cb" on "hr_files"."export_jobs" ("tenant_id", "created_by");
create index if not exists "ix_fk_export_jobs_6f5d58d2" on "hr_files"."export_jobs" ("tenant_id", "request_id");
create index if not exists "ix_fk_file_objects_191e4627" on "hr_files"."file_objects" ("tenant_id", "uploaded_by");
create index if not exists "ix_fk_file_objects_383f2336" on "hr_files"."file_objects" ("tenant_id", "capacity_request_id");
create index if not exists "ix_fk_file_versions_678a0291" on "hr_files"."file_versions" ("tenant_id", "uploaded_by");
create index if not exists "ix_fk_bulletin_acknowledgements_ae18a114" on "hr_notify"."bulletin_acknowledgements" ("tenant_id", "app_user_id");
create index if not exists "ix_fk_bulletins_482dbb89" on "hr_notify"."bulletins" ("tenant_id", "created_by");
create index if not exists "ix_fk_duties_1be02d8e" on "hr_org"."duties" ("tenant_id", "created_by");
create index if not exists "ix_fk_offices_ee2c171e" on "hr_org"."offices" ("tenant_id", "created_by");
create index if not exists "ix_fk_org_units_2cce64c0" on "hr_org"."org_units" ("tenant_id", "company_id", "layer_id");
create index if not exists "ix_fk_org_units_432a1e77" on "hr_org"."org_units" ("tenant_id", "layer_id");
create index if not exists "ix_fk_org_units_d55c7c0d" on "hr_org"."org_units" ("tenant_id", "parent_unit_id");
create index if not exists "ix_fk_position_assignment_events_90d6ff64" on "hr_org"."position_assignment_events" ("correction_of_event_id");
create index if not exists "ix_fk_position_assignment_events_2a0628e1" on "hr_org"."position_assignment_events" ("tenant_id", "actor_app_user_id");
create index if not exists "ix_fk_position_assignments_bd4f4e33" on "hr_org"."position_assignments" ("tenant_id", "company_id", "personnel_record_id");
create index if not exists "ix_fk_position_assignments_51dfed08" on "hr_org"."position_assignments" ("tenant_id", "company_id", "position_id");
create index if not exists "ix_fk_position_assignments_bd887e81" on "hr_org"."position_assignments" ("tenant_id", "company_id");
create index if not exists "ix_fk_position_duties_560b1233" on "hr_org"."position_duties" ("tenant_id", "company_id", "position_id");
create index if not exists "ix_fk_position_duties_2bfa6ad6" on "hr_org"."position_duties" ("tenant_id", "created_by");
create index if not exists "ix_fk_position_duties_26b7062e" on "hr_org"."position_duties" ("tenant_id", "duty_id");
create index if not exists "ix_fk_position_office_assignments_4aabd2b0" on "hr_org"."position_office_assignments" ("tenant_id", "company_id", "office_id");
create index if not exists "ix_fk_position_office_assignments_377e739c" on "hr_org"."position_office_assignments" ("tenant_id", "company_id", "position_id");
create index if not exists "ix_fk_position_office_assignments_11ff98ee" on "hr_org"."position_office_assignments" ("tenant_id", "created_by");
create index if not exists "ix_fk_position_profiles_1b4a250c" on "hr_org"."position_profiles" ("tenant_id", "company_id", "org_layer_id");
create index if not exists "ix_fk_position_profiles_a66350e3" on "hr_org"."position_profiles" ("tenant_id", "company_id", "position_id");
create index if not exists "ix_fk_position_profiles_8312975d" on "hr_org"."position_profiles" ("tenant_id", "company_id", "superior_position_id");
create index if not exists "ix_fk_position_profiles_64e65cf6" on "hr_org"."position_profiles" ("tenant_id", "recorded_by");
create index if not exists "ix_fk_position_relationships_93cd103d" on "hr_org"."position_relationships" ("tenant_id", "company_id", "from_position_id");
create index if not exists "ix_fk_position_relationships_35d39550" on "hr_org"."position_relationships" ("tenant_id", "company_id", "to_position_id");
create index if not exists "ix_fk_position_relationships_5f0ec38a" on "hr_org"."position_relationships" ("tenant_id", "from_position_id");
create index if not exists "ix_fk_position_relationships_c68da5fd" on "hr_org"."position_relationships" ("tenant_id", "to_position_id");
create index if not exists "ix_fk_positions_89e3074b" on "hr_org"."positions" ("tenant_id", "company_id", "organizational_position_id");
create index if not exists "ix_fk_positions_7aa5db54" on "hr_org"."positions" ("tenant_id", "company_id", "superior_position_id");
create index if not exists "ix_fk_positions_266735ab" on "hr_org"."positions" ("tenant_id", "company_id", "org_unit_id");
create index if not exists "ix_fk_succession_candidates_37a3a529" on "hr_org"."succession_candidates" ("tenant_id", "company_id", "candidate_personnel_record_id");
create index if not exists "ix_fk_succession_candidates_4f4efcf7" on "hr_org"."succession_candidates" ("tenant_id", "company_id", "target_position_id");
create index if not exists "ix_fk_succession_candidates_7f9ba766" on "hr_org"."succession_candidates" ("tenant_id", "recorded_by");
create index if not exists "ix_fk_app_users_4f548f47" on "hr_security"."app_users" ("tenant_id", "person_id");
create index if not exists "ix_fk_data_scopes_469a4ef5" on "hr_security"."data_scopes" ("tenant_id", "company_id");
create index if not exists "ix_fk_data_scopes_81e4e493" on "hr_security"."data_scopes" ("tenant_id", "org_unit_id");
create index if not exists "ix_fk_data_scopes_c9b2360a" on "hr_security"."data_scopes" ("tenant_id", "personnel_record_id");
create index if not exists "ix_fk_data_scopes_576acba6" on "hr_security"."data_scopes" ("tenant_id", "company_id", "org_unit_id");
create index if not exists "ix_fk_data_scopes_d664083f" on "hr_security"."data_scopes" ("tenant_id", "company_id", "personnel_record_id");
create index if not exists "ix_fk_group_permission_rules_15a57412" on "hr_security"."group_permission_rules" ("system_id", "permission_id");
create index if not exists "ix_fk_group_permission_rules_5cfc2893" on "hr_security"."group_permission_rules" ("tenant_id", "system_id", "group_id");
create index if not exists "ix_fk_group_scope_assignments_ee7d74ed" on "hr_security"."group_scope_assignments" ("tenant_id", "group_id");
create index if not exists "ix_fk_group_scope_assignments_585ea17e" on "hr_security"."group_scope_assignments" ("tenant_id", "scope_id");
create index if not exists "ix_fk_temporary_access_5b401188" on "hr_security"."temporary_access" ("system_id", "permission_id");
create index if not exists "ix_fk_temporary_access_5a5af65d" on "hr_security"."temporary_access" ("tenant_id", "app_user_id");
create index if not exists "ix_fk_temporary_access_84d0e361" on "hr_security"."temporary_access" ("tenant_id", "approved_by");
create index if not exists "ix_fk_temporary_access_0f6f4366" on "hr_security"."temporary_access" ("tenant_id", "created_by");
create index if not exists "ix_fk_temporary_access_d38c0b86" on "hr_security"."temporary_access" ("tenant_id", "scope_id");
create index if not exists "ix_fk_user_default_groups_719cde97" on "hr_security"."user_default_groups" ("tenant_id", "system_id", "group_id");
create index if not exists "ix_fk_user_default_groups_d71aa98a" on "hr_security"."user_default_groups" ("system_id");
create index if not exists "ix_fk_user_default_groups_4c256be5" on "hr_security"."user_default_groups" ("tenant_id", "group_id");
create index if not exists "ix_fk_user_default_groups_039105d2" on "hr_security"."user_default_groups" ("tenant_id", "set_by");
create index if not exists "ix_fk_user_groups_ca0269b6" on "hr_security"."user_groups" ("system_id");
create index if not exists "ix_fk_user_ip_rules_3baf5c4a" on "hr_security"."user_ip_rules" ("tenant_id", "created_by");
create index if not exists "ix_fk_bank_accounts_67efa44c" on "hr_sensitive"."bank_accounts" ("tenant_id", "created_by");
create index if not exists "ix_fk_bank_accounts_6285c054" on "hr_sensitive"."bank_accounts" ("tenant_id", "personnel_record_id");
create index if not exists "ix_fk_identity_data_aa04fb83" on "hr_sensitive"."identity_data" ("tenant_id", "updated_by");
create index if not exists "ix_fk_person_contact_data_5b4cc5c4" on "hr_sensitive"."person_contact_data" ("tenant_id", "created_by");
create index if not exists "ix_fk_person_contact_data_736aca2d" on "hr_sensitive"."person_contact_data" ("tenant_id", "person_id");
create index if not exists "ix_fk_person_private_details_ad330d24" on "hr_sensitive"."person_private_details" ("birth_city_id");
create index if not exists "ix_fk_person_private_details_4c1ad913" on "hr_sensitive"."person_private_details" ("tenant_id", "updated_by");
create index if not exists "ix_fk_capacity_change_requests_d5c60a28" on "hr_workflow"."capacity_change_requests" ("tenant_id", "approved_by");
create index if not exists "ix_fk_capacity_change_requests_bc37706e" on "hr_workflow"."capacity_change_requests" ("tenant_id", "executed_by");
create index if not exists "ix_fk_capacity_change_requests_5b180c89" on "hr_workflow"."capacity_change_requests" ("tenant_id", "requested_by");
create index if not exists "ix_fk_capacity_request_files_488f6f53" on "hr_workflow"."capacity_request_files" ("tenant_id", "attached_by");
create index if not exists "ix_fk_capacity_request_files_f345c219" on "hr_workflow"."capacity_request_files" ("tenant_id", "file_object_id");
create index if not exists "ix_fk_capacity_request_notes_5f9d1419" on "hr_workflow"."capacity_request_notes" ("tenant_id", "created_by");
create index if not exists "ix_fk_capacity_request_notes_f8766dac" on "hr_workflow"."capacity_request_notes" ("tenant_id", "request_id");
create index if not exists "ix_fk_capacity_request_revisions_b26d82b8" on "hr_workflow"."capacity_request_revisions" ("tenant_id", "edited_by");
create index if not exists "ix_fk_decisions_cd46ba71" on "hr_workflow"."decisions" ("tenant_id", "decided_by");
create index if not exists "ix_fk_decisions_de2ab0cc" on "hr_workflow"."decisions" ("tenant_id", "request_id");
create index if not exists "ix_fk_decisions_fb551209" on "hr_workflow"."decisions" ("tenant_id", "step_id");
create index if not exists "ix_fk_requests_4c118cbb" on "hr_workflow"."requests" ("tenant_id", "requester_app_user_id");
create index if not exists "ix_fk_steps_7071ff9c" on "hr_workflow"."steps" ("tenant_id", "approver_app_user_id");
create index if not exists "ix_fk_steps_ef850b36" on "hr_workflow"."steps" ("tenant_id", "approver_group_id");
