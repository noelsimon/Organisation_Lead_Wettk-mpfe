-- ============================================================
-- MIGRATION: Nur Admins löschen gespeicherte Stände
-- (Laden bleibt technisch eine plan_state-Schreibaktion und ist für Orga
-- weiter möglich, wird aber in der Oberfläche auf Admin beschränkt.)
-- ============================================================

drop policy "stands: Orga oder Admin verwaltet" on public.stands;

create policy "stands: Orga oder Admin legen an/aktualisieren" on public.stands
  for insert
  with check (public.is_admin() or (public.my_status() = 'approved' and public.my_category() = 'orga' and public.is_member(competition_id)));
create policy "stands: Orga oder Admin aktualisieren" on public.stands
  for update
  using (public.is_admin() or (public.my_status() = 'approved' and public.my_category() = 'orga' and public.is_member(competition_id)))
  with check (public.is_admin() or (public.my_status() = 'approved' and public.my_category() = 'orga' and public.is_member(competition_id)));
create policy "stands: nur Admin löscht" on public.stands
  for delete using (public.is_admin());
