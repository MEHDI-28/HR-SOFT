-- HR-SOFT follow-up: snapshot implementation finalized with source-derived redaction.

CREATE OR REPLACE FUNCTION hr_internal.hr_org_get_admin_snapshot_impl(p_company_id uuid, p_effective_at date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  v_auth_user_id uuid := auth.uid();
  v_app_user_id uuid;
  v_tenant_id uuid;
  v_effective_date date := coalesce(p_effective_at, current_date);
  v_effective_ts timestamptz;
  v_company record;
  v_allowed boolean;
  v_company_view boolean;
  v_chart_view boolean;
  v_unit_company_view boolean;
  v_position_company_view boolean;
  v_relationship_company_view boolean;
  v_row record;
  v_org_layers jsonb := '[]'::jsonb;
  v_org_units jsonb := '[]'::jsonb;
  v_organizational_positions jsonb := '[]'::jsonb;
  v_positions jsonb := '[]'::jsonb;
  v_relationships jsonb := '[]'::jsonb;
  v_visible_layer_ids uuid[] := array[]::uuid[];
  v_visible_unit_ids uuid[] := array[]::uuid[];
  v_visible_org_position_ids uuid[] := array[]::uuid[];
  v_visible_position_ids uuid[] := array[]::uuid[];
  v_can_unit_any boolean := false;
  v_can_position_any boolean := false;
  v_can_relationship_any boolean := false;
begin
  if v_auth_user_id is null then
    raise exception using errcode = 'P0001', message = 'AUTH_REQUIRED';
  end if;

  if p_company_id is null then
    raise exception using errcode = 'P0001', message = 'INVALID_ARGUMENT';
  end if;

  v_app_user_id := hr_security.current_app_user_id();
  v_tenant_id := hr_security.current_tenant_id();

  if v_app_user_id is null or v_tenant_id is null then
    raise exception using errcode = 'P0001', message = 'APP_USER_INACTIVE';
  end if;

  select t.id into v_tenant_id
    from hr_core.tenants t
   where t.id = v_tenant_id
     and t.status = 'active'
     and t.archived_at is null;

  if v_tenant_id is null then
    raise exception using errcode = 'P0001', message = 'APP_USER_INACTIVE';
  end if;

  v_effective_ts := (v_effective_date::timestamp at time zone 'UTC');

  select c.id, c.company_code, c.legal_name, c.display_name
    into v_company
    from hr_core.companies c
   where c.id = p_company_id
     and c.tenant_id = v_tenant_id
     and c.status = 'active'
     and c.archived_at is null
     and c.valid_from <= v_effective_date
     and (c.valid_to is null or c.valid_to >= v_effective_date);

  if v_company.id is null then
    raise exception using errcode = 'P0001', message = 'RESOURCE_NOT_FOUND';
  end if;

  select coalesce(r.allowed, false) into v_company_view
    from hr_internal.evaluate_permission_context(
      'org.company.view', 'view', v_tenant_id, p_company_id,
      null, null, v_effective_ts
    ) r;

  select coalesce(r.allowed, false) into v_chart_view
    from hr_internal.evaluate_permission_context(
      'org.chart.view', 'view', v_tenant_id, p_company_id,
      null, null, v_effective_ts
    ) r;

  if not v_company_view or not v_chart_view then
    raise exception using errcode = 'P0001', message = 'PERMISSION_DENIED';
  end if;

  select coalesce(r.allowed, false) into v_unit_company_view
    from hr_internal.evaluate_permission_context(
      'org.unit.view', 'view', v_tenant_id, p_company_id,
      null, null, v_effective_ts
    ) r;

  select coalesce(r.allowed, false) into v_position_company_view
    from hr_internal.evaluate_permission_context(
      'org.position.view', 'view', v_tenant_id, p_company_id,
      null, null, v_effective_ts
    ) r;

  select coalesce(r.allowed, false) into v_relationship_company_view
    from hr_internal.evaluate_permission_context(
      'org.relationship.view', 'view', v_tenant_id, p_company_id,
      null, null, v_effective_ts
    ) r;

  if v_unit_company_view then
    for v_row in
      select l.id, l.layer_code, l.title, l.sort_order
        from hr_org.org_layers l
       where l.tenant_id = v_tenant_id
         and l.company_id = p_company_id
         and l.is_active
       order by l.sort_order, l.layer_code, l.id
    loop
      v_visible_layer_ids := array_append(v_visible_layer_ids, v_row.id);
      v_org_layers := v_org_layers || jsonb_build_array(
        jsonb_build_object(
          'id', v_row.id,
          'layer_code', v_row.layer_code,
          'title', v_row.title,
          'sort_order', v_row.sort_order
        )
      );
    end loop;
  end if;

  for v_row in
    select u.id
      from hr_org.org_units u
     where u.tenant_id = v_tenant_id
       and u.company_id = p_company_id
       and u.is_visible
       and u.is_active
       and u.archived_at is null
       and u.valid_from <= v_effective_date
       and (u.valid_to is null or u.valid_to >= v_effective_date)
     order by u.unit_code, u.id
  loop
    select coalesce(r.allowed, false) into v_allowed
      from hr_internal.evaluate_permission_context(
        'org.unit.view', 'view', v_tenant_id, p_company_id,
        v_row.id, null, v_effective_ts
      ) r;

    if v_allowed then
      v_visible_unit_ids := array_append(v_visible_unit_ids, v_row.id);
      v_can_unit_any := true;
    end if;
  end loop;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', u.id,
      'layer_id', case when u.layer_id = any(v_visible_layer_ids) then u.layer_id else null end,
      'parent_unit_id', case when u.parent_unit_id = any(v_visible_unit_ids) then u.parent_unit_id else null end,
      'unit_code', u.unit_code,
      'title', u.title,
      'unit_type_code', u.unit_type_code,
      'is_visible', u.is_visible,
      'is_active', u.is_active,
      'valid_from', u.valid_from,
      'valid_to', u.valid_to
    ) order by u.unit_code,u.id
  ), '[]'::jsonb)
  into v_org_units
  from hr_org.org_units u
  where u.tenant_id=v_tenant_id and u.company_id=p_company_id
    and u.id=any(v_visible_unit_ids);

  if v_position_company_view then
    for v_row in
      select op.id, op.position_key, op.title, op.priority, op.level_code
        from hr_org.organizational_positions op
       where op.tenant_id = v_tenant_id
         and op.company_id = p_company_id
         and op.is_visible
         and op.is_active
         and op.valid_from <= v_effective_date
         and (op.valid_to is null or op.valid_to >= v_effective_date)
       order by op.priority desc, op.position_key, op.id
    loop
      v_visible_org_position_ids := array_append(v_visible_org_position_ids, v_row.id);
      v_organizational_positions := v_organizational_positions || jsonb_build_array(
        jsonb_build_object(
          'id', v_row.id,
          'position_key', v_row.position_key,
          'title', v_row.title,
          'priority', v_row.priority,
          'level_code', v_row.level_code
        )
      );
    end loop;
  end if;

  for v_row in
    select p.id, p.org_unit_id
      from hr_org.positions p
     where p.tenant_id = v_tenant_id
       and p.company_id = p_company_id
       and p.is_active
       and p.archived_at is null
       and p.valid_from <= v_effective_date
       and (p.valid_to is null or p.valid_to >= v_effective_date)
       and p.org_unit_id = any(v_visible_unit_ids)
     order by p.position_code, p.id
  loop
    select coalesce(r.allowed, false) into v_allowed
      from hr_internal.evaluate_permission_context(
        'org.position.view', 'view', v_tenant_id, p_company_id,
        v_row.org_unit_id, null, v_effective_ts
      ) r;

    if v_allowed then
      v_visible_position_ids := array_append(v_visible_position_ids, v_row.id);
      v_can_position_any := true;
    end if;
  end loop;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', p.id,
      'org_unit_id', p.org_unit_id,
      'position_code', p.position_code,
      'title', p.title,
      'superior_position_id', case when p.superior_position_id = any(v_visible_position_ids) then p.superior_position_id else null end,
      'approved_capacity', p.approved_capacity,
      'organizational_position_id', case when p.organizational_position_id = any(v_visible_org_position_ids) then p.organizational_position_id else null end,
      'valid_from', p.valid_from,
      'valid_to', p.valid_to
    ) order by p.position_code,p.id
  ), '[]'::jsonb)
  into v_positions
  from hr_org.positions p
  where p.tenant_id=v_tenant_id and p.company_id=p_company_id
    and p.id=any(v_visible_position_ids);

  for v_row in
    select rel.id, rel.from_position_id, rel.to_position_id,
           rel.relationship_type, rel.description, rel.valid_from, rel.valid_to,
           pf.org_unit_id as from_org_unit_id, pt.org_unit_id as to_org_unit_id
      from hr_org.position_relationships rel
      join hr_org.positions pf
        on pf.tenant_id = rel.tenant_id
       and pf.company_id = rel.company_id
       and pf.id = rel.from_position_id
      join hr_org.positions pt
        on pt.tenant_id = rel.tenant_id
       and pt.company_id = rel.company_id
       and pt.id = rel.to_position_id
     where rel.tenant_id = v_tenant_id
       and rel.company_id = p_company_id
       and rel.valid_from <= v_effective_date
       and (rel.valid_to is null or rel.valid_to >= v_effective_date)
       and rel.from_position_id = any(v_visible_position_ids)
       and rel.to_position_id = any(v_visible_position_ids)
     order by rel.relationship_type, rel.id
  loop
    select coalesce(r.allowed, false) into v_allowed
      from hr_internal.evaluate_permission_context(
        'org.relationship.view', 'view', v_tenant_id, p_company_id,
        v_row.from_org_unit_id, null, v_effective_ts
      ) r;

    if v_allowed then
      select coalesce(r.allowed, false) into v_allowed
        from hr_internal.evaluate_permission_context(
          'org.relationship.view', 'view', v_tenant_id, p_company_id,
          v_row.to_org_unit_id, null, v_effective_ts
        ) r;
    end if;

    if v_allowed then
      v_can_relationship_any := true;
      v_relationships := v_relationships || jsonb_build_array(
        jsonb_build_object(
          'id', v_row.id,
          'from_position_id', v_row.from_position_id,
          'to_position_id', v_row.to_position_id,
          'relationship_type', v_row.relationship_type,
          'description', v_row.description,
          'valid_from', v_row.valid_from,
          'valid_to', v_row.valid_to
        )
      );
    end if;
  end loop;

  return jsonb_build_object(
    'contract_version', 1,
    'effective_date', v_effective_date,
    'company', jsonb_build_object(
      'id', v_company.id,
      'company_code', v_company.company_code,
      'legal_name', v_company.legal_name,
      'display_name', v_company.display_name
    ),
    'capabilities', jsonb_build_object(
      'company', v_company_view,
      'chart', v_chart_view,
      'unit', (v_unit_company_view or v_can_unit_any),
      'position', (v_position_company_view or v_can_position_any),
      'relationship', (v_relationship_company_view or v_can_relationship_any)
    ),
    'org_layers', v_org_layers,
    'org_units', v_org_units,
    'organizational_positions', v_organizational_positions,
    'positions', v_positions,
    'relationships', v_relationships
  );
exception
  when others then
    declare
      v_message text;
    begin
      get stacked diagnostics v_message = message_text;
      if v_message in ('AUTH_REQUIRED','APP_USER_INACTIVE','PERMISSION_DENIED','RESOURCE_NOT_FOUND','INVALID_ARGUMENT','INTERNAL_ERROR') then
        raise;
      end if;
      raise exception using errcode = 'P0001', message = 'INTERNAL_ERROR';
    end;
end;
$function$
