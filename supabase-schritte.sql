-- =========================================================
-- Creative Walks – Schritte aus Apple Health (Zusatz)
-- In Supabase: SQL Editor → New query → einfügen → Run
-- =========================================================
create table if not exists public.step_sync (
  code       text primary key check (char_length(code) between 12 and 64),
  steps      integer not null check (steps between 0 and 200000),
  day        date not null,
  updated_at timestamptz not null default now()
);
alter table public.step_sync enable row level security;
revoke all on public.step_sync from anon, authenticated;

-- Kurzbefehl schreibt die heutigen Schritte (nur über diese Funktion)
create or replace function public.set_steps(p_code text, p_steps numeric)
returns void language sql security definer set search_path = public as $$
  insert into public.step_sync (code, steps, day, updated_at)
  values (p_code, greatest(0, least(round(p_steps)::int, 200000)), (now() at time zone 'Europe/Berlin')::date, now())
  on conflict (code) do update set steps = excluded.steps, day = excluded.day, updated_at = now();
$$;

-- App liest die Schritte zum eigenen Code
create or replace function public.get_steps(p_code text)
returns table (steps integer, day date, updated_at timestamptz)
language sql stable security definer set search_path = public as $$
  select s.steps, s.day, s.updated_at from public.step_sync s where s.code = p_code;
$$;

revoke all on function public.set_steps(text, numeric) from public;
revoke all on function public.get_steps(text) from public;
grant execute on function public.set_steps(text, numeric) to anon, authenticated;
grant execute on function public.get_steps(text) to anon, authenticated;
