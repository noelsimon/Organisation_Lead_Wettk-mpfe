-- ============================================================
-- MIGRATION: E-Mail je Person (nur für Admins sichtbar)
-- Einmalig im SQL Editor ausführen.
-- ============================================================

-- Eigene Tabelle statt Ablage in plan_state/CFG.people: plan_state ist für
-- alle freigegebenen Mitglieder des Wettkampfs lesbar (siehe "plan_state:
-- Mitglieder oder Admin lesen") – E-Mail-Adressen sollen aber ausschließlich
-- für Admins sichtbar sein. Gleiches Muster wie payouts (Migration 0006):
-- person_id verweist auf die Client-ID aus CFG.people (kein Fremdschlüssel
-- möglich, da diese Liste reines Plan-JSON ist).
create table public.people_contacts (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  person_id      text not null,
  email          text,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles(id),
  primary key (competition_id, person_id)
);
alter table public.people_contacts enable row level security;

create policy "people_contacts: nur Admin" on public.people_contacts
  for all using (public.is_admin()) with check (public.is_admin());
