-- YPT Study by Rathod: ALL-IN-ONE (safe: kuch table missing ho to ye khud bana deta hai; dobara chalane me bhi dikkat nahi)

-- 0) Zaroori tables (agar pehle se hain to kuch nahi badlega)
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
create or replace function public.ypt_has_access(required_plan text)
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.ypt_memberships m
    where m.user_id=auth.uid() and m.active=true and (m.expires_at is null or m.expires_at>now())
      and case required_plan when 'vip' then m.plan='vip' when 'premium' then m.plan in ('premium','vip') else true end);
$$;
revoke all on function public.ypt_has_access(text) from public,anon;
grant execute on function public.ypt_has_access(text) to authenticated;

create table if not exists public.ypt_admins (user_id uuid primary key references auth.users(id) on delete cascade, created_at timestamptz not null default now());
alter table public.ypt_admins enable row level security;
create or replace function public.ypt_is_admin() returns boolean language sql stable security definer set search_path=public as $$select exists(select 1 from public.ypt_admins where user_id=auth.uid())$$;
revoke all on function public.ypt_is_admin() from public,anon; grant execute on function public.ypt_is_admin() to authenticated;

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
drop policy if exists "create ypt groups" on public.ypt_study_groups;
drop policy if exists "premium create ypt groups" on public.ypt_study_groups;
create policy "premium create ypt groups" on public.ypt_study_groups for insert to authenticated with check(owner_id=auth.uid() and public.ypt_has_access('premium'));
drop policy if exists "owner updates ypt group" on public.ypt_study_groups;
create policy "owner updates ypt group" on public.ypt_study_groups for update to authenticated using(owner_id=auth.uid()) with check(owner_id=auth.uid());
drop policy if exists "members view ypt memberships" on public.ypt_group_members;
create policy "members view ypt memberships" on public.ypt_group_members for select to authenticated using(public.ypt_is_group_member(group_id));
drop policy if exists "join public ypt group" on public.ypt_group_members;
create policy "join public ypt group" on public.ypt_group_members for insert to authenticated with check(user_id=auth.uid() and exists(select 1 from public.ypt_study_groups g where g.id=group_id and (g.privacy='public' or g.owner_id=auth.uid())));
drop policy if exists "leave ypt group" on public.ypt_group_members;
create policy "leave ypt group" on public.ypt_group_members for delete to authenticated using(user_id=auth.uid());

create table if not exists public.ypt_live_chat (
  id uuid primary key default gen_random_uuid(), user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null, message text not null check(length(trim(message)) between 1 and 300), created_at timestamptz not null default now()
);
alter table public.ypt_live_chat enable row level security;
create index if not exists ypt_live_chat_created_idx on public.ypt_live_chat(created_at desc);
do $$ begin alter publication supabase_realtime add table public.ypt_live_chat; exception when others then null; end $$;

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
create table if not exists public.ypt_coupon_redemptions (
  id uuid primary key default gen_random_uuid(),
  coupon_id uuid not null references public.ypt_access_coupons(id) on delete restrict,
  user_id uuid not null references auth.users(id) on delete cascade,
  redeemed_at timestamptz not null default now(),
  unique(coupon_id,user_id)
);
alter table public.ypt_coupon_redemptions enable row level security;

-- 1-4) GROUP JOIN FIX

-- 1) Har logged-in student public groups dekh sake (create abhi bhi Premium ke liye)
drop policy if exists "students view public groups" on public.ypt_study_groups;
create policy "students view public groups" on public.ypt_study_groups for select to authenticated
  using (privacy='public' or owner_id=auth.uid() or public.ypt_is_group_member(id));

-- 2) Group banate hi owner apne aap member ban jaye
create or replace function public.ypt_group_owner_member() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  insert into public.ypt_group_members(group_id,user_id,role) values(new.id,new.owner_id,'owner') on conflict do nothing;
  return new;
end $$;
drop trigger if exists ypt_group_owner_member_t on public.ypt_study_groups;
create trigger ypt_group_owner_member_t after insert on public.ypt_study_groups
  for each row execute function public.ypt_group_owner_member();
insert into public.ypt_group_members(group_id,user_id,role)
  select id,owner_id,'owner' from public.ypt_study_groups on conflict do nothing;

-- 3) Join (premium/free dono student)
create or replace function public.join_ypt_group(p_group uuid) returns jsonb
language plpgsql security definer set search_path=public as $$
declare g public.ypt_study_groups%rowtype;
begin
  if auth.uid() is null then return jsonb_build_object('success',false,'error','Login required'); end if;
  select * into g from public.ypt_study_groups where id=p_group;
  if g.id is null then return jsonb_build_object('success',false,'error','Group nahi mila'); end if;
  if g.privacy<>'public' and g.owner_id<>auth.uid() then return jsonb_build_object('success',false,'error','Ye private group hai'); end if;
  insert into public.ypt_group_members(group_id,user_id,role)
    values(p_group,auth.uid(),case when g.owner_id=auth.uid() then 'owner' else 'member' end) on conflict do nothing;
  return jsonb_build_object('success',true);
end $$;
revoke all on function public.join_ypt_group(uuid) from public,anon;
grant execute on function public.join_ypt_group(uuid) to authenticated;

-- 4) Groups list with sahi member count
create or replace function public.get_ypt_groups()
returns table(id uuid,name text,owner_id uuid,privacy text,weekly_goal_hours integer,member_count bigint,is_member boolean)
language sql stable security definer set search_path=public as $$
  select g.id,g.name,g.owner_id,g.privacy,g.weekly_goal_hours,
    (select count(*) from public.ypt_group_members m where m.group_id=g.id),
    exists(select 1 from public.ypt_group_members m where m.group_id=g.id and m.user_id=auth.uid())
  from public.ypt_study_groups g
  where auth.uid() is not null and (g.privacy='public' or g.owner_id=auth.uid()
    or exists(select 1 from public.ypt_group_members m where m.group_id=g.id and m.user_id=auth.uid()))
  order by g.created_at desc limit 100
$$;
revoke all on function public.get_ypt_groups() from public,anon;
grant execute on function public.get_ypt_groups() to authenticated;

-- 5) Group ke members + is hafte ki study (profiles/focus_sessions table ho tabhi banega)
do $do$ begin
  if to_regclass('public.ypt_profiles') is not null and to_regclass('public.ypt_focus_sessions') is not null then
    execute $f$create or replace function public.get_ypt_group_members(p_group uuid)
returns table(user_id uuid,display_name text,avatar_url text,role text,week_seconds bigint)
language sql stable security definer set search_path=public as $$
  select m.user_id,coalesce(p.display_name,'Learner'),p.avatar_url,m.role,
    coalesce((select sum(s.duration_seconds) from public.ypt_focus_sessions s
      where s.user_id=m.user_id and s.session_date>=date_trunc('week',current_date)::date),0)::bigint
  from public.ypt_group_members m left join public.ypt_profiles p on p.id=m.user_id
  where m.group_id=p_group and exists(select 1 from public.ypt_group_members x where x.group_id=p_group and x.user_id=auth.uid())
  order by 5 desc
$$;$f$;
    execute 'revoke all on function public.get_ypt_group_members(uuid) from public,anon';
    execute 'grant execute on function public.get_ypt_group_members(uuid) to authenticated';
  else raise notice 'ypt_profiles/ypt_focus_sessions missing - members list skipped';
  end if;
end $do$;

-- 7) LIVE CHAT VIP + 3 DIN AUTO DELETE
-- 1) 3 din se purane messages delete karne wala function
create or replace function public.purge_ypt_live_chat() returns void
language sql security definer set search_path=public as $$
  delete from public.ypt_live_chat where created_at < now() - interval '3 days'
$$;
revoke all on function public.purge_ypt_live_chat() from public,anon;
grant execute on function public.purge_ypt_live_chat() to authenticated;

-- 2) Naya message aate hi purane (3 din+) apne aap delete
create or replace function public.ypt_live_chat_autopurge() returns trigger
language plpgsql security definer set search_path=public as $$
begin
  delete from public.ypt_live_chat where created_at < now() - interval '3 days';
  return null;
end $$;
drop trigger if exists ypt_live_chat_autopurge_t on public.ypt_live_chat;
create trigger ypt_live_chat_autopurge_t after insert on public.ypt_live_chat
  for each statement execute function public.ypt_live_chat_autopurge();

-- 3) Sirf VIP (ya admin) padh/likh sake; 3 din se purana kisi ko dikhe hi nahi
drop policy if exists "authenticated read live chat" on public.ypt_live_chat;
drop policy if exists "vip read live chat" on public.ypt_live_chat;
create policy "vip read live chat" on public.ypt_live_chat for select to authenticated
  using ((public.ypt_has_access('vip') or public.ypt_is_admin()) and created_at > now() - interval '3 days');
drop policy if exists "authenticated write own live chat" on public.ypt_live_chat;
drop policy if exists "vip write own live chat" on public.ypt_live_chat;
create policy "vip write own live chat" on public.ypt_live_chat for insert to authenticated
  with check (auth.uid()=user_id and (public.ypt_has_access('vip') or public.ypt_is_admin()));

-- 4) Abhi ke saare purane messages turant delete
select public.purge_ypt_live_chat();

-- 5) Har ghante automatic safai (agar pg_cron available ho; warna upar wale trigger se hota rahega)
do $$ begin
  create extension if not exists pg_cron;
  perform cron.unschedule('ypt_live_chat_purge') where exists(select 1 from cron.job where jobname='ypt_live_chat_purge');
  perform cron.schedule('ypt_live_chat_purge','0 * * * *','select public.purge_ypt_live_chat()');
exception when others then raise notice 'pg_cron not available: %', sqlerrm; end $$;

-- 6) Community reactions: 😂 😢 allow (community table ho tabhi)
do $do$ declare c text; begin
  if to_regclass('public.ypt_community_reactions') is not null then
    for c in select conname from pg_constraint where conrelid='public.ypt_community_reactions'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%reaction_type%' loop
      execute format('alter table public.ypt_community_reactions drop constraint %I', c);
    end loop;
    alter table public.ypt_community_reactions add constraint ypt_community_reactions_reaction_type_check
      check (reaction_type in ('👍','❤️','🔥','🎉','💡','👏','😂','😢'));
  else raise notice 'community reactions table missing - skipped';
  end if;
end $do$;

-- 8) WELCOME COUPON
-- 2) Welcome coupon (login par sabko dikhe, redeem ke baad hat jaye)
alter table public.ypt_access_coupons add column if not exists show_to_all boolean not null default false;

create or replace function public.get_ypt_public_coupon()
returns table(code text, plan text, duration_days integer)
language sql stable security definer set search_path=public as $$
  select c.code,c.plan,c.duration_days
  from public.ypt_access_coupons c
  where auth.uid() is not null and c.show_to_all and c.active
    and (c.expires_at is null or c.expires_at>now())
    and (c.max_uses is null or c.used_count<c.max_uses)
    and not exists(select 1 from public.ypt_coupon_redemptions r where r.coupon_id=c.id and r.user_id=auth.uid())
  order by c.created_at desc limit 1
$$;
revoke all on function public.get_ypt_public_coupon() from public,anon;
grant execute on function public.get_ypt_public_coupon() to authenticated;

-- 3) Coupon "RATHOD HUB 2.0 GIFT" ko sabko dikhao (spelling/space/dash ka farak nahi padta)
update public.ypt_access_coupons set show_to_all=true
 where regexp_replace(upper(code),'[^A-Z0-9]','','g')='RATHODHUB20GIFT'
returning code, plan, duration_days, max_uses, used_count, active, expires_at, show_to_all;
