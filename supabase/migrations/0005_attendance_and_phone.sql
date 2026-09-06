-- ============================================================
-- MIGRATION: Telefonnummer im Profil + An-/Abwesenheit je Wettkampf
-- Einmalig im SQL Editor ausführen.
-- ============================================================

alter table public.profiles add column if not exists phone text;
-- Kein neues RLS nötig: "profiles: eigene Zeile aktualisieren" (Migration
-- 0004) deckt das Feld schon ab, und "profiles: Mitwettkämpfer sehen
-- Basisdaten" ist zeilenbasiert (RLS kennt keine Spaltenrechte) – sobald
-- ein Client "phone" mit abfragt, ist es für Mitwettkämpfer sichtbar.

alter table public.competition_members add column if not exists attendance text
  check (attendance in ('da','unterwegs','abwesend'));
alter table public.competition_members add column if not exists attendance_at timestamptz;

-- Verhindert, dass jemand über das Selbst-Update unten den Primärschlüssel
-- (competition_id/profile_id) verschiebt und sich damit selbst einem
-- anderen Wettkampf zuordnet.
create or replace function public.protect_membership_keys()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.competition_id := old.competition_id;
    new.profile_id := old.profile_id;
  end if;
  return new;
end;
$$;
drop trigger if exists before_membership_update on public.competition_members;
create trigger before_membership_update
  before update on public.competition_members
  for each row execute function public.protect_membership_keys();

create policy "competition_members: Mitglieder sehen Anwesenheit" on public.competition_members
  for select using (public.is_admin() or public.is_member(competition_id));
create policy "competition_members: eigene Anwesenheit aktualisieren" on public.competition_members
  for update using (profile_id = auth.uid()) with check (profile_id = auth.uid());
