-- HR-SOFT Stage 6 / v2.4
-- CONTRACT SKELETON ONLY. NOT DEPLOYABLE.
-- Do not grant this internal function to authenticated clients.
-- Resource context must be derived by a trusted wrapper after loading the row.

create schema if not exists hr_internal;

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
    matched_allow_count integer,
    matched_deny_count integer
)
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_app_user_id uuid;
    v_tenant_id uuid;
begin
    -- Resolve identity from Supabase Auth; never accept actor from caller.
    select au.id, au.tenant_id
      into v_app_user_id, v_tenant_id
    from hr_security.app_users au
    where au.auth_user_id = auth.uid()
      and au.status = 'active'
    limit 1;

    if v_app_user_id is null then
      return query select false, 'APP_USER_INACTIVE', '2.4', 0, 0;
      return;
    end if;

    if p_tenant_id is distinct from v_tenant_id then
      return query select false, 'TENANT_MISMATCH', '2.4', 0, 0;
      return;
    end if;

    -- TODO: implement exact system/group/membership validity.
    -- TODO: implement permission operation mapping:
    -- view -> permission rule exists and effect allow (no can_view column);
    -- add/edit/delete -> matching can_* = true.
    -- TODO: evaluate group scope allow/deny and descendant hierarchy.
    -- TODO: evaluate temporary_access allow/deny and its scope.
    -- TODO: deny in any valid group or temporary rule overrides every allow.
    -- TODO: require a non-empty explicit allow scope for every group allow.
    -- TODO: log sensitive access in the same trusted wrapper transaction.
    -- This placeholder deliberately returns deny until the resolver is complete.
    return query select false, 'PERMISSION_NOT_GRANTED', '2.4', 0, 0;
end;
$$;

revoke all on function hr_internal.evaluate_permission_context(
  text,text,uuid,uuid,uuid,uuid,timestamptz
) from public, anon, authenticated;

-- No RLS policy should call this placeholder. A production resolver must be
-- fully implemented, reviewed, and tested before any policy references it.
