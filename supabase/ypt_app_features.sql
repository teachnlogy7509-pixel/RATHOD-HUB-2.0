-- Realtime chat, admin notifications and app updates for YPT Study by Rathod
create table if not exists public.ypt_live_chat (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null, message text not null check(length(trim(message)) between 1 and 300), created_at timestamptz not null default now()
);
alter table public.ypt_live_chat enable row level security;
drop policy if exists "authenticated read live chat" on public.ypt_live_chat;
create policy "authenticated read live chat" on public.ypt_live_chat for select to authenticated using(true);
drop policy if exists "authenticated write own live chat" on public.ypt_live_chat;
create policy "authenticated write own live chat" on public.ypt_live_chat for insert to authenticated with check(auth.uid()=user_id);
create index if not exists ypt_live_chat_created_idx on public.ypt_live_chat(created_at desc);

create table if not exists public.ypt_admins (
  user_id uuid primary key references auth.users(id) on delete cascade, created_at timestamptz not null default now()
);
alter table public.ypt_admins enable row level security;
create or replace function public.ypt_is_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.ypt_admins where user_id=auth.uid())$$;
revoke all on function public.ypt_is_admin() from public,anon; grant execute on function public.ypt_is_admin() to authenticated;

create table if not exists public.ypt_notifications (
  id uuid primary key default gen_random_uuid(), title text not null, body text not null,
  type text not null default 'notice' check(type in ('notice','maintenance','event','update')),
  link_url text, created_by uuid references auth.users(id) on delete set null, published boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.ypt_notifications enable row level security;
drop policy if exists "users read published notifications" on public.ypt_notifications;
create policy "users read published notifications" on public.ypt_notifications for select to authenticated using(published=true or public.ypt_is_admin());
drop policy if exists "admins manage notifications" on public.ypt_notifications;
create policy "admins manage notifications" on public.ypt_notifications for all to authenticated using(public.ypt_is_admin()) with check(public.ypt_is_admin());

create table if not exists public.ypt_app_updates (
  id uuid primary key default gen_random_uuid(), version text not null, title text not null, notes text not null,
  apk_url text, force_update boolean not null default false, published boolean not null default true,
  created_by uuid references auth.users(id) on delete set null, created_at timestamptz not null default now()
);
alter table public.ypt_app_updates enable row level security;
drop policy if exists "users read published updates" on public.ypt_app_updates;
create policy "users read published updates" on public.ypt_app_updates for select to authenticated using(published=true or public.ypt_is_admin());
drop policy if exists "admins manage updates" on public.ypt_app_updates;
create policy "admins manage updates" on public.ypt_app_updates for all to authenticated using(public.ypt_is_admin()) with check(public.ypt_is_admin());

do $$ begin alter publication supabase_realtime add table public.ypt_live_chat; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.ypt_notifications; exception when duplicate_object then null; end $$;
do $$ begin alter publication supabase_realtime add table public.ypt_app_updates; exception when duplicate_object then null; end $$;

create table if not exists public.ypt_login_names (
  user_id uuid primary key references auth.users(id) on delete cascade,
  username text unique not null check(length(username) between 3 and 40),
  recovery_email text not null,
  created_at timestamptz not null default now()
);
alter table public.ypt_login_names enable row level security;
drop policy if exists "users manage own login name" on public.ypt_login_names;
create policy "users manage own login name" on public.ypt_login_names for all to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
create or replace function public.resolve_ypt_login(p_name text) returns text
language sql stable security definer set search_path=public as $$select recovery_email from public.ypt_login_names where lower(username)=lower(trim(p_name)) limit 1$$;
revoke all on function public.resolve_ypt_login(text) from public;
grant execute on function public.resolve_ypt_login(text) to anon,authenticated;

create table if not exists public.ypt_private_messages (
  id uuid primary key default gen_random_uuid(), sender_id uuid not null references auth.users(id) on delete cascade,
  receiver_id uuid not null references auth.users(id) on delete cascade,
  message text not null check(length(trim(message)) between 1 and 300), created_at timestamptz not null default now(), read_at timestamptz,
  check(sender_id<>receiver_id)
);
alter table public.ypt_private_messages enable row level security;
drop policy if exists "users read own private chat" on public.ypt_private_messages;
create policy "users read own private chat" on public.ypt_private_messages for select to authenticated using(auth.uid()=sender_id or auth.uid()=receiver_id);
drop policy if exists "users send private chat" on public.ypt_private_messages;
create policy "users send private chat" on public.ypt_private_messages for insert to authenticated with check(auth.uid()=sender_id);
drop policy if exists "receiver marks private chat read" on public.ypt_private_messages;
create policy "receiver marks private chat read" on public.ypt_private_messages for update to authenticated using(auth.uid()=receiver_id) with check(auth.uid()=receiver_id);
do $$ begin alter publication supabase_realtime add table public.ypt_private_messages; exception when duplicate_object then null; end $$;

create table if not exists public.ypt_recovery_rate (
  username text primary key, failed_attempts integer not null default 0,
  blocked_until timestamptz, updated_at timestamptz not null default now()
);
alter table public.ypt_recovery_rate enable row level security;
-- No client policies. Only the security-definer recovery function can access this table.
create or replace function public.recover_ypt_account(p_name text,p_recovery_email text,p_new_password text)
returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare account record; rate record;
begin
  if length(p_new_password)<6 then return jsonb_build_object('success',false,'error','Password must be at least 6 characters'); end if;
  select * into rate from public.ypt_recovery_rate where username=lower(trim(p_name)) for update;
  if rate.blocked_until is not null and rate.blocked_until>now() then return jsonb_build_object('success',false,'error','Too many attempts. Try later.'); end if;
  select user_id,recovery_email into account from public.ypt_login_names where lower(username)=lower(trim(p_name)) limit 1;
  if account.user_id is null or lower(account.recovery_email)<>lower(trim(p_recovery_email)) then
    insert into public.ypt_recovery_rate(username,failed_attempts,blocked_until,updated_at) values(lower(trim(p_name)),1,null,now())
    on conflict(username) do update set failed_attempts=public.ypt_recovery_rate.failed_attempts+1,blocked_until=case when public.ypt_recovery_rate.failed_attempts+1>=5 then now()+interval '1 hour' else null end,updated_at=now();
    return jsonb_build_object('success',false,'error','Recovery details do not match');
  end if;
  update auth.users set encrypted_password=crypt(p_new_password,gen_salt('bf')),updated_at=now() where id=account.user_id;
  delete from public.ypt_recovery_rate where username=lower(trim(p_name));
  return jsonb_build_object('success',true);
end; $$;
revoke all on function public.recover_ypt_account(text,text,text) from public;
grant execute on function public.recover_ypt_account(text,text,text) to anon,authenticated;
