-- RATHOD HUB 2.0 / correct project: oeacgchzyilgqzaqxssh
-- Run AFTER ypt_wallet.sql. Repeat-safe; no admin credit is added by this file.
-- Prices are server-owned; purchases are one-time, account-bound unlocks.
begin;
create table if not exists public.ypt_store_products (
  code text primary key, name text not null,
  price_paise bigint not null check(price_paise>0), enabled boolean not null default true
);
insert into public.ypt_store_products(code,name,price_paise,enabled) values
 ('analog_timer','Analog Timer',2000,true),('study_report_pdf','Study Report PDF',5000,true)
on conflict(code) do update set name=excluded.name,price_paise=excluded.price_paise,enabled=excluded.enabled;
create table if not exists public.ypt_store_purchases (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 product_code text not null references public.ypt_store_products(code),
 price_paise bigint not null check(price_paise>0),
 request_id uuid not null, purchased_at timestamptz not null default clock_timestamp(),
 unique(user_id,product_code),unique(user_id,request_id)
);
create index if not exists ypt_store_user_date_idx on public.ypt_store_purchases(user_id,purchased_at desc);
create table if not exists public.ypt_store_debits (
 purchase_id uuid not null references public.ypt_store_purchases(id) on delete cascade,
 credit_id uuid not null references public.ypt_wallet_ledger(id) on delete cascade,
 amount_paise bigint not null check(amount_paise>0),primary key(purchase_id,credit_id)
);
alter table public.ypt_store_products enable row level security;
alter table public.ypt_store_purchases enable row level security;
alter table public.ypt_store_debits enable row level security;
revoke all on public.ypt_store_products,public.ypt_store_purchases,public.ypt_store_debits from public,anon,authenticated;
grant select on public.ypt_store_products,public.ypt_store_purchases to authenticated;
drop policy if exists store_catalogue_read on public.ypt_store_products;
create policy store_catalogue_read on public.ypt_store_products for select to authenticated using(true);
drop policy if exists store_own_purchases on public.ypt_store_purchases;
create policy store_own_purchases on public.ypt_store_purchases for select to authenticated using(user_id=auth.uid());

-- Extend allowed credit kinds, preserving existing credits and constraints.
alter table public.ypt_wallet_ledger drop constraint if exists ypt_wallet_ledger_kind_check;
alter table public.ypt_wallet_ledger add constraint ypt_wallet_ledger_kind_check
 check(kind in ('study','referral_inviter','referral_joiner','admin_credit'));

create or replace function public.ypt_store_snapshot() returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure();
begin
 return jsonb_build_object('server_time',clock_timestamp(),'wallet',public.ypt_wallet_snapshot(),
 'products',(select coalesce(jsonb_agg(jsonb_build_object('code',p.code,'name',p.name,'price_paise',p.price_paise,'enabled',p.enabled,
 'owned',exists(select 1 from public.ypt_store_purchases b where b.user_id=u and b.product_code=p.code)) order by p.price_paise),'[]'::jsonb)
 from public.ypt_store_products p),
 'purchases',(select coalesce(jsonb_agg(jsonb_build_object('id',b.id,'product_code',b.product_code,'name',p.name,
 'price_paise',b.price_paise,'purchased_at',b.purchased_at) order by b.purchased_at desc),'[]'::jsonb)
 from public.ypt_store_purchases b join public.ypt_store_products p on p.code=b.product_code where b.user_id=u));
end $$;

create or replace function public.ypt_store_buy(p_product text,p_request uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure(); t timestamptz; p public.ypt_store_products%rowtype;
 owned public.ypt_store_purchases%rowtype; credit record; cost bigint; debit bigint; purchase_uuid uuid;
begin
 if p_request is null then raise exception 'Purchase request ID required';end if;
 -- Same lock as focus credits: two tabs cannot overspend the same account.
 perform 1 from public.ypt_wallet_accounts where user_id=u for update;
 select * into owned from public.ypt_store_purchases where user_id=u and product_code=p_product;
 if found then return public.ypt_store_snapshot()||jsonb_build_object('purchase_status','already_owned');end if;
 if exists(select 1 from public.ypt_store_purchases where user_id=u and request_id=p_request) then
  raise exception 'Purchase request already used for another item';end if;
 select * into p from public.ypt_store_products where code=p_product for share;
 if not found or not p.enabled then raise exception 'Item is not available';end if;
 t:=clock_timestamp();cost:=p.price_paise;
 if (select coalesce(sum(remaining_paise),0) from public.ypt_wallet_ledger where user_id=u and expires_at>t)<cost then
  raise exception 'Insufficient unexpired wallet credits';end if;
 insert into public.ypt_store_purchases(user_id,product_code,price_paise,request_id,purchased_at)
 values(u,p.code,p.price_paise,p_request,t) returning id into purchase_uuid;
 -- Spend earliest-expiring credits first; no negative ledger entries.
 for credit in select id,remaining_paise from public.ypt_wallet_ledger
 where user_id=u and expires_at>t and remaining_paise>0 order by expires_at,earned_at,id for update loop
  debit:=least(cost,credit.remaining_paise);
  update public.ypt_wallet_ledger set remaining_paise=remaining_paise-debit where id=credit.id;
  insert into public.ypt_store_debits(purchase_id,credit_id,amount_paise) values(purchase_uuid,credit.id,debit);
  cost:=cost-debit;exit when cost=0;
 end loop;
 if cost<>0 then raise exception 'Purchase could not be completed; no credits charged';end if;
 return public.ypt_store_snapshot()||jsonb_build_object('purchase_status','purchased','purchase_id',purchase_uuid);
end $$;

create or replace function public.ypt_store_report(p_period text,p_anchor date default null) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=auth.uid(); today_date date:=(clock_timestamp() at time zone 'Asia/Kolkata')::date;
 anchor_date date:=coalesce(p_anchor,today_date);from_date date;to_date date;student_name text;
begin
 if u is null then raise exception 'Login required' using errcode='28000';end if;
 if not exists(select 1 from public.ypt_store_purchases where user_id=u and product_code='study_report_pdf') then
  raise exception 'Buy Study Report PDF first';end if;
 if p_period='week' then
  if anchor_date>today_date then raise exception 'Choose a past date or today';end if;
  to_date:=anchor_date;from_date:=to_date-6;
 elsif p_period='month' then
  from_date:=date_trunc('month',anchor_date)::date;
  if from_date>today_date then raise exception 'Choose a past month or this month';end if;
  to_date:=least((from_date+interval '1 month'-interval '1 day')::date,today_date);
 else raise exception 'Choose week or month';end if;
 if (select count(*) from public.ypt_focus_sessions where user_id=u and session_date between from_date and to_date)>5000
 or (select count(*) from public.ypt_daily_tasks where user_id=u and task_date between from_date and to_date)>5000 then
  raise exception 'Too many entries in this range; select a 7-day report';end if;
 select display_name into student_name from public.ypt_profiles where id=u;
 return jsonb_build_object('name',coalesce(nullif(student_name,''),'Learner'),'period',p_period,
 'from_date',from_date,'to_date',to_date,'timezone','Asia/Kolkata','generated_at',clock_timestamp(),
 'source','Cloud-saved study sessions and planner tasks; not independently verified attendance.',
 'sessions',(select coalesce(jsonb_agg(jsonb_build_object('id',s.id,'date',s.session_date,'subject',s.subject,
 'seconds',s.duration_seconds,'started_at',s.started_at,'ended_at',s.ended_at,'focus_score',to_jsonb(s)->'focus_score')
 order by s.session_date,s.started_at,s.id),'[]'::jsonb) from public.ypt_focus_sessions s
 where s.user_id=u and s.session_date between from_date and to_date),
 'tasks',(select coalesce(jsonb_agg(jsonb_build_object('id',d.id,'date',d.task_date,'title',d.title,
 'subject',d.subject,'completed',d.completed) order by d.task_date,d.created_at,d.id),'[]'::jsonb)
 from public.ypt_daily_tasks d where d.user_id=u and d.task_date between from_date and to_date));
end $$;
revoke all on function public.ypt_store_snapshot(),public.ypt_store_buy(text,uuid),public.ypt_store_report(text,date) from public,anon;
grant execute on function public.ypt_store_snapshot(),public.ypt_store_buy(text,uuid),public.ypt_store_report(text,date) to authenticated;
comment on table public.ypt_store_purchases is 'One-time account-bound unlocks bought atomically with unexpired reward credits. No cash withdrawal.';
notify pgrst,'reload schema';
commit;
