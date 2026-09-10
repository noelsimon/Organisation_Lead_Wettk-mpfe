-- ============================================================
-- MIGRATION: Texte in eigene Zeilen je Abschnitt umbauen, damit RLS
-- Routenbau auf den Routenplan-Bereich einschränken kann.
-- Einmalig im SQL Editor ausführen, VOR dem Mergen des zugehörigen PR
-- (der Client fragt ab sofort die Tabelle plan_texts ab).
-- ============================================================

create table if not exists public.plan_texts (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  ed_key         text not null,
  scope          text not null,
  html           text not null default '',
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles(id),
  primary key (competition_id, ed_key)
);
alter table public.plan_texts enable row level security;

create policy "plan_texts: Mitglieder oder Admin lesen" on public.plan_texts
  for select using (public.is_admin() or (public.my_status() = 'approved' and public.is_member(competition_id)));
create policy "plan_texts: Orga/Admin aktualisieren, Routenbau nur Routenplan" on public.plan_texts
  for update
  using (public.is_admin() or (public.my_status() = 'approved' and public.is_member(competition_id) and (
           public.my_category() = 'orga' or (public.my_category() = 'routenbau' and scope = 'routenplan'))))
  with check (public.is_admin() or (public.my_status() = 'approved' and public.is_member(competition_id) and (
           public.my_category() = 'orga' or (public.my_category() = 'routenbau' and scope = 'routenplan'))));
create policy "plan_texts: Orga/Admin legen Zeile an, Routenbau nur Routenplan" on public.plan_texts
  for insert
  with check (public.is_admin() or (public.my_status() = 'approved' and public.is_member(competition_id) and (
           public.my_category() = 'orga' or (public.my_category() = 'routenbau' and scope = 'routenplan'))));

-- Bestehende Texte aus dem plan_state-JSON-Blob (key='texts') verlustfrei in
-- die neue Zeilen-Struktur umschreiben. "scope" wird aus dem Element-
-- Schlüssel abgeleitet (Format "<scope>_<TAG>_<n>", siehe initTexts() in
-- src/script.part) - bekannter Grenzfall: nachträglich per "+ Baustein"
-- hinzugefügte Textbausteine tragen stattdessen einen Zufalls-Schlüssel
-- ("n..."), ohne Unterstrich, ihr abgeleiteter "scope" ist dann einfach der
-- ganze Schlüssel und trifft nie auf 'routenplan' zu (Routenbau kann so
-- einen selbst hinzugefügten Baustein bis zur nächsten Bearbeitung durch
-- Orga/Admin nicht mehr ändern - danach schreibt der Client den korrekten
-- scope automatisch mit, das behebt sich von selbst).
insert into public.plan_texts (competition_id, ed_key, scope, html)
select
  ps.competition_id,
  kv.key,
  coalesce(nullif(split_part(kv.key,'_',1),''), 'root'),
  coalesce(kv.value #>> '{}', '')
from public.plan_state ps
cross join lateral jsonb_each(ps.data) as kv(key,value)
where ps.key = 'texts'
on conflict (competition_id, ed_key) do nothing;

-- Der alte Blob wird nicht mehr gelesen; aufräumen, damit keine
-- widersprüchliche Kopie liegen bleibt. Der 'texts'-Schlüssel bleibt in
-- der key-Liste von plan_state weiterhin erlaubt, falls während der
-- Umstellung noch ein alter Client schreibt - dieser Übergangs-Datensatz
-- wird von neuen Clients einfach nicht mehr gelesen.
delete from public.plan_state where key = 'texts';
