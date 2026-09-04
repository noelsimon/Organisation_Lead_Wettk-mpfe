-- ============================================================
-- Regieplan Lead-Wettkämpfe — Supabase-Schema
-- Login, Freigabe-Dashboard, feste Rechte je Kategorie, mehrere
-- Wettkämpfe parallel.
--
-- Dies ist der Fresh-Install-Stand (neues, leeres Supabase-Projekt).
-- Für ein bereits laufendes Projekt NICHT dieses ganze Skript erneut
-- ausführen — die einzelnen Migrations-Blöcke aus dem Chat-Verlauf
-- (bzw. supabase/migrations/) wurden inkrementell draufgesetzt.
--
-- Einmalig im SQL-Editor des Supabase-Projekts ausführen
-- (Dashboard → SQL Editor → New query → einfügen → Run).
-- ============================================================

-- ---------- Kategorien ----------
create type user_category as enum ('orga','sicherung','ergebnisdienst','routenbau','buffet');

-- ---------- Profile: 1 Zeile je auth.users-Eintrag ----------
create table public.profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  email       text not null,
  full_name   text not null,
  category    user_category not null,
  status      text not null default 'pending' check (status in ('pending','approved','rejected')),
  is_admin    boolean not null default false,
  created_at  timestamptz not null default now(),
  approved_at timestamptz,
  approved_by uuid references public.profiles(id)
);

alter table public.profiles enable row level security;

-- security-definer Hilfsfunktionen: lesen profiles/competition_members unter
-- Umgehung von RLS, damit die Policies unten sich nicht selbst rekursiv
-- aufrufen.
create or replace function public.is_admin()
returns boolean language sql security definer stable set search_path = public as $$
  select coalesce((select is_admin from public.profiles where id = auth.uid()), false);
$$;

create or replace function public.my_status()
returns text language sql security definer stable set search_path = public as $$
  select status from public.profiles where id = auth.uid();
$$;

create or replace function public.my_category()
returns user_category language sql security definer stable set search_path = public as $$
  select category from public.profiles where id = auth.uid();
$$;

create policy "profiles: eigene Zeile lesen" on public.profiles
  for select using (auth.uid() = id);
create policy "profiles: Admin liest alle" on public.profiles
  for select using (public.is_admin());
create policy "profiles: eigene Zeile bei Registrierung anlegen" on public.profiles
  for insert with check (auth.uid() = id);
create policy "profiles: Admin aktualisiert alle" on public.profiles
  for update using (public.is_admin()) with check (true);

-- ---------- Wettkämpfe ----------
-- Mehrere Wettkämpfe parallel; jeder hat einen eigenen Link (?w=<slug>).
-- Der Link ohne Parameter zeigt den Wettkampf mit is_default = true.
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

create or replace function public.is_member(c_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from public.competition_members where competition_id = c_id and profile_id = auth.uid());
$$;

-- Prüft für eine Aufgabe (über deren Wettkampf), ob die aufrufende Person
-- Admin oder Mitglied des zugehörigen Wettkampfs ist — verhindert, dass
-- jemand über task_assignees/task_comments an einer fremden Aufgabe
-- vorbei am Wettkampf-Zugriff manipuliert.
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

-- Ohne diese Policy sähe eine nicht-admin Person unter "Zugewiesen an" oder
-- in der Zuweisen-Auswahl nur ihren eigenen Namen (RLS blockt sonst fremde
-- profiles-Zeilen) — hier freigegeben für alle, die mindestens einen
-- Wettkampf gemeinsam haben. security definer, weil sie sonst rekursiv an
-- der RLS von competition_members selbst scheitern würde.
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

-- Profil (und bei Registrierung über einen Wettkampf-Link die Mitgliedschaft)
-- automatisch anlegen, sobald sich jemand registriert – per Trigger auf
-- auth.users statt per Insert vom Client aus. Läuft serverseitig (security
-- definer, umgeht RLS) und funktioniert dadurch unabhängig davon, ob bei der
-- Registrierung schon eine angemeldete Sitzung besteht (z.B. wenn "Confirm
-- email" aktiviert ist, gibt es direkt nach signUp() noch keine Sitzung –
-- ein Insert vom Client aus würde dann an der RLS-Policy oben scheitern).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare
  comp_id uuid;
begin
  insert into public.profiles (id, email, full_name, category)
  values (
    new.id,
    new.email,
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

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Planungsdaten: 1 Zeile je bisherigem localStorage-Key, je Wettkampf ----------
-- ersetzt kidscup-cfg-v1 / kidscup-quali-v9 / kidscup-finale-v9 / kidscup-texts-v1
create table public.plan_state (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  key            text not null check (key in ('cfg','quali','finale','texts')),
  data           jsonb not null,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles(id),
  primary key (competition_id, key)
);
alter table public.plan_state enable row level security;

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

-- Bekannte Einschränkung: die Trennung "Routenbau darf nur einzelne Textstellen
-- ändern" wird nur clientseitig durchgesetzt (die UI zeigt nur die für die Rolle
-- relevanten Textfelder als bearbeitbar) — der 'texts'-Datensatz ist ein einziges
-- JSON-Objekt, RLS kann nicht auf einzelne Schlüssel darin eingrenzen.

-- ---------- Speicherstände (je Wettkampf) ----------
-- id ist text, kein uuid: der Client erzeugt eigene IDs wie "s1a2b3c4d5e6"
-- (aus der bisherigen Plan-Engine übernommen), das ist kein UUID-Format.
create table public.stands (
  id             text primary key,
  competition_id uuid not null references public.competitions(id) on delete cascade,
  title  text not null,
  note   text,
  author text,                     -- Anzeigename, wie bisher (kein FK, entspricht meName())
  at     timestamptz not null default now(),
  state  jsonb not null
);
alter table public.stands enable row level security;
create policy "stands: Mitglieder oder Admin lesen" on public.stands
  for select using (public.is_admin() or (public.my_status() = 'approved' and public.is_member(competition_id)));
create policy "stands: Orga oder Admin verwaltet" on public.stands
  for all
  using (public.is_admin() or (public.my_status() = 'approved' and public.my_category() = 'orga' and public.is_member(competition_id)))
  with check (public.is_admin() or (public.my_status() = 'approved' and public.my_category() = 'orga' and public.is_member(competition_id)));

-- ---------- Wer war zuletzt hier (je Wettkampf) ----------
create table public.viewers (
  key            uuid not null,
  competition_id uuid not null references public.competitions(id) on delete cascade,
  name text not null,
  at   timestamptz not null,
  last text,
  pdf  int not null default 0,
  primary key (competition_id, key)
);
alter table public.viewers enable row level security;
create policy "viewers: Mitglieder oder Admin lesen" on public.viewers
  for select using (public.is_admin() or (public.my_status() = 'approved' and public.is_member(competition_id)));
create policy "viewers: jede:r schreibt die eigene Zeile" on public.viewers
  for all
  using (public.is_admin() or (public.my_status() = 'approved' and key = auth.uid() and public.is_member(competition_id)))
  with check (public.is_admin() or (public.my_status() = 'approved' and key = auth.uid() and public.is_member(competition_id)));

-- ---------- Aufgaben (je Wettkampf) ----------
-- Orga weist Aufgaben (mit Kategorie-Tag, Dringlichkeit, mehreren
-- Zugewiesenen) zu; Zugewiesene kommentieren und markieren als erledigt.
create type task_priority as enum ('niedrig','mittel','hoch');
create type task_status as enum ('open','done');

create table public.tasks (
  id             uuid primary key default gen_random_uuid(),
  competition_id uuid not null references public.competitions(id) on delete cascade,
  title       text not null,
  description text,
  category    user_category,          -- optionales Filter-Tag, wiederverwendet die Personal-Kategorien
  priority    task_priority not null default 'mittel',
  status      task_status not null default 'open',
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now(),
  done_at     timestamptz,
  done_by     uuid references public.profiles(id)
);
alter table public.tasks enable row level security;

-- updated_at automatisch pflegen, damit die Oberfläche neue Aktivität
-- (Statusänderung etc.) erkennen kann, ohne jede Änderung einzeln zu tracken.
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;
drop trigger if exists tasks_touch_updated_at on public.tasks;
create trigger tasks_touch_updated_at
  before update on public.tasks
  for each row execute function public.touch_updated_at();

create table public.task_assignees (
  task_id    uuid not null references public.tasks(id) on delete cascade,
  profile_id uuid not null references public.profiles(id) on delete cascade,
  primary key (task_id, profile_id)
);
alter table public.task_assignees enable row level security;

create table public.task_comments (
  id         uuid primary key default gen_random_uuid(),
  task_id    uuid not null references public.tasks(id) on delete cascade,
  author     uuid references public.profiles(id),
  body       text not null,
  created_at timestamptz not null default now()
);
alter table public.task_comments enable row level security;

-- Hilfsfunktion: bin ich einer bestimmten Aufgabe zugewiesen?
create or replace function public.is_assigned(t_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(select 1 from public.task_assignees where task_id = t_id and profile_id = auth.uid());
$$;

create policy "tasks: Orga oder Admin verwaltet alle" on public.tasks
  for all
  using (public.is_admin() or (public.my_status()='approved' and public.my_category()='orga' and public.is_member(competition_id)))
  with check (public.is_admin() or (public.my_status()='approved' and public.my_category()='orga' and public.is_member(competition_id)));
create policy "tasks: Zugewiesene sehen eigene Aufgaben" on public.tasks
  for select using (public.my_status()='approved' and public.is_assigned(id));
create policy "tasks: Zugewiesene markieren erledigt/offen" on public.tasks
  for update
  using (public.my_status()='approved' and public.is_assigned(id))
  with check (public.my_status()='approved' and public.is_assigned(id));

create policy "task_assignees: sichtbar wenn Aufgabe sichtbar" on public.task_assignees
  for select using (public.my_status()='approved' and (public.my_category()='orga' or public.is_assigned(task_id)) and public.task_competition_ok(task_id));
create policy "task_assignees: nur Orga verwaltet" on public.task_assignees
  for all
  using (public.my_status()='approved' and public.my_category()='orga' and public.task_competition_ok(task_id))
  with check (public.my_status()='approved' and public.my_category()='orga' and public.task_competition_ok(task_id));

create policy "task_comments: sichtbar wenn Aufgabe sichtbar" on public.task_comments
  for select using (public.my_status()='approved' and (public.my_category()='orga' or public.is_assigned(task_id)) and public.task_competition_ok(task_id));
create policy "task_comments: schreiben wenn Aufgabe sichtbar" on public.task_comments
  for insert
  with check (public.my_status()='approved' and (public.my_category()='orga' or public.is_assigned(task_id)) and author=auth.uid() and public.task_competition_ok(task_id));

-- Bekannte Einschränkung, gleiches Muster wie bei den Texten: Zugewiesene
-- dürfen die ganze tasks-Zeile updaten (nicht nur status/done_at), weil RLS
-- keine Spalten einschränkt. Die Oberfläche zeigt Zugewiesenen aber nur den
-- Erledigt-Umschalter, nicht die Bearbeitungsfelder von Orga.

-- ============================================================
-- Danach in der README weiterlesen:
--  1. Auth → Providers → Email aktivieren (Confirm email nach Bedarf)
--  2. Edge Function "notify-signup" deployen + Secrets setzen
--  3. Database → Webhooks: INSERT auf profiles → Edge Function notify-signup
--  4. src/config.part mit Project URL + anon key füllen, `python3 src/build.py`
--  5. Einen ersten Wettkampf anlegen (is_default = true), z.B.:
--       insert into public.competitions (slug, name, is_default)
--       values ('kidscup2026', 'Kidscup 2026', true);
--  6. Einmalig dich selbst freischalten + dem Wettkampf zuordnen
--     (E-Mail anpassen, competitions-ID aus Schritt 5 einsetzen):
--       update public.profiles set is_admin = true, status = 'approved'
--       where email = 'deine@mail.de';
--       insert into public.competition_members (competition_id, profile_id)
--       select '<competition-id-aus-schritt-5>', id from public.profiles
--       where email = 'deine@mail.de';
-- ============================================================
