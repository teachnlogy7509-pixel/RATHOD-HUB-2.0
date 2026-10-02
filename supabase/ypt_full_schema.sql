-- RATHOD Focus: YPT-style study system (safe to run repeatedly)
create extension if not exists pgcrypto;

create table if not exists public.ypt_focus_sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  subject text not null default 'General',
  session_date date not null default current_date,
  duration_seconds integer not null check (duration_seconds >= 0),
  started_at timestamptz not null,
  ended_at timestamptz,
  created_at timestamptz not null default now()
);
create index if not exists ypt_focus_user_date_idx on public.ypt_focus_sessions(user_id,session_date desc);
alter table public.ypt_focus_sessions enable row level security;
drop policy if exists "ypt own sessions read" on public.ypt_focus_sessions;
create policy "ypt own sessions read" on public.ypt_focus_sessions for select to authenticated using (auth.uid()=user_id);
drop policy if exists "ypt own sessions insert" on public.ypt_focus_sessions;
create policy "ypt own sessions insert" on public.ypt_focus_sessions for insert to authenticated with check (auth.uid()=user_id);
drop policy if exists "ypt own sessions update" on public.ypt_focus_sessions;
create policy "ypt own sessions update" on public.ypt_focus_sessions for update to authenticated using (auth.uid()=user_id) with check (auth.uid()=user_id);
drop policy if exists "ypt own sessions delete" on public.ypt_focus_sessions;
create policy "ypt own sessions delete" on public.ypt_focus_sessions for delete to authenticated using (auth.uid()=user_id);

create table if not exists public.ypt_live_sessions (
  user_id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Learner',
  subject text not null default 'General',
  status text not null default 'live' check(status in ('live','paused','ended')),
  started_at timestamptz not null default now(),
  last_heartbeat_at timestamptz not null default now(),
  elapsed_seconds integer not null default 0 check(elapsed_seconds>=0)
);
alter table public.ypt_live_sessions enable row level security;
drop policy if exists "authenticated view ypt live" on public.ypt_live_sessions;
create policy "authenticated view ypt live" on public.ypt_live_sessions for select to authenticated using (true);
drop policy if exists "ypt own live insert" on public.ypt_live_sessions;
create policy "ypt own live insert" on public.ypt_live_sessions for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "ypt own live update" on public.ypt_live_sessions;
create policy "ypt own live update" on public.ypt_live_sessions for update to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);

create table if not exists public.ypt_daily_tasks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  task_date date not null default current_date,
  title text not null check(length(trim(title))>0),
  subject text,
  completed boolean not null default false,
  created_at timestamptz not null default now()
);
alter table public.ypt_daily_tasks enable row level security;
drop policy if exists "ypt own tasks all" on public.ypt_daily_tasks;
create policy "ypt own tasks all" on public.ypt_daily_tasks for all to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
create index if not exists ypt_tasks_user_date_idx on public.ypt_daily_tasks(user_id,task_date desc);

create table if not exists public.ypt_study_groups (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null check(length(trim(name)) between 2 and 50),
  privacy text not null default 'public' check(privacy in ('public','private')),
  weekly_goal_hours integer not null default 35 check(weekly_goal_hours between 1 and 200),
  invite_code text unique not null default upper(substr(encode(gen_random_bytes(6),'hex'),1,8)),
  created_at timestamptz not null default now()
);
create table if not exists public.ypt_group_members (
  group_id uuid not null references public.ypt_study_groups(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null default 'member' check(role in ('owner','admin','member')),
  joined_at timestamptz not null default now(),
  primary key(group_id,user_id)
);
create or replace function public.ypt_is_group_member(g uuid) returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.ypt_group_members where group_id=g and user_id=auth.uid())$$;
alter table public.ypt_study_groups enable row level security;
alter table public.ypt_group_members enable row level security;
drop policy if exists "view public or joined ypt groups" on public.ypt_study_groups;
create policy "view public or joined ypt groups" on public.ypt_study_groups for select to authenticated using(privacy='public' or owner_id=auth.uid() or public.ypt_is_group_member(id));
drop policy if exists "create ypt groups" on public.ypt_study_groups;
create policy "create ypt groups" on public.ypt_study_groups for insert to authenticated with check(owner_id=auth.uid());
drop policy if exists "owner updates ypt group" on public.ypt_study_groups;
create policy "owner updates ypt group" on public.ypt_study_groups for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists "members view ypt memberships" on public.ypt_group_members;
create policy "members view ypt memberships" on public.ypt_group_members for select to authenticated using(public.ypt_is_group_member(group_id));
drop policy if exists "join public ypt group" on public.ypt_group_members;
create policy "join public ypt group" on public.ypt_group_members for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.ypt_study_groups g where g.id=group_id and (g.privacy='public' or g.owner_id=auth.uid())));
drop policy if exists "leave ypt group" on public.ypt_group_members;
create policy "leave ypt group" on public.ypt_group_members for delete to authenticated using(user_id=auth.uid());

create or replace view public.ypt_weekly_leaderboard with (security_invoker=true) as
select user_id, sum(duration_seconds)::bigint as focus_seconds, count(*)::bigint as sessions
from public.ypt_focus_sessions
where session_date >= date_trunc('week',current_date)::date
group by user_id;

do $$ begin
  alter publication supabase_realtime add table public.ypt_live_sessions;
exception when duplicate_object then null; end $$;


-- Real user identities used by live rooms, groups and leaderboard
create table if not exists public.ypt_profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default 'Learner',
  avatar_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.ypt_profiles enable row level security;
drop policy if exists "authenticated view ypt profiles" on public.ypt_profiles;
create policy "authenticated view ypt profiles" on public.ypt_profiles for select to authenticated using(true);
drop policy if exists "users create ypt profile" on public.ypt_profiles;
create policy "users create ypt profile" on public.ypt_profiles for insert to authenticated with check(auth.uid()=id);
drop policy if exists "users update ypt profile" on public.ypt_profiles;
create policy "users update ypt profile" on public.ypt_profiles for update to authenticated using(auth.uid()=id) with check(auth.uid()=id);

create or replace function public.create_ypt_profile() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into public.ypt_profiles(id,display_name)
  values(new.id,coalesce(nullif(new.raw_user_meta_data->>'full_name',''),split_part(coalesce(new.email,'Learner'),'@',1)))
  on conflict(id) do nothing;
  return new;
end; $$;
drop trigger if exists on_auth_user_create_ypt_profile on auth.users;
create trigger on_auth_user_create_ypt_profile after insert on auth.users
for each row execute function public.create_ypt_profile();

-- Premium/VIP access. Coupon codes are never selectable from the browser.
create table if not exists public.ypt_memberships (
  user_id uuid primary key references auth.users(id) on delete cascade,
  plan text not null default 'free' check(plan in ('free','premium','vip')),
  active boolean not null default true,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  source text not null default 'admin',
  updated_at timestamptz not null default now()
);
alter table public.ypt_memberships enable row level security;
drop policy if exists "users view own ypt membership" on public.ypt_memberships;
create policy "users view own ypt membership" on public.ypt_memberships for select to authenticated using(auth.uid()=user_id);

create table if not exists public.ypt_access_coupons (
  id uuid primary key default gen_random_uuid(),
  code text unique not null,
  plan text not null check(plan in ('premium','vip')),
  duration_days integer not null check(duration_days between 1 and 3650),
  max_uses integer check(max_uses is null or max_uses>0),
  used_count integer not null default 0 check(used_count>=0),
  active boolean not null default true,
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.ypt_access_coupons enable row level security;
-- Intentionally no browser SELECT policy: codes are validated only inside the RPC.

create table if not exists public.ypt_coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.ypt_access_coupons(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  unique(coupon_id,user_id)
);
alter table public.ypt_coupon_redemptions enable row level security;
drop policy if exists "users view own ypt redemptions" on public.ypt_coupon_redemptions;
create policy "users view own ypt redemptions" on public.ypt_coupon_redemptions for select to authenticated using(auth.uid()=user_id);

create or replace function public.redeem_ypt_access(p_code text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare c public.ypt_access_coupons%rowtype; new_expiry timestamptz; existing_expiry timestamptz;
begin
  if auth.uid() is null then return jsonb_build_object('success',false,'error','Login required'); end if;
  select * into c from public.ypt_access_coupons
  where upper(code)=upper(trim(p_code)) and active=true
    and (expires_at is null or expires_at>now())
  for update;
  if c.id is null then return jsonb_build_object('success',false,'error','Code invalid or expired'); end if;
  if c.max_uses is not null and c.used_count>=c.max_uses then return jsonb_build_object('success',false,'error','Code usage limit reached'); end if;
  if exists(select 1 from public.ypt_coupon_redemptions where coupon_id=c.id and user_id=auth.uid()) then
    return jsonb_build_object('success',false,'error','You already redeemed this code');
  end if;
  select expires_at into existing_expiry from public.ypt_memberships where user_id=auth.uid();
  new_expiry:=greatest(coalesce(existing_expiry,now()),now())+make_interval(days=>c.duration_days);
  insert into public.ypt_memberships(user_id,plan,active,starts_at,expires_at,source,updated_at)
  values(auth.uid(),c.plan,true,now(),new_expiry,'coupon',now())
  on conflict(user_id) do update set plan=excluded.plan,active=true,expires_at=new_expiry,source='coupon',updated_at=now();
  insert into public.ypt_coupon_redemptions(coupon_id,user_id) values(c.id,auth.uid());
  update public.ypt_access_coupons set used_count=used_count+1 where id=c.id;
  return jsonb_build_object('success',true,'plan',c.plan,'expires_at',new_expiry);
end; $$;
revoke all on function public.redeem_ypt_access(text) from public,anon;
grant execute on function public.redeem_ypt_access(text) to authenticated;

-- Real weekly leaderboard with real profile names. Security invoker keeps source RLS active.
drop view if exists public.ypt_weekly_leaderboard;
create view public.ypt_weekly_leaderboard with (security_invoker=true) as
select s.user_id,coalesce(p.display_name,'Learner') as display_name,
       sum(s.duration_seconds)::bigint as focus_seconds,count(*)::bigint as sessions,0::integer as streak
from public.ypt_focus_sessions s
left join public.ypt_profiles p on p.id=s.user_id
where s.session_date>=date_trunc('week',current_date)::date
group by s.user_id,p.display_name;

-- Server-side plan check used by protected Premium/VIP policies.
create or replace function public.ypt_has_access(required_plan text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(
    select 1 from public.ypt_memberships m
    where m.user_id=auth.uid() and m.active=true
      and (m.expires_at is null or m.expires_at>now())
      and case required_plan when 'vip' then m.plan='vip' when 'premium' then m.plan in ('premium','vip') else true end
  );
$$;
revoke all on function public.ypt_has_access(text) from public,anon;
grant execute on function public.ypt_has_access(text) to authenticated;

drop policy if exists "authenticated view ypt live" on public.ypt_live_sessions;
create policy "vip view ypt live" on public.ypt_live_sessions for select to authenticated using(public.ypt_has_access('vip'));
drop policy if exists "ypt own live insert" on public.ypt_live_sessions;
create policy "vip own live insert" on public.ypt_live_sessions for insert to authenticated with check(auth.uid()=user_id and public.ypt_has_access('vip'));
drop policy if exists "ypt own live update" on public.ypt_live_sessions;
create policy "vip own live update" on public.ypt_live_sessions for update to authenticated using(auth.uid()=user_id and public.ypt_has_access('vip')) with check(auth.uid()=user_id and public.ypt_has_access('vip'));

drop policy if exists "view public or joined ypt groups" on public.ypt_study_groups;
create policy "premium view ypt groups" on public.ypt_study_groups for select to authenticated using(public.ypt_has_access('premium') and (privacy='public' or owner_id=auth.uid() or public.ypt_is_group_member(id)));
drop policy if exists "create ypt groups" on public.ypt_study_groups;
create policy "premium create ypt groups" on public.ypt_study_groups for insert to authenticated with check(owner_id=auth.uid() and public.ypt_has_access('premium'));

create or replace function public.get_ypt_weekly_leaderboard()
returns table(user_id uuid,display_name text,focus_seconds bigint,sessions bigint,streak integer)
language sql stable security definer set search_path=public as $$
  select s.user_id,coalesce(p.display_name,'Learner'),sum(s.duration_seconds)::bigint,count(*)::bigint,0::integer
  from public.ypt_focus_sessions s left join public.ypt_profiles p on p.id=s.user_id
  where s.session_date>=date_trunc('week',current_date)::date and public.ypt_has_access('vip')
  group by s.user_id,p.display_name order by sum(s.duration_seconds) desc limit 100;
$$;
revoke all on function public.get_ypt_weekly_leaderboard() from public,anon;
grant execute on function public.get_ypt_weekly_leaderboard() to authenticated;

-- Dashboard live-presence fix: all authenticated real learners can appear live.
drop policy if exists "vip view ypt live" on public.ypt_live_sessions;
create policy "authenticated view ypt live" on public.ypt_live_sessions for select to authenticated using(true);
drop policy if exists "vip own live insert" on public.ypt_live_sessions;
create policy "authenticated own live insert" on public.ypt_live_sessions for insert to authenticated with check(auth.uid()=user_id);
drop policy if exists "vip own live update" on public.ypt_live_sessions;
create policy "authenticated own live update" on public.ypt_live_sessions for update to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
-- Real YPT-style student insights. Only authenticated users can call these RPCs.
-- It shares subject, duration and timer timestamps; private task text is not exposed.
create or replace function public.get_ypt_insight_users()
returns table(
  user_id uuid,
  display_name text,
  avatar_url text,
  today_seconds bigint,
  week_seconds bigint,
  live_now boolean,
  current_subject text
)
language sql stable security definer set search_path=public as $$
  select p.id,p.display_name,p.avatar_url,
    coalesce(sum(s.duration_seconds) filter(where s.session_date=current_date),0)::bigint,
    coalesce(sum(s.duration_seconds) filter(where s.session_date>=date_trunc('week',current_date)::date),0)::bigint,
    coalesce(max((l.status='live' and l.last_heartbeat_at>now()-interval '2 minutes')::int),0)=1,
    max(l.subject) filter(where l.status='live' and l.last_heartbeat_at>now()-interval '2 minutes')
  from public.ypt_profiles p
  left join public.ypt_focus_sessions s on s.user_id=p.id and s.session_date>=date_trunc('week',current_date)::date
  left join public.ypt_live_sessions l on l.user_id=p.id
  where auth.uid() is not null
  group by p.id,p.display_name,p.avatar_url
  order by coalesce(sum(s.duration_seconds) filter(where s.session_date=current_date),0) desc,p.display_name;
$$;
revoke all on function public.get_ypt_insight_users() from public,anon;
grant execute on function public.get_ypt_insight_users() to authenticated;

create or replace function public.get_ypt_user_insight(p_user_id uuid,p_date date)
returns table(id uuid,subject text,duration_seconds integer,started_at timestamptz,ended_at timestamptz)
language sql stable security definer set search_path=public as $$
  select s.id,s.subject,s.duration_seconds,s.started_at,s.ended_at
  from public.ypt_focus_sessions s
  where auth.uid() is not null and s.user_id=p_user_id and s.session_date=p_date
  order by s.started_at;
$$;
revoke all on function public.get_ypt_user_insight(uuid,date) from public,anon;
grant execute on function public.get_ypt_user_insight(uuid,date) to authenticated;

create or replace function public.get_ypt_user_month_totals(p_user_id uuid,p_month date)
returns table(study_date date,total_seconds bigint,sessions bigint)
language sql stable security definer set search_path=public as $$
  select s.session_date,sum(s.duration_seconds)::bigint,count(*)::bigint
  from public.ypt_focus_sessions s
  where auth.uid() is not null and s.user_id=p_user_id
    and s.session_date>=date_trunc('month',p_month)::date
    and s.session_date<(date_trunc('month',p_month)+interval '1 month')::date
  group by s.session_date order by s.session_date;
$$;
revoke all on function public.get_ypt_user_month_totals(uuid,date) from public,anon;
grant execute on function public.get_ypt_user_month_totals(uuid,date) to authenticated;
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
  recovery_email text not null, created_at timestamptz not null default now()
);
alter table public.ypt_login_names enable row level security;
drop policy if exists "users manage own login name" on public.ypt_login_names;
create policy "users manage own login name" on public.ypt_login_names for all to authenticated using(auth.uid()=user_id) with check(auth.uid()=user_id);
create or replace function public.resolve_ypt_login(p_name text) returns text language sql stable security definer set search_path=public as $$select recovery_email from public.ypt_login_names where lower(username)=lower(trim(p_name)) limit 1$$;
revoke all on function public.resolve_ypt_login(text) from public;
grant execute on function public.resolve_ypt_login(text) to anon,authenticated;
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

create table if not exists public.ypt_recovery_rate(username text primary key,failed_attempts integer not null default 0,blocked_until timestamptz,updated_at timestamptz not null default now());
alter table public.ypt_recovery_rate enable row level security;
create or replace function public.recover_ypt_account(p_name text,p_recovery_email text,p_new_password text) returns jsonb language plpgsql security definer set search_path=public,auth as $$
declare account record;rate record;begin if length(p_new_password)<6 then return jsonb_build_object('success',false,'error','Password must be at least 6 characters');end if;select * into rate from public.ypt_recovery_rate where username=lower(trim(p_name)) for update;if rate.blocked_until is not null and rate.blocked_until>now() then return jsonb_build_object('success',false,'error','Too many attempts. Try later.');end if;select user_id,recovery_email into account from public.ypt_login_names where lower(username)=lower(trim(p_name)) limit 1;if account.user_id is null or lower(account.recovery_email)<>lower(trim(p_recovery_email)) then insert into public.ypt_recovery_rate(username,failed_attempts,blocked_until,updated_at) values(lower(trim(p_name)),1,null,now()) on conflict(username) do update set failed_attempts=public.ypt_recovery_rate.failed_attempts+1,blocked_until=case when public.ypt_recovery_rate.failed_attempts+1>=5 then now()+interval '1 hour' else null end,updated_at=now();return jsonb_build_object('success',false,'error','Recovery details do not match');end if;update auth.users set encrypted_password=crypt(p_new_password,gen_salt('bf')),updated_at=now() where id=account.user_id;delete from public.ypt_recovery_rate where username=lower(trim(p_name));return jsonb_build_object('success',true);end;$$;
revoke all on function public.recover_ypt_account(text,text,text) from public;grant execute on function public.recover_ypt_account(text,text,text) to anon,authenticated;
