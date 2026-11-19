-- =========================================================
-- Creative Walks – Supabase Einrichtung (Version 2)
-- Fotos + Standort + Chats
-- In Supabase: SQL Editor → New query → alles einfügen → Run
-- Kann auch mehrmals ausgeführt werden, ohne etwas kaputt zu machen.
-- =========================================================

-- ---------- 1) BEITRÄGE (Bilder) ----------
create table if not exists public.posts (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  user_name   text not null check (char_length(user_name) between 1 and 30),
  quest       text not null check (char_length(quest) <= 40),
  caption     text check (char_length(caption) <= 200),
  image_path  text not null,
  x real,
  y real
);
-- Standort (wird von der App leicht ungenau gespeichert, ca. 30–80 m)
alter table public.posts add column if not exists lat double precision;
alter table public.posts add column if not exists lng double precision;

alter table public.posts enable row level security;
drop policy if exists "Beiträge sind für alle sichtbar" on public.posts;
drop policy if exists "Eigene Beiträge erstellen" on public.posts;
drop policy if exists "Eigene Beiträge löschen" on public.posts;
create policy "Beiträge sind für alle sichtbar" on public.posts for select using (true);
create policy "Eigene Beiträge erstellen" on public.posts for insert to authenticated with check (auth.uid() = user_id);
create policy "Eigene Beiträge löschen" on public.posts for delete to authenticated using (auth.uid() = user_id);

-- ---------- 2) CHAT-GRUPPEN ----------
create table if not exists public.chats (
  id          uuid primary key default gen_random_uuid(),
  created_at  timestamptz not null default now(),
  created_by  uuid default auth.uid() references auth.users on delete set null,
  name        text not null check (char_length(name) between 1 and 60),
  type        text not null default 'quest' check (type in ('quest','treffen')),
  art         text
);
alter table public.chats enable row level security;
drop policy if exists "Gruppen sind sichtbar" on public.chats;
drop policy if exists "Gruppen erstellen" on public.chats;
create policy "Gruppen sind sichtbar" on public.chats for select using (true);
create policy "Gruppen erstellen" on public.chats for insert to authenticated with check (auth.uid() = created_by);

-- Start-Gruppen (nur wenn noch keine Gruppen existieren)
insert into public.chats (name, type, art)
select * from (values
  ('Blau-Jäger:innen','quest','blau'),
  ('Collage Club','quest','formen'),
  ('Herbst-Schnitzeljagd','quest','herbst'),
  ('Sonntags-Spaziergang','treffen','natur')
) as v(name, type, art)
where not exists (select 1 from public.chats);

-- ---------- 3) NACHRICHTEN ----------
create table if not exists public.messages (
  id          bigint generated always as identity primary key,
  created_at  timestamptz not null default now(),
  chat_id     uuid not null references public.chats on delete cascade,
  user_id     uuid not null default auth.uid() references auth.users on delete cascade,
  user_name   text not null check (char_length(user_name) between 1 and 30),
  body        text check (char_length(body) <= 1000),
  image_path  text,
  check (body is not null or image_path is not null)
);
create index if not exists messages_chat_time on public.messages (chat_id, created_at);
alter table public.messages enable row level security;
drop policy if exists "Nachrichten sind sichtbar" on public.messages;
drop policy if exists "Eigene Nachrichten senden" on public.messages;
drop policy if exists "Eigene Nachrichten löschen" on public.messages;
create policy "Nachrichten sind sichtbar" on public.messages for select using (true);
create policy "Eigene Nachrichten senden" on public.messages for insert to authenticated with check (auth.uid() = user_id);
create policy "Eigene Nachrichten löschen" on public.messages for delete to authenticated using (auth.uid() = user_id);

-- ---------- 4) LIVE-UPDATES ----------
do $$ begin
  begin alter publication supabase_realtime add table public.posts;    exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.chats;    exception when duplicate_object then null; end;
  begin alter publication supabase_realtime add table public.messages; exception when duplicate_object then null; end;
end $$;

-- ---------- 5) FOTO-SPEICHER ----------
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('photos', 'photos', true, 3145728, array['image/jpeg','image/png','image/webp'])
on conflict (id) do nothing;

drop policy if exists "Fotos in eigenen Ordner hochladen" on storage.objects;
drop policy if exists "Eigene Fotos sehen" on storage.objects;
drop policy if exists "Eigene Fotos löschen" on storage.objects;
create policy "Fotos in eigenen Ordner hochladen" on storage.objects for insert to authenticated
  with check (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Eigene Fotos sehen" on storage.objects for select to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "Eigene Fotos löschen" on storage.objects for delete to authenticated
  using (bucket_id = 'photos' and (storage.foldername(name))[1] = auth.uid()::text);

-- ---------- 6) ZUGRIFFSRECHTE FÜR DIE APP ----------
-- (nötig, falls "Grant API access to new tables automatically" beim Projekt aus war)
grant usage on schema public to anon, authenticated;
grant select on public.posts, public.chats, public.messages to anon, authenticated;
grant insert, delete on public.posts, public.messages to authenticated;
grant insert on public.chats to authenticated;
grant usage, select on all sequences in schema public to authenticated;
