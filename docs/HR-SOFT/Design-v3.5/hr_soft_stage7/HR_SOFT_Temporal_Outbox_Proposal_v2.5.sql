-- HR-SOFT Stage 7 / v2.5
-- DESIGN DRAFT ONLY. Requires schema review and migrations before use.

begin;

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

commit;

-- TODO:
-- 1) Add position_assignments recorded/effective columns and correction reference.
-- 2) Implement command functions with row locks and permission resolver.
-- 3) Implement outbox worker role and SKIP LOCKED claim function.
-- 4) Add unique idempotency constraints for reminder event keys/date.
-- 5) Add assignment activation scheduler and manager-chain resolution.
-- 6) Add company timezone settings and timezone-aware due-time logic.
-- 7) Do not grant client access to outbox or temporal event tables.
