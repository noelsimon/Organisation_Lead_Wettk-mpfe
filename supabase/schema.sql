-- ============================================================
-- Regieplan Lead-Wettkämpfe — Supabase-Schema
-- Login, Freigabe-Dashboard, feste Rechte je Kategorie.
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

-- security-definer Hilfsfunktionen: lesen profiles unter Umgehung von RLS,
-- damit die Policies unten sich nicht selbst rekursiv aufrufen.
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

-- Profil automatisch anlegen, sobald sich jemand registriert – per Trigger auf
-- auth.users statt per Insert vom Client aus. Läuft serverseitig (security
-- definer, umgeht RLS) und funktioniert dadurch unabhängig davon, ob bei der
-- Registrierung schon eine angemeldete Sitzung besteht (z.B. wenn "Confirm
-- email" aktiviert ist, gibt es direkt nach signUp() noch keine Sitzung –
-- ein Insert vom Client aus würde dann an der RLS-Policy oben scheitern).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name, category)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data->>'full_name', split_part(new.email,'@',1)),
    coalesce((new.raw_user_meta_data->>'category')::user_category, 'buffet')
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- Planungsdaten: 1 Zeile je bisherigem localStorage-Key ----------
-- ersetzt kidscup-cfg-v1 / kidscup-quali-v9 / kidscup-finale-v9 / kidscup-texts-v1
create table public.plan_state (
  key        text primary key check (key in ('cfg','quali','finale','texts')),
  data       jsonb not null,
  updated_at timestamptz not null default now(),
  updated_by uuid references public.profiles(id)
);
alter table public.plan_state enable row level security;

create policy "plan_state: Freigegebene lesen alles" on public.plan_state
  for select using (public.my_status() = 'approved');
create policy "plan_state: Orga schreibt Klassen/Zeitplan" on public.plan_state
  for all
  using (public.my_status() = 'approved' and public.my_category() = 'orga' and key in ('cfg','quali','finale'))
  with check (public.my_status() = 'approved' and public.my_category() = 'orga' and key in ('cfg','quali','finale'));
create policy "plan_state: Orga und Routenbau schreiben Texte" on public.plan_state
  for update
  using (public.my_status() = 'approved' and key = 'texts' and public.my_category() in ('orga','routenbau'))
  with check (public.my_status() = 'approved' and key = 'texts' and public.my_category() in ('orga','routenbau'));
create policy "plan_state: Orga oder Routenbau legen Texte-Zeile an" on public.plan_state
  for insert
  with check (public.my_status() = 'approved' and key = 'texts' and public.my_category() in ('orga','routenbau'));

-- Bekannte Einschränkung: die Trennung "Routenbau darf nur einzelne Textstellen
-- ändern" wird nur clientseitig durchgesetzt (die UI zeigt nur die für die Rolle
-- relevanten Textfelder als bearbeitbar) — der 'texts'-Datensatz ist ein einziges
-- JSON-Objekt, RLS kann nicht auf einzelne Schlüssel darin eingrenzen.

-- ---------- Speicherstände ----------
-- id ist text, kein uuid: der Client erzeugt eigene IDs wie "s1a2b3c4d5e6"
-- (aus der bisherigen Plan-Engine übernommen), das ist kein UUID-Format.
create table public.stands (
  id     text primary key,
  title  text not null,
  note   text,
  author text,                     -- Anzeigename, wie bisher (kein FK, entspricht meName())
  at     timestamptz not null default now(),
  state  jsonb not null
);
alter table public.stands enable row level security;
create policy "stands: Freigegebene lesen" on public.stands
  for select using (public.my_status() = 'approved');
create policy "stands: Orga verwaltet" on public.stands
  for all
  using (public.my_status() = 'approved' and public.my_category() = 'orga')
  with check (public.my_status() = 'approved' and public.my_category() = 'orga');

-- ---------- Wer war zuletzt hier ----------
create table public.viewers (
  key  uuid primary key,
  name text not null,
  at   timestamptz not null,
  last text,
  pdf  int not null default 0
);
alter table public.viewers enable row level security;
create policy "viewers: Freigegebene lesen" on public.viewers
  for select using (public.my_status() = 'approved');
create policy "viewers: jede:r schreibt die eigene Zeile" on public.viewers
  for all
  using (public.my_status() = 'approved' and key = auth.uid())
  with check (public.my_status() = 'approved' and key = auth.uid());

-- ---------- Aufgaben ----------
-- Orga weist Aufgaben (mit Kategorie-Tag, Dringlichkeit, mehreren
-- Zugewiesenen) zu; Zugewiesene kommentieren und markieren als erledigt.
create type task_priority as enum ('niedrig','mittel','hoch');
create type task_status as enum ('open','done');

create table public.tasks (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  description text,
  category    user_category,          -- optionales Filter-Tag, wiederverwendet die Personal-Kategorien
  priority    task_priority not null default 'mittel',
  status      task_status not null default 'open',
  created_by  uuid references public.profiles(id),
  created_at  timestamptz not null default now(),
  done_at     timestamptz,
  done_by     uuid references public.profiles(id)
);
alter table public.tasks enable row level security;

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

create policy "tasks: Orga sieht und verwaltet alle" on public.tasks
  for all
  using (public.my_status()='approved' and public.my_category()='orga')
  with check (public.my_status()='approved' and public.my_category()='orga');
create policy "tasks: Zugewiesene sehen eigene Aufgaben" on public.tasks
  for select using (public.my_status()='approved' and public.is_assigned(id));
create policy "tasks: Zugewiesene markieren erledigt/offen" on public.tasks
  for update
  using (public.my_status()='approved' and public.is_assigned(id))
  with check (public.my_status()='approved' and public.is_assigned(id));

create policy "task_assignees: sichtbar wenn Aufgabe sichtbar" on public.task_assignees
  for select using (public.my_status()='approved' and (public.my_category()='orga' or public.is_assigned(task_id)));
create policy "task_assignees: nur Orga verwaltet" on public.task_assignees
  for all
  using (public.my_status()='approved' and public.my_category()='orga')
  with check (public.my_status()='approved' and public.my_category()='orga');

create policy "task_comments: sichtbar wenn Aufgabe sichtbar" on public.task_comments
  for select using (public.my_status()='approved' and (public.my_category()='orga' or public.is_assigned(task_id)));
create policy "task_comments: schreiben wenn Aufgabe sichtbar" on public.task_comments
  for insert
  with check (public.my_status()='approved' and (public.my_category()='orga' or public.is_assigned(task_id)) and author=auth.uid());

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
--  5. Einmalig dich selbst freischalten (E-Mail anpassen):
--       update public.profiles set is_admin = true, status = 'approved'
--       where email = 'deine@mail.de';
-- ============================================================
