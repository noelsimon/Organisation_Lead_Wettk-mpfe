-- ============================================================
-- MIGRATION: Sync-Konflikt-Erkennung für plan_state
-- Einmalig im SQL Editor ausführen, VOR dem Mergen des zugehörigen PR
-- (der Client fragt ab sofort die "version"-Spalte ab).
-- ============================================================

-- Ganzzahlige Version statt Zeitvergleich: robuster als updated_at
-- (Rundung/Zeitzonen beim Hin- und Herschicken), einfacher exakt zu
-- vergleichen. Startet bei 1, wird beim Speichern serverseitig hochgezählt.
alter table public.plan_state add column if not exists version integer not null default 1;

-- Erhöht die Version bei jedem UPDATE und setzt updated_at serverseitig neu -
-- unabhängig davon, was der Client mitschickt. Der Client liest vor dem
-- Speichern die zuletzt bekannte Version mit; weicht sie beim Schreiben von
-- der aktuellen Server-Version ab (0 betroffene Zeilen beim UPDATE), hat
-- inzwischen jemand anderes gespeichert - die Oberfläche zeigt dann den
-- Sync-Konflikt-Hinweis statt still zu überschreiben.
create or replace function public.bump_plan_state_version()
returns trigger language plpgsql as $$
begin
  new.version := coalesce(old.version, 0) + 1;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists before_plan_state_update on public.plan_state;
create trigger before_plan_state_update
  before update on public.plan_state
  for each row execute function public.bump_plan_state_version();
