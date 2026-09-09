-- ============================================================
-- MIGRATION: Textbausteine hinzufügen/entfernen in der Textbearbeitung
-- Einmalig im SQL Editor ausführen.
-- ============================================================

-- Neuer plan_state-Schlüssel "textblocks" (welche Textbausteine hinzugefügt
-- oder entfernt wurden), synchronisiert genau wie "texts".
alter table public.plan_state drop constraint if exists plan_state_key_check;
alter table public.plan_state add constraint plan_state_key_check
  check (key in ('cfg','quali','finale','texts','textblocks'));

drop policy if exists "plan_state: Orga/Routenbau/Admin schreiben Texte" on public.plan_state;
create policy "plan_state: Orga/Routenbau/Admin schreiben Texte" on public.plan_state
  for update
  using (public.is_admin() or (public.my_status() = 'approved' and key in ('texts','textblocks') and public.my_category() in ('orga','routenbau') and public.is_member(competition_id)))
  with check (public.is_admin() or (public.my_status() = 'approved' and key in ('texts','textblocks') and public.my_category() in ('orga','routenbau') and public.is_member(competition_id)));

drop policy if exists "plan_state: Orga/Routenbau/Admin legen Texte-Zeile an" on public.plan_state;
create policy "plan_state: Orga/Routenbau/Admin legen Texte-Zeile an" on public.plan_state
  for insert
  with check (public.is_admin() or (public.my_status() = 'approved' and key in ('texts','textblocks') and public.my_category() in ('orga','routenbau') and public.is_member(competition_id)));
