-- Keep the privileged one-time bootstrap implementation outside the exposed PostgREST schema.
ALTER FUNCTION public.hr_bootstrap_first_admin(text,text,text,text,text) SET SCHEMA hr_internal;
ALTER FUNCTION hr_internal.hr_bootstrap_first_admin(text,text,text,text,text) RENAME TO bootstrap_first_admin_impl;
REVOKE ALL ON SCHEMA hr_internal FROM public, anon, authenticated;
GRANT USAGE ON SCHEMA hr_internal TO authenticated;
REVOKE ALL ON FUNCTION hr_internal.bootstrap_first_admin_impl(text,text,text,text,text) FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION hr_internal.bootstrap_first_admin_impl(text,text,text,text,text) TO authenticated;
CREATE OR REPLACE FUNCTION public.hr_bootstrap_first_admin(
  p_token text, p_tenant_key text, p_tenant_name text, p_company_code text, p_company_name text
) RETURNS jsonb
LANGUAGE sql
SECURITY INVOKER
SET search_path = ''
AS $$ SELECT hr_internal.bootstrap_first_admin_impl($1,$2,$3,$4,$5); $$;
REVOKE ALL ON FUNCTION public.hr_bootstrap_first_admin(text,text,text,text,text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.hr_bootstrap_first_admin(text,text,text,text,text) TO authenticated;
NOTIFY pgrst, 'reload schema';
