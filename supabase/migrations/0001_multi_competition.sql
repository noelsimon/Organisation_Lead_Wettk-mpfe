-- ============================================================
-- MIGRATION: Mehrere Wettkämpfe gleichzeitig
-- Für ein bereits laufendes Projekt (mit vorhandenen Daten) — einmalig
-- im SQL Editor ausführen, in dieser Reihenfolge (von oben nach unten).
-- Legt den bestehenden Kidscup-2026-Datensatz als ersten, standardmäßigen
-- Wettkampf an; niemand verliert dadurch Zugriff.
-- ============================================================

-- 1) Wettkämpfe-Tabellen
create table public.competitions (
  id          uuid primary key default gen_random_uuid(),
  slug        text unique not null,
  name        text not null,
  is_default  boolean not null default false,
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now()
);
alter table public.competitions enable row level security;

create table public.competition_members (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  profile_id     uuid not null references public.profiles(id) on delete cascade,
  primary key (competition_id, profile_id)
);
alter table public.competition_members enable row level security;

-- 2) Ersten Wettkampf für die bestehenden Daten anlegen
insert into public.competitions (slug, name, is_default)
values ('kidscup2026', 'Kidscup 2026', true);

-- 3) competition_id an bestehende Tabellen anhängen und befüllen
alter table public.plan_state add column competition_id uuid references public.competitions(id) on delete cascade;
alter table public.stands     add column competition_id uuid references public.competitions(id) on delete cascade;
alter table public.viewers    add column competition_id uuid references public.competitions(id) on delete cascade;
alter table public.tasks      add column competition_id uuid references public.competitions(id) on delete cascade;

update public.plan_state set competition_id = (select id from public.competitions where slug='kidscup2026');
update public.stands     set competition_id = (select id from public.competitions where slug='kidscup2026');
update public.viewers    set competition_id = (select id from public.competitions where slug='kidscup2026');
update public.tasks      set competition_id = (select id from public.competitions where slug='kidscup2026');

alter table public.plan_state alter column competition_id set not null;
alter table public.stands     alter column competition_id set not null;
alter table public.viewers    alter column competition_id set not null;
alter table public.tasks      alter column competition_id set not null;

-- 4) Primärschlüssel von plan_state/viewers erweitern (jetzt je Wettkampf eindeutig)
alter table public.plan_state drop constraint plan_state_pkey;
alter table public.plan_state add primary key (competition_id, key);

alter table public.viewers drop constraint viewers_pkey;
alter table public.viewers add primary key (competition_id, key);

-- 5) Alle bestehenden Profile dem Kidscup 2026 zuordnen (niemand verliert Zugriff)
insert into public.competition_members (competition_id, profile_id)
select (select id from public.competitions where slug='kidscup2026'), id from public.profiles
on conflict do nothing;

-- 6) Hilfsfunktionen (erst jetzt, da is_member competition_members und
--    task_competition_ok die neue Spalte tasks.competition_id braucht)
create or replace function public.is_member(c_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from public.competition_members where competition_id = c_id and profile_id = auth.uid());
$$;

create or replace function public.task_competition_ok(t_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1 from public.tasks t
    where t.id = t_id and (public.is_admin() or public.is_member(t.competition_id))
  );
$$;

-- competitions enthält keine sensiblen Daten (nur Name/Slug/Erstellt-von) und
-- muss auch VOR dem Login lesbar sein, damit ein Wettkampf-Link (?w=<slug>)
-- schon auf der Registrierungsmaske aufgelöst werden kann.
create policy "competitions: alle lesen" on public.competitions
  for select using (true);
create policy "competitions: Admin verwaltet" on public.competitions
  for all using (public.is_admin()) with check (public.is_admin());

create policy "competition_members: Admin verwaltet alle" on public.competition_members
  for all using (public.is_admin()) with check (public.is_admin());
create policy "competition_members: eigene Zeilen lesen" on public.competition_members
  for select using (profile_id = auth.uid());

-- Behebt einen Bug im bereits laufenden Aufgaben-Feature: ohne diese Policy
-- sah eine nicht-admin Person unter "Zugewiesen an" nur ihren eigenen Namen
-- (RLS blockte fremde profiles-Zeilen). Jetzt sichtbar für alle, die
-- mindestens einen Wettkampf gemeinsam haben.
create or replace function public.shares_competition_with(other uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1 from public.competition_members cm1
    join public.competition_members cm2 on cm1.competition_id = cm2.competition_id
    where cm1.profile_id = auth.uid() and cm2.profile_id = other
  );
$$;
create policy "profiles: Mitwettkämpfer sehen Basisdaten" on public.profiles
  for select using (public.shares_competition_with(id));

-- 7) Registrierungs-Trigger erweitern: legt bei Registrierung über einen
--    Wettkampf-Link (?w=...) automatisch auch die Mitgliedschaft an.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  comp_id uuid;
begin
  insert into public.profiles (id, email, full_name, category)
  values (
    new.id, new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
    coalesce((new.raw_user_meta_data->>'category')::user_category, 'buffet')
  )
  on conflict (id) do nothing;

  comp_id := nullif(new.raw_user_meta_data->>'competition_id','')::uuid;
  if comp_id is not null then
    insert into public.competition_members (competition_id, profile_id)
    values (comp_id, new.id)
    on conflict do nothing;
  end if;

  return new;
end;
$$;

-- 8) Bestehende Policies ersetzen (Wettkampf-Zugehörigkeit einbauen)
drop policy "plan_state: Freigegebene lesen alles" on public.plan_state;
drop policy "plan_state: Orga schreibt Klassen/Zeitplan" on public.plan_state;
drop policy "plan_state: Orga und Routenbau schreiben Texte" on public.plan_state;
drop policy "plan_state: Orga oder Routenbau legen Texte-Zeile an" on public.plan_state;

create policy "plan_state: Mitglieder oder Admin lesen" on public.plan_state
  for select using (public.is_admin() or (public.my_status() = 'approved' and public.is_member(competition_id)));
create policy "plan_state: Orga oder Admin schreibt Klassen/Zeitplan" on public.plan_state
  for all
  using (public.is_admin() or (public.my_status() = 'approved' and public.my_category() = 'orga' and public.is_member(competition_id) and key in ('cfg','quali','finale')))
  with check (public.is_admin() or (public.my_status() = 'approved' and public.my_category() = 'orga' and public.is_member(competition_id) and key in ('cfg','quali','finale')));
create policy "plan_state: Orga/Routenbau/Admin schreiben Texte" on public.plan_state
  for update
  using (public.is_admin() or (public.my_status() = 'approved' and key = 'texts' and public.my_category() in ('orga','routenbau') and public.is_member(competition_id)))
  with check (public.is_admin() or (public.my_status() = 'approved' and key = 'texts' and public.my_category() in ('orga','routenbau') and public.is_member(competition_id)));
create policy "plan_state: Orga/Routenbau/Admin legen Texte-Zeile an" on public.plan_state
  for insert
  with check (public.is_admin() or (public.my_status() = 'approved' and key = 'texts' and public.my_category() in ('orga','routenbau') and public.is_member(competition_id)));

drop policy "stands: Freigegebene lesen" on public.stands;
drop policy "stands: Orga verwaltet" on public.stands;
create policy "stands: Mitglieder oder Admin lesen" on public.stands
  for select using (public.is_admin() or (public.my_status() = 'approved' and public.is_member(competition_id)));
create policy "stands: Orga oder Admin verwaltet" on public.stands
  for all
  using (public.is_admin() or (public.my_status() = 'approved' and public.my_category() = 'orga' and public.is_member(competition_id)))
  with check (public.is_admin() or (public.my_status() = 'approved' and public.my_category() = 'orga' and public.is_member(competition_id)));

drop policy "viewers: Freigegebene lesen" on public.viewers;
drop policy "viewers: jede:r schreibt die eigene Zeile" on public.viewers;
create policy "viewers: Mitglieder oder Admin lesen" on public.viewers
  for select using (public.is_admin() or (public.my_status() = 'approved' and public.is_member(competition_id)));
create policy "viewers: jede:r schreibt die eigene Zeile" on public.viewers
  for all
  using (public.is_admin() or (public.my_status() = 'approved' and key = auth.uid() and public.is_member(competition_id)))
  with check (public.is_admin() or (public.my_status() = 'approved' and key = auth.uid() and public.is_member(competition_id)));

drop policy "tasks: Orga sieht und verwaltet alle" on public.tasks;
create policy "tasks: Orga oder Admin verwaltet alle" on public.tasks
  for all
  using (public.is_admin() or (public.my_status()='approved' and public.my_category()='orga' and public.is_member(competition_id)))
  with check (public.is_admin() or (public.my_status()='approved' and public.my_category()='orga' and public.is_member(competition_id)));
-- (die beiden "Zugewiesene …"-Policies auf tasks bleiben unverändert)

drop policy "task_assignees: sichtbar wenn Aufgabe sichtbar" on public.task_assignees;
drop policy "task_assignees: nur Orga verwaltet" on public.task_assignees;
create policy "task_assignees: sichtbar wenn Aufgabe sichtbar" on public.task_assignees
  for select using (public.my_status()='approved' and (public.my_category()='orga' or public.is_assigned(task_id)) and public.task_competition_ok(task_id));
create policy "task_assignees: nur Orga verwaltet" on public.task_assignees
  for all
  using (public.my_status()='approved' and public.my_category()='orga' and public.task_competition_ok(task_id))
  with check (public.my_status()='approved' and public.my_category()='orga' and public.task_competition_ok(task_id));

drop policy "task_comments: sichtbar wenn Aufgabe sichtbar" on public.task_comments;
drop policy "task_comments: schreiben wenn Aufgabe sichtbar" on public.task_comments;
create policy "task_comments: sichtbar wenn Aufgabe sichtbar" on public.task_comments
  for select using (public.my_status()='approved' and (public.my_category()='orga' or public.is_assigned(task_id)) and public.task_competition_ok(task_id));
create policy "task_comments: schreiben wenn Aufgabe sichtbar" on public.task_comments
  for insert
  with check (public.my_status()='approved' and (public.my_category()='orga' or public.is_assigned(task_id)) and author=auth.uid() and public.task_competition_ok(task_id));
