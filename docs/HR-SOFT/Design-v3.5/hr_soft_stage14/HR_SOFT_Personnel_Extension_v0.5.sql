-- HR-SOFT Stage 14 / proposed personnel extension v0.5
-- DESIGN DRAFT ONLY. No production execution.

begin;

-- Global reference catalogs based on the observed country/city forms.
create table if not exists hr_core.countries (
  id uuid primary key default gen_random_uuid(),
  country_code text,
  title text not null,
  iso_alpha2 char(2),
  iso_alpha3 char(3),
  iso_numeric char(3),
  is_active boolean not null default true,
  unique (id),
  unique (iso_alpha2),
  unique (iso_alpha3),
  unique (iso_numeric)
);

create table if not exists hr_core.cities (
  id uuid primary key default gen_random_uuid(),
  country_id uuid not null references hr_core.countries(id),
  city_code text,
  title text not null,
  is_active boolean not null default true,
  unique (id),
  unique (country_id, city_code)
);

-- Person names remain in the base person record.
alter table hr_core.people
  add column if not exists first_name_en text,
  add column if not exists last_name_en text;

-- Private demographic details are separated from the basic directory row.
create table if not exists hr_sensitive.person_private_details (
  tenant_id uuid not null references hr_core.tenants(id),
  person_id uuid not null,
  father_name text,
  mother_name text,
  birth_date date,
  gender_code text,
  birth_city_id uuid references hr_core.cities(id),
  updated_at timestamptz not null default now(),
  updated_by uuid,
  primary key (tenant_id, person_id),
  foreign key (tenant_id, person_id)
    references hr_core.people(tenant_id, id),
  foreign key (tenant_id, updated_by)
    references hr_security.app_users(tenant_id, id)
);

-- Private contact channel. Store ciphertext, not cleartext mobile.
create table if not exists hr_sensitive.person_contact_data (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references hr_core.tenants(id),
  person_id uuid not null,
  mobile_ciphertext bytea,
  mobile_fingerprint text,
  mobile_last4 text,
  is_primary boolean not null default true,
  valid_from date not null default current_date,
  valid_to date,
  created_at timestamptz not null default now(),
  created_by uuid,
  unique (tenant_id, id),
  foreign key (tenant_id, person_id)
    references hr_core.people(tenant_id, id),
  foreign key (tenant_id, created_by)
    references hr_security.app_users(tenant_id, id),
  check (valid_to is null or valid_to >= valid_from)
);

create index if not exists ix_person_contact_lookup
  on hr_sensitive.person_contact_data(tenant_id, mobile_fingerprint)
  where mobile_fingerprint is not null;

-- Add tenant-scoped access and append-only event history for employment changes.
create table if not exists hr_core.personnel_record_events (
  id bigint generated always as identity primary key,
  tenant_id uuid not null references hr_core.tenants(id),
  personnel_record_id uuid not null,
  event_type text not null check (event_type in (
    'created','status_changed','employment_type_changed',
    'company_transfer_out','company_transfer_in',
    'ended','reactivated','corrected'
  )),
  recorded_at timestamptz not null default now(),
  effective_at timestamptz,
  actor_app_user_id uuid,
  reason text,
  before_state jsonb,
  after_state jsonb,
  foreign key (tenant_id, personnel_record_id)
    references hr_core.personnel_records(tenant_id, id),
  foreign key (tenant_id, actor_app_user_id)
    references hr_security.app_users(tenant_id, id)
);

create index if not exists ix_personnel_record_events_history
  on hr_core.personnel_record_events(tenant_id, personnel_record_id, recorded_at desc);

alter table hr_sensitive.person_private_details enable row level security;
alter table hr_sensitive.person_contact_data enable row level security;
alter table hr_core.personnel_record_events enable row level security;

-- Legacy hr_core.people.birth_date is retained during transition.
-- After data migration and all API consumers switch to person_private_details,
-- deprecate it in a later migration; do not drop in this proposal.

commit;

-- TODO:
-- - Decide whether country/city catalogs need source/import provenance.
-- - Define permitted gender codes and localization.
-- - Define mobile encryption/HMAC key management outside DB.
-- - Add sensitive permission keys and audit events for view/update.
-- - Add append-only trigger for personnel_record_events.
-- - Add migration path for legacy birth_date values.
-- - Do not create contract/order fields until their actual forms are analyzed.
