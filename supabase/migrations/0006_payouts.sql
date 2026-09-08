-- ============================================================
-- MIGRATION: Honorar/Auszahlung je Person (nur für Admins sichtbar)
-- Einmalig im SQL Editor ausführen.
-- ============================================================

-- Eigene Tabelle statt Ablage in plan_state/CFG: plan_state ist für alle
-- freigegebenen Mitglieder des Wettkampfs lesbar (siehe "plan_state:
-- Mitglieder oder Admin lesen") – Honorare sollen aber ausschließlich für
-- Admins sichtbar sein. person_id verweist auf die Client-ID aus
-- CFG.people (kein Fremdschlüssel möglich, da diese Liste reines
-- Plan-JSON ist).
create table public.payouts (
  competition_id uuid not null references public.competitions(id) on delete cascade,
  person_id      text not null,
  amount         numeric not null default 25,
  updated_at     timestamptz not null default now(),
  updated_by     uuid references public.profiles(id),
  primary key (competition_id, person_id)
);
alter table public.payouts enable row level security;

create policy "payouts: nur Admin" on public.payouts
  for all using (public.is_admin()) with check (public.is_admin());
