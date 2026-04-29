-- 0001-members.sql
-- ----------------------------------------------------------------------------
-- Sets up the `members` table for the mah-stack-starter.
-- One row per signed-up user; mirrors auth.users via id.
--
-- Reversible: every block is `IF NOT EXISTS` / `CREATE OR REPLACE` so re-runs
-- are no-ops. See the rollback note at the bottom.
-- ----------------------------------------------------------------------------

create table if not exists public.members (
  id uuid primary key references auth.users (id) on delete cascade,
  email text not null unique,
  tier text not null default 'tier1' check (tier in ('tier1', 'tier2', 'tier3')),
  display_name text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Updated-at trigger (standard pattern; reusable across all tables)
create or replace function public.update_updated_at_column()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists set_updated_at on public.members;
create trigger set_updated_at
  before update on public.members
  for each row execute function public.update_updated_at_column();

-- Auto-create a members row whenever a new auth user is created
-- (Supabase fires this trigger on the auth schema)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, pg_catalog
as $$
begin
  insert into public.members (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- Row-level security: each member can read/update their own row only.
alter table public.members enable row level security;

drop policy if exists "members_read_own" on public.members;
create policy "members_read_own"
  on public.members for select
  to authenticated
  using (id = (select auth.uid()));

drop policy if exists "members_update_own" on public.members;
create policy "members_update_own"
  on public.members for update
  to authenticated
  using (id = (select auth.uid()))
  with check (id = (select auth.uid()));

-- Service-role: full access (used by Edge Functions when needed)
drop policy if exists "members_service_role" on public.members;
create policy "members_service_role"
  on public.members for all
  to service_role
  using (true)
  with check (true);

-- ----------------------------------------------------------------------------
-- Rollback (manual; do not auto-run)
--   drop policy if exists "members_service_role" on public.members;
--   drop policy if exists "members_update_own" on public.members;
--   drop policy if exists "members_read_own" on public.members;
--   drop trigger if exists on_auth_user_created on auth.users;
--   drop function if exists public.handle_new_user;
--   drop trigger if exists set_updated_at on public.members;
--   drop function if exists public.update_updated_at_column;
--   drop table if exists public.members;
-- ----------------------------------------------------------------------------
