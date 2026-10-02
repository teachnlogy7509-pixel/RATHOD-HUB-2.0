-- Private 1-to-1 chat for authenticated YPT Study users.
create table if not exists public.ypt_private_messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  message text not null check(length(trim(message)) between 1 and 300),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  check(sender_id<>receiver_id)
);
alter table public.ypt_private_messages enable row level security;
drop policy if exists "users read own private chat" on public.ypt_private_messages;
create policy "users read own private chat" on public.ypt_private_messages for select to authenticated using(auth.uid()=sender_id or auth.uid()=receiver_id);
drop policy if exists "users send private chat" on public.ypt_private_messages;
create policy "users send private chat" on public.ypt_private_messages for insert to authenticated with check(auth.uid()=sender_id);
drop policy if exists "receiver marks private chat read" on public.ypt_private_messages;
create policy "receiver marks private chat read" on public.ypt_private_messages for update to authenticated using(auth.uid()=receiver_id) with check(auth.uid()=receiver_id);
create index if not exists ypt_private_pair_idx on public.ypt_private_messages(sender_id,receiver_id,created_at);
do $$ begin alter publication supabase_realtime add table public.ypt_private_messages; exception when duplicate_object then null; end $$;
