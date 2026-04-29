-- 0002-eoi.sql
-- ----------------------------------------------------------------------------
-- Sets up the `eoi_submissions` table — for "expression of interest" forms
-- where any visitor (not just signed-in users) can leave their email + a note.
-- The members table from 0001-members.sql must exist first.
-- ----------------------------------------------------------------------------

create table if not exists public.eoi_submissions (
  id uuid primary key default gen_random_uuid (),
  email text not null,
  note text,
  source text,
  created_at timestamptz not null default now()
);

-- Anonymous (anon-key) clients can INSERT (so the public form on your site
-- can submit without sign-in) but cannot SELECT (no leaking the list).
alter table public.eoi_submissions enable row level security;

drop policy if exists "eoi_anon_insert" on public.eoi_submissions;
create policy "eoi_anon_insert"
  on public.eoi_submissions for insert
  to anon, authenticated
  with check (true);

-- Only authenticated members at tier2 or above can read the list.
drop policy if exists "eoi_tier2_read" on public.eoi_submissions;
create policy "eoi_tier2_read"
  on public.eoi_submissions for select
  to authenticated
  using (
    exists (
      select 1 from public.members m
      where m.id = (select auth.uid())
        and m.tier in ('tier2', 'tier3')
    )
  );

drop policy if exists "eoi_service_role" on public.eoi_submissions;
create policy "eoi_service_role"
  on public.eoi_submissions for all
  to service_role
  using (true)
  with check (true);

-- ----------------------------------------------------------------------------
-- Rollback (manual)
--   drop policy if exists "eoi_service_role" on public.eoi_submissions;
--   drop policy if exists "eoi_tier2_read" on public.eoi_submissions;
--   drop policy if exists "eoi_anon_insert" on public.eoi_submissions;
--   drop table if exists public.eoi_submissions;
-- ----------------------------------------------------------------------------
