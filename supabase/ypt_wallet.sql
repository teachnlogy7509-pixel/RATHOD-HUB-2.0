-- RATHOD HUB 2.0 WALLET -- run ONLY in oeacgchzyilgqzaqxssh.
-- App reward credits, not bank cash. No old/client-entered study time is converted.
-- Repeat-safe; preserves existing study data, coupons, memberships and settings.
begin;
create table if not exists public.ypt_wallet_config (
  singleton boolean primary key default true check(singleton),
  enabled_at timestamptz not null default clock_timestamp()
);
insert into public.ypt_wallet_config(singleton) values(true) on conflict do nothing;
create table if not exists public.ypt_wallet_accounts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  referral_code text not null unique default upper(substr(replace(gen_random_uuid()::text,'-',''),1,12)),
  study_seconds bigint not null default 0 check(study_seconds>=0),
  credited_blocks bigint not null default 0 check(credited_blocks>=0),
  running boolean not null default false,
  monitor_id uuid,
  last_tick timestamptz,
  created_at timestamptz not null default clock_timestamp()
);
create table if not exists public.ypt_wallet_ledger (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  kind text not null check(kind in ('study','referral_inviter','referral_joiner')),
  amount_paise bigint not null check(amount_paise>0),
  remaining_paise bigint not null check(remaining_paise>=0 and remaining_paise<=amount_paise),
  source_key text not null,
  earned_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null,
  unique(user_id,kind,source_key),
  check(expires_at>earned_at)
);
create index if not exists ypt_wallet_user_earned_idx on public.ypt_wallet_ledger(user_id,earned_at desc,id desc);
create index if not exists ypt_wallet_user_expiry_idx on public.ypt_wallet_ledger(user_id,expires_at);
create table if not exists public.ypt_wallet_referrals (
  referred_user_id uuid primary key references auth.users(id) on delete cascade,
  referrer_user_id uuid not null references auth.users(id) on delete cascade,
  claimed_at timestamptz not null default clock_timestamp(),
  check(referrer_user_id<>referred_user_id)
);
-- Referral intent is captured at signup, not editable later by clients.
create table if not exists public.ypt_wallet_referral_intents (
  referred_user_id uuid primary key references auth.users(id) on delete cascade,
  referral_code text not null,
  created_at timestamptz not null default clock_timestamp()
);
alter table public.ypt_wallet_referral_intents enable row level security;
revoke all on public.ypt_wallet_referral_intents from public,anon,authenticated;
create or replace function public.ypt_wallet_capture_invite() returns trigger
language plpgsql security definer set search_path=pg_catalog,public as $$
declare code text:=upper(trim(new.raw_user_meta_data->>'referral_code'));
begin
  if code is not null and code~'^[A-F0-9]{12}$' and exists(
    select 1 from public.ypt_wallet_accounts a where a.referral_code=code and a.user_id<>new.id
  ) then
    insert into public.ypt_wallet_referral_intents(referred_user_id,referral_code)
      values(new.id,code) on conflict do nothing;
  end if;
  return new;
end $$;
revoke all on function public.ypt_wallet_capture_invite() from public,anon,authenticated;
drop trigger if exists ypt_wallet_capture_invite on auth.users;
create trigger ypt_wallet_capture_invite after insert on auth.users for each row execute function public.ypt_wallet_capture_invite();
alter table public.ypt_wallet_config enable row level security;
alter table public.ypt_wallet_accounts enable row level security;
alter table public.ypt_wallet_ledger enable row level security;
alter table public.ypt_wallet_referrals enable row level security;
revoke all on public.ypt_wallet_config,public.ypt_wallet_accounts,public.ypt_wallet_ledger,public.ypt_wallet_referrals from public,anon,authenticated;
grant select on public.ypt_wallet_accounts,public.ypt_wallet_ledger,public.ypt_wallet_referrals to authenticated;
drop policy if exists wallet_own_account on public.ypt_wallet_accounts;
create policy wallet_own_account on public.ypt_wallet_accounts for select to authenticated using(user_id=auth.uid());
drop policy if exists wallet_own_ledger on public.ypt_wallet_ledger;
create policy wallet_own_ledger on public.ypt_wallet_ledger for select to authenticated using(user_id=auth.uid());
drop policy if exists wallet_own_referrals on public.ypt_wallet_referrals;
create policy wallet_own_referrals on public.ypt_wallet_referrals for select to authenticated using(referrer_user_id=auth.uid() or referred_user_id=auth.uid());

create or replace function public.ypt_wallet_ensure() returns uuid
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=auth.uid();
begin
  if u is null then raise exception 'Login required' using errcode='28000'; end if;
  insert into public.ypt_wallet_accounts(user_id) values(u) on conflict(user_id) do nothing;
  return u;
end $$;
revoke all on function public.ypt_wallet_ensure() from public,anon,authenticated;

create or replace function public.ypt_wallet_history(p_before timestamptz default null,p_before_id uuid default null)
returns jsonb language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure(); t timestamptz:=clock_timestamp(); since_at timestamptz;
begin
  since_at:=((t at time zone 'Asia/Kolkata')::date-6)::timestamp at time zone 'Asia/Kolkata';
  return (select coalesce(jsonb_agg(jsonb_build_object(
    'id',x.id,'kind',x.kind,'amount_paise',x.amount_paise,'earned_at',x.earned_at,
    'expires_at',x.expires_at,'remaining_paise',x.remaining_paise,
    'status',case when x.expires_at<=t then 'expired' when x.remaining_paise=0 then 'used' else 'available' end
  ) order by x.earned_at desc,x.id desc),'[]'::jsonb)
  from (select * from public.ypt_wallet_ledger l where l.user_id=u and l.earned_at>=since_at and l.earned_at<=t
    and (p_before is null or (l.earned_at,l.id)<(p_before,coalesce(p_before_id,'ffffffff-ffff-ffff-ffff-ffffffffffff'::uuid)))
    order by l.earned_at desc,l.id desc limit 50) x);
end $$;

create or replace function public.ypt_wallet_snapshot() returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure(); t timestamptz:=clock_timestamp();
  a public.ypt_wallet_accounts%rowtype; today_date date:=(t at time zone 'Asia/Kolkata')::date;
  today_at timestamptz; since_at timestamptz; totals jsonb; days jsonb; eligible boolean;
begin
  select * into a from public.ypt_wallet_accounts where user_id=u;
  today_at:=today_date::timestamp at time zone 'Asia/Kolkata';
  since_at:=(today_date-6)::timestamp at time zone 'Asia/Kolkata';
  select jsonb_build_object(
    'available_paise',coalesce(sum(remaining_paise) filter(where expires_at>t),0),
    'today_earned_paise',coalesce(sum(amount_paise) filter(where earned_at>=today_at and earned_at<=t),0),
    'week_earned_paise',coalesce(sum(amount_paise) filter(where earned_at>=since_at and earned_at<=t),0),
    'total_earned_paise',coalesce(sum(amount_paise),0),
    'expired_paise',coalesce(sum(remaining_paise) filter(where expires_at<=t),0),
    'expiring_7d_paise',coalesce(sum(remaining_paise) filter(where expires_at>t and expires_at<=t+interval '7 days'),0)
  ) into totals from public.ypt_wallet_ledger where user_id=u;
  select jsonb_agg(jsonb_build_object('date',d.day_date,'amount_paise',coalesce(q.amount,0)) order by d.day_date)
    into days from (select today_date-i day_date from generate_series(0,6) i) d
    left join (select (earned_at at time zone 'Asia/Kolkata')::date day_date,sum(amount_paise) amount
      from public.ypt_wallet_ledger where user_id=u and earned_at>=since_at and earned_at<=t group by 1) q using(day_date);
  select exists(select 1 from auth.users x,public.ypt_wallet_config c where x.id=u
    and x.created_at>=c.enabled_at and x.email_confirmed_at is not null
    and exists(select 1 from public.ypt_wallet_referral_intents i where i.referred_user_id=u))
    and not exists(select 1 from public.ypt_wallet_referrals where referred_user_id=u) into eligible;
  return totals||jsonb_build_object('server_time',t,'timezone','Asia/Kolkata',
    'study_seconds',a.study_seconds,'progress_seconds',a.study_seconds%28800,
    'referral_code',a.referral_code,'can_claim_referral',eligible,
    'pending_referral_code',(select referral_code from public.ypt_wallet_referral_intents where referred_user_id=u),
    'referral_claimed',exists(select 1 from public.ypt_wallet_referrals where referred_user_id=u),
    'referrals_count',(select count(*) from public.ypt_wallet_referrals where referrer_user_id=u),
    'seven_day_earnings',days,'transactions',public.ypt_wallet_history());
end $$;

create or replace function public.ypt_wallet_focus(p_action text,p_monitor uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure(); t timestamptz; a public.ypt_wallet_accounts%rowtype;
  delta_seconds bigint:=0; blocks bigint; expiry timestamptz;
begin
  if p_monitor is null or p_action is null or p_action not in ('start','tick','pause','finish') then raise exception 'Invalid focus request'; end if;
  select * into a from public.ypt_wallet_accounts where user_id=u for update;
  t:=clock_timestamp();
  if a.running and a.monitor_id is distinct from p_monitor and a.last_tick>t-interval '90 seconds' then
    raise exception 'Wallet rewards already running on another tab or device';
  end if;
  if p_action='start' then
    -- A fresh/reconnected monitor starts now; no offline/backdated credit.
    if a.running and a.monitor_id=p_monitor and a.last_tick>t-interval '90 seconds' then
      delta_seconds:=greatest(0,least(45,floor(extract(epoch from(t-a.last_tick)))::bigint));
    end if;
    a.running:=true;a.monitor_id:=p_monitor;
  else
    if a.monitor_id is distinct from p_monitor then raise exception 'Start wallet focus on this device first'; end if;
    if a.running and a.last_tick>t-interval '90 seconds' then
      delta_seconds:=greatest(0,least(45,floor(extract(epoch from(t-a.last_tick)))::bigint));
    end if;
    if p_action in ('pause','finish') then a.running:=false; end if;
  end if;
  a.study_seconds:=a.study_seconds+delta_seconds;blocks:=a.study_seconds/28800;
  if blocks>a.credited_blocks then
    expiry:=((t at time zone 'Asia/Kolkata')+interval '6 months') at time zone 'Asia/Kolkata';
    insert into public.ypt_wallet_ledger(user_id,kind,amount_paise,remaining_paise,source_key,earned_at,expires_at)
      values(u,'study',(blocks-a.credited_blocks)*500,(blocks-a.credited_blocks)*500,'block-'||blocks,t,expiry)
      on conflict(user_id,kind,source_key) do nothing;
  end if;
  update public.ypt_wallet_accounts set study_seconds=a.study_seconds,credited_blocks=blocks,
    running=a.running,monitor_id=a.monitor_id,last_tick=t where user_id=u;
  return public.ypt_wallet_snapshot();
end $$;

create or replace function public.ypt_wallet_claim_referral(p_code text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure(); inviter uuid; t timestamptz; expiry timestamptz;
  created_time timestamptz; confirmed_time timestamptz; enabled_time timestamptz; existing uuid;
begin
  perform 1 from public.ypt_wallet_accounts where user_id=u for update;
  t:=clock_timestamp();
  select referrer_user_id into existing from public.ypt_wallet_referrals where referred_user_id=u;
  if existing is not null then return public.ypt_wallet_snapshot()||jsonb_build_object('claim_status','already_claimed'); end if;
  select created_at,email_confirmed_at into created_time,confirmed_time from auth.users where id=u;
  select enabled_at into enabled_time from public.ypt_wallet_config where singleton=true;
  if created_time<enabled_time then
    raise exception 'Referral rewards are only for new signups using an invite link'; end if;
  if confirmed_time is null then raise exception 'Confirm your signup email, then claim your referral'; end if;
  select user_id into inviter from public.ypt_wallet_accounts where referral_code=upper(trim(p_code));
  if inviter is null then raise exception 'Invalid referral code'; end if;
  if inviter=u then raise exception 'Self-referral is not allowed'; end if;
  if not exists(select 1 from public.ypt_wallet_referral_intents where referred_user_id=u and referral_code=upper(trim(p_code))) then
    raise exception 'Referral bonus requires a new account created with this invite link'; end if;
  if not exists(select 1 from auth.users where id=inviter and created_at<created_time) then
    raise exception 'Referral must come from an existing account'; end if;
  insert into public.ypt_wallet_referrals(referred_user_id,referrer_user_id,claimed_at) values(u,inviter,t);
  expiry:=((t at time zone 'Asia/Kolkata')+interval '6 months') at time zone 'Asia/Kolkata';
  insert into public.ypt_wallet_ledger(user_id,kind,amount_paise,remaining_paise,source_key,earned_at,expires_at) values
    (inviter,'referral_inviter',1000,1000,'ref-'||u,t,expiry),
    (u,'referral_joiner',1000,1000,'ref-'||u,t,expiry);
  return public.ypt_wallet_snapshot()||jsonb_build_object('claim_status','credited_both');
end $$;
revoke all on function public.ypt_wallet_history(timestamptz,uuid),public.ypt_wallet_snapshot(),public.ypt_wallet_focus(text,uuid),public.ypt_wallet_claim_referral(text) from public,anon;
grant execute on function public.ypt_wallet_history(timestamptz,uuid),public.ypt_wallet_snapshot(),public.ypt_wallet_focus(text,uuid),public.ypt_wallet_claim_referral(text) to authenticated;
comment on table public.ypt_wallet_ledger is 'Protected reward-credit ledger in paise. No client writes, no cash withdrawals, no purchases enabled yet.';
notify pgrst,'reload schema';
commit;
