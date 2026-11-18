-- HR-SOFT Stage 13 / proposed user security extension v0.4
-- DESIGN DRAFT ONLY. Review auth integration and proxy trust before use.

begin;

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
  foreign key (tenant_id, created_by)
    references hr_security.app_users(tenant_id, id),
  check (ends_at is null or ends_at > starts_at),
  check (display_on_login or display_on_home or display_on_monthly_performance)
);

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

commit;

-- TODO:
-- - Implement IP check in trusted auth/API gateway; do not trust spoofable headers.
-- - Implement AD/SSO identity broker and issuer/audience validation.
-- - Add append-only triggers for login/access event tables.
-- - Add policies and permission keys for each table.
-- - Decide if default group is per system or one global default; current proposal is per system.
-- - Add timezone-aware login schedule if that Admino feature is later confirmed.
