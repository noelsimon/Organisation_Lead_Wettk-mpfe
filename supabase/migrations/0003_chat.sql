-- ============================================================
-- MIGRATION: Chat (Gruppen-Chat je Wettkampf + private Direktnachrichten)
-- Einmalig im SQL Editor ausführen.
-- ============================================================

create type conversation_kind as enum ('group','dm');

create table public.conversations (
  id             uuid primary key default gen_random_uuid(),
  kind           conversation_kind not null,
  competition_id uuid references public.competitions(id) on delete cascade,
  created_at     timestamptz not null default now()
);
alter table public.conversations enable row level security;

create table public.conversation_participants (
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  profile_id      uuid not null references public.profiles(id) on delete cascade,
  primary key (conversation_id, profile_id)
);
alter table public.conversation_participants enable row level security;

create table public.chat_messages (
  id              uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations(id) on delete cascade,
  competition_id  uuid references public.competitions(id) on delete set null,
  sender_id       uuid not null references public.profiles(id),
  body            text not null,
  created_at      timestamptz not null default now()
);
alter table public.chat_messages enable row level security;

create or replace function public.is_conv_participant(c_id uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists(
    select 1 from public.conversations c
    where c.id = c_id and (
      (c.kind = 'group' and public.is_member(c.competition_id))
      or (c.kind = 'dm' and exists(
        select 1 from public.conversation_participants p
        where p.conversation_id = c.id and p.profile_id = auth.uid()
      ))
    )
  );
$$;

-- Gruppen-Chat automatisch anlegen, sobald künftig ein neuer Wettkampf entsteht.
create or replace function public.handle_new_competition()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.conversations (kind, competition_id) values ('group', new.id);
  return new;
end;
$$;
drop trigger if exists on_competition_created on public.competitions;
create trigger on_competition_created
  after insert on public.competitions
  for each row execute function public.handle_new_competition();

-- Für den/die schon bestehenden Wettkampf/Wettkämpfe den Gruppen-Chat nachträglich anlegen
-- (der Trigger oben greift nur für künftig neu angelegte Wettkämpfe).
insert into public.conversations (kind, competition_id)
select 'group', id from public.competitions
where id not in (select competition_id from public.conversations where kind='group' and competition_id is not null);

create policy "conversations: sichtbar für Teilnehmer oder Admin" on public.conversations
  for select using (public.is_admin() or public.is_conv_participant(id));
create policy "conversations: Admin verwaltet" on public.conversations
  for all using (public.is_admin()) with check (public.is_admin());
create policy "conversations: DM anlegen" on public.conversations
  for insert with check (kind = 'dm' and public.my_status() = 'approved');

create policy "conversation_participants: sichtbar für Teilnehmer oder Admin" on public.conversation_participants
  for select using (public.is_admin() or public.is_conv_participant(conversation_id));
create policy "conversation_participants: Admin verwaltet" on public.conversation_participants
  for all using (public.is_admin()) with check (public.is_admin());
create policy "conversation_participants: eigene DM-Teilnahme anlegen" on public.conversation_participants
  for insert
  with check (
    public.my_status() = 'approved' and
    (profile_id = auth.uid() or public.shares_competition_with(profile_id) or public.is_admin())
  );

create policy "chat_messages: sichtbar für Teilnehmer oder Admin" on public.chat_messages
  for select using (public.is_admin() or public.is_conv_participant(conversation_id));
create policy "chat_messages: Teilnehmer schreiben" on public.chat_messages
  for insert
  with check (
    sender_id = auth.uid() and public.my_status() = 'approved' and
    (public.is_admin() or public.is_conv_participant(conversation_id))
  );
