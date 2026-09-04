-- ============================================================
-- MIGRATION: Profil-Selbstverwaltung (eigener Name + eigenes Profilbild,
-- ohne Admin-Freigabe)
-- Einmalig im SQL Editor ausführen.
-- ============================================================

alter table public.profiles add column if not exists avatar_url text;

-- Verhindert, dass jemand über das neue Selbst-Update seine eigenen Rechte
-- hochstuft (is_admin/status/category) oder E-Mail/Freigabe-Metadaten
-- verändert. RLS allein kann das nicht spaltenweise prüfen, daher ein
-- Trigger, der diese Felder bei Nicht-Admin-Updates auf den alten Wert
-- zurücksetzt.
create or replace function public.protect_privileged_profile_fields()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not public.is_admin() then
    new.is_admin    := old.is_admin;
    new.status      := old.status;
    new.category    := old.category;
    new.email       := old.email;
    new.approved_at := old.approved_at;
    new.approved_by := old.approved_by;
  end if;
  return new;
end;
$$;
drop trigger if exists before_profile_update on public.profiles;
create trigger before_profile_update
  before update on public.profiles
  for each row execute function public.protect_privileged_profile_fields();

create policy "profiles: eigene Zeile aktualisieren" on public.profiles
  for update using (auth.uid() = id) with check (auth.uid() = id);

-- ---------- Storage: Profilbilder ----------
-- Öffentlich lesbar (damit <img> sie ohne Login/Signierung anzeigen kann),
-- Schreibzugriff nur in den eigenen Ordner "<profile_id>/…".
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do nothing;

create policy "avatars: alle lesen" on storage.objects
  for select using (bucket_id = 'avatars');
create policy "avatars: eigene Datei verwalten" on storage.objects
  for all using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text)
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);
