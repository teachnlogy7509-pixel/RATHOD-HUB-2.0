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
