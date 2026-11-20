-- HR-SOFT: expose only invoker wrappers; private implementations remain SECURITY DEFINER.
alter function public.hr_admin_get_context_v1() security invoker;
alter function public.hr_org_get_admin_snapshot_v1(uuid,date) security invoker;
grant usage on schema hr_internal to authenticated;
grant execute on function hr_internal.hr_admin_get_context_impl() to authenticated;
grant execute on function hr_internal.hr_org_get_admin_snapshot_impl(uuid,date) to authenticated;
revoke all on function hr_internal.hr_admin_get_context_impl() from public, anon;
revoke all on function hr_internal.hr_org_get_admin_snapshot_impl(uuid,date) from public, anon;
