-- ============================================================
-- MIGRATION: Aufgabentool nur für echte Admins, nicht für Kategorie "orga"
-- (public.my_category()='orga' ist Selbstauswahl bei der Anmeldung und kein
-- Admin-Recht; die tasks/task_assignees/task_comments-Policies verwendeten
-- sie fälschlich als Admin-Stellvertreter. Ersetzt durch public.is_admin().
-- Zugewiesene Personen sehen weiterhin nur ihre eigenen Aufgaben über die
-- unveränderten is_assigned()-Policies.)
-- ============================================================

drop policy "tasks: Orga oder Admin verwaltet alle" on public.tasks;
create policy "tasks: Orga oder Admin verwaltet alle" on public.tasks
  for all
  using (public.is_admin())
  with check (public.is_admin());

drop policy "task_assignees: sichtbar wenn Aufgabe sichtbar" on public.task_assignees;
drop policy "task_assignees: nur Orga verwaltet" on public.task_assignees;
create policy "task_assignees: sichtbar wenn Aufgabe sichtbar" on public.task_assignees
  for select using (public.my_status()='approved' and (public.is_admin() or public.is_assigned(task_id)) and public.task_competition_ok(task_id));
create policy "task_assignees: nur Orga verwaltet" on public.task_assignees
  for all
  using (public.my_status()='approved' and public.is_admin() and public.task_competition_ok(task_id))
  with check (public.my_status()='approved' and public.is_admin() and public.task_competition_ok(task_id));

drop policy "task_comments: sichtbar wenn Aufgabe sichtbar" on public.task_comments;
drop policy "task_comments: schreiben wenn Aufgabe sichtbar" on public.task_comments;
create policy "task_comments: sichtbar wenn Aufgabe sichtbar" on public.task_comments
  for select using (public.my_status()='approved' and (public.is_admin() or public.is_assigned(task_id)) and public.task_competition_ok(task_id));
create policy "task_comments: schreiben wenn Aufgabe sichtbar" on public.task_comments
  for insert
  with check (public.my_status()='approved' and (public.is_admin() or public.is_assigned(task_id)) and author=auth.uid() and public.task_competition_ok(task_id));
