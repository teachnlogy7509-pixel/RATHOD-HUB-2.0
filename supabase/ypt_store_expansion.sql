-- Additive Reward Store expansion. Existing purchases, ledger and features are preserved.
-- One-time pack prices are enforced on the server; Android widget is free.
begin;
insert into public.ypt_store_products(code,name,price_paise,enabled) values
('theme_pack','Premium Themes & Timer Skins',4000,true),
('profile_frame','Profile Frames',3000,true),('name_effect','Name Effects',6000,true),
('focus_celebration','Focus Celebrations',8000,true),('custom_dashboard','Custom Dashboard',10000,true),
('group_customization','Group Customization',12000,true),('friend_gift','Friend Gift Pass',15000,true),
('voice_revision','Voice Revision',20000,true)
on conflict(code) do update set name=excluded.name,price_paise=excluded.price_paise,enabled=excluded.enabled;
create table if not exists public.ypt_store_preferences (
 user_id uuid primary key references auth.users(id) on delete cascade,
 settings jsonb not null default '{}'::jsonb,updated_at timestamptz not null default clock_timestamp());
create table if not exists public.ypt_store_styles (
 user_id uuid primary key references auth.users(id) on delete cascade,
 frame text not null default 'none',name_effect text not null default 'none');
create table if not exists public.ypt_store_group_styles (
 group_id uuid primary key references public.ypt_study_groups(id) on delete cascade,
 theme text not null default 'gold',icon text not null default '📚',tagline text not null default '',
 updated_at timestamptz not null default clock_timestamp());
create table if not exists public.ypt_store_gifts (
 id uuid primary key default gen_random_uuid(),sender_id uuid references auth.users(id) on delete set null,
 recipient_id uuid references auth.users(id) on delete set null,
 product_code text not null references public.ypt_store_products(code),price_paise bigint not null check(price_paise>0),
 request_id uuid not null,created_at timestamptz not null default clock_timestamp(),
 check(sender_id<>recipient_id),unique(recipient_id,product_code),unique(sender_id,request_id));
-- Preserve the receiver's permanent unlock and sender's receipt after account deletion.
alter table public.ypt_store_gifts alter column sender_id drop not null;
alter table public.ypt_store_gifts alter column recipient_id drop not null;
alter table public.ypt_store_gifts drop constraint if exists ypt_store_gifts_sender_id_fkey;
alter table public.ypt_store_gifts drop constraint if exists ypt_store_gifts_recipient_id_fkey;
alter table public.ypt_store_gifts add constraint ypt_store_gifts_sender_id_fkey foreign key(sender_id) references auth.users(id) on delete set null;
alter table public.ypt_store_gifts add constraint ypt_store_gifts_recipient_id_fkey foreign key(recipient_id) references auth.users(id) on delete set null;
create index if not exists ypt_store_gifts_sender_idx on public.ypt_store_gifts(sender_id,created_at desc);
create table if not exists public.ypt_store_gift_debits (
 gift_id uuid not null references public.ypt_store_gifts(id) on delete cascade,
 credit_id uuid not null references public.ypt_wallet_ledger(id) on delete cascade,
 amount_paise bigint not null check(amount_paise>0),primary key(gift_id,credit_id));
alter table public.ypt_store_preferences enable row level security;
alter table public.ypt_store_styles enable row level security;
alter table public.ypt_store_group_styles enable row level security;
alter table public.ypt_store_gifts enable row level security;
alter table public.ypt_store_gift_debits enable row level security;
revoke all on public.ypt_store_preferences,public.ypt_store_styles,public.ypt_store_group_styles,public.ypt_store_gifts,public.ypt_store_gift_debits from public,anon,authenticated;
grant select on public.ypt_store_preferences,public.ypt_store_styles,public.ypt_store_group_styles,public.ypt_store_gifts to authenticated;
drop policy if exists store_preferences_own on public.ypt_store_preferences;
create policy store_preferences_own on public.ypt_store_preferences for select to authenticated using(user_id=auth.uid());
drop policy if exists store_styles_read on public.ypt_store_styles;
create policy store_styles_read on public.ypt_store_styles for select to authenticated using(true);
drop policy if exists store_gifts_own on public.ypt_store_gifts;
create policy store_gifts_own on public.ypt_store_gifts for select to authenticated using(sender_id=auth.uid() or recipient_id=auth.uid());
drop policy if exists store_group_styles_read on public.ypt_store_group_styles;
create policy store_group_styles_read on public.ypt_store_group_styles for select to authenticated using(exists(
 select 1 from public.ypt_study_groups g where g.id=group_id and (g.privacy='public' or g.owner_id=auth.uid()
 or exists(select 1 from public.ypt_group_members m where m.group_id=g.id and m.user_id=auth.uid()))));
create or replace function public.ypt_store_owns(p_user uuid,p_product text) returns boolean
language sql stable security definer set search_path=pg_catalog,public as $$
 select exists(select 1 from public.ypt_store_purchases where user_id=p_user and product_code=p_product)
 or exists(select 1 from public.ypt_store_gifts where recipient_id=p_user and product_code=p_product)
$$;
revoke all on function public.ypt_store_owns(uuid,text) from public,anon,authenticated;
create or replace function public.ypt_store_snapshot() returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure();
begin
 return jsonb_build_object('server_time',clock_timestamp(),'wallet',public.ypt_wallet_snapshot(),
 'products',(select coalesce(jsonb_agg(jsonb_build_object('code',p.code,'name',p.name,'price_paise',p.price_paise,'enabled',p.enabled,
 'owned',public.ypt_store_owns(u,p.code)) order by p.price_paise),'[]'::jsonb) from public.ypt_store_products p),
 'preferences',coalesce((select settings from public.ypt_store_preferences where user_id=u),'{}'::jsonb),
 'purchases',(select coalesce(jsonb_agg(q.item order by q.at desc),'[]'::jsonb) from (
 select b.purchased_at as at,jsonb_build_object('id',b.id,'product_code',b.product_code,'name',p.name,
 'price_paise',b.price_paise,'purchased_at',b.purchased_at) as item from public.ypt_store_purchases b
 join public.ypt_store_products p on p.code=b.product_code where b.user_id=u
 union all select g.created_at,jsonb_build_object('id',g.id,'product_code',g.product_code,'name','Gift · '||p.name,
 'price_paise',g.price_paise,'purchased_at',g.created_at) from public.ypt_store_gifts g
 join public.ypt_store_products p on p.code=g.product_code where g.sender_id=u)q),
 'received_gifts',(select coalesce(jsonb_agg(jsonb_build_object('id',g.id,'name',p.name,'product_code',g.product_code,
 'sender_name',coalesce(s.display_name,'Learner'),'received_at',g.created_at) order by g.created_at desc),'[]'::jsonb)
 from public.ypt_store_gifts g join public.ypt_store_products p on p.code=g.product_code
 left join public.ypt_profiles s on s.id=g.sender_id where g.recipient_id=u));
end $$;
create or replace function public.ypt_store_buy(p_product text,p_request uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure(); t timestamptz; p public.ypt_store_products%rowtype;
 owned public.ypt_store_purchases%rowtype; credit record; cost bigint; debit bigint; purchase_uuid uuid;
begin
 if p_request is null then raise exception 'Purchase request ID required';end if;
 -- Same lock as focus credits: two tabs cannot overspend the same account.
 perform 1 from public.ypt_wallet_accounts where user_id=u for update;
 if public.ypt_store_owns(u,p_product) then return public.ypt_store_snapshot()||jsonb_build_object('purchase_status','already_owned');end if;
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
 if not public.ypt_store_owns(u,'study_report_pdf') then
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
create or replace function public.ypt_store_save_preferences(p_settings jsonb) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure();k text;v jsonb;needed text;current_settings jsonb;
begin
 if jsonb_typeof(p_settings)<>'object' or octet_length(p_settings::text)>4096 then raise exception 'Invalid settings';end if;
 for k,v in select * from jsonb_each(p_settings) loop
 needed:=case when k in ('theme','timer_skin') then 'theme_pack' when k='frame' then 'profile_frame'
 when k='name_effect' then 'name_effect' when k='celebration' then 'focus_celebration'
 when k='dashboard' then 'custom_dashboard' else null end;
 if needed is null then raise exception 'Unknown setting';end if;
 if not public.ypt_store_owns(u,needed) then raise exception 'Unlock this pack first';end if;
 if jsonb_typeof(v)<>'string' then raise exception 'Choose a valid option';end if;
 if k='theme' and (v#>>'{}') not in ('gold','ocean','forest','amethyst','sunset','midnight','paper') then raise exception 'Invalid theme';end if;
 if k='timer_skin' and (v#>>'{}') not in ('classic','mono','serif','outline','capsule','segmented','minimal') then raise exception 'Invalid timer skin';end if;
 if k in ('frame','name_effect') and (v#>>'{}') not in ('none','gold','ocean','mint','rose','violet','ember','silver') then raise exception 'Invalid style';end if;
 if k='celebration' and (v#>>'{}') not in ('none','confetti','stars','ripple','beams','applause') then raise exception 'Invalid celebration';end if;
 if k='dashboard' and (v#>>'{}') not in ('default','focus','plan','social','progress') then raise exception 'Invalid dashboard';end if;
 end loop;
 insert into public.ypt_store_preferences(user_id,settings) values(u,p_settings)
 on conflict(user_id) do update set settings=ypt_store_preferences.settings||excluded.settings,updated_at=clock_timestamp()
 returning settings into current_settings;
 insert into public.ypt_store_styles(user_id,frame,name_effect)
 values(u,coalesce(current_settings->>'frame','none'),coalesce(current_settings->>'name_effect','none'))
 on conflict(user_id) do update set frame=excluded.frame,name_effect=excluded.name_effect;
 return public.ypt_store_snapshot();
end $$;
create or replace function public.ypt_store_my_groups() returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=auth.uid();begin
 if u is null then raise exception 'Login required' using errcode='28000';end if;
 return coalesce((select jsonb_agg(jsonb_build_object('id',g.id,'name',g.name,'theme',coalesce(s.theme,'gold'),
 'icon',coalesce(s.icon,'📚'),'tagline',coalesce(s.tagline,'')) order by g.created_at desc)
 from public.ypt_study_groups g left join public.ypt_store_group_styles s on s.group_id=g.id where g.owner_id=u),'[]'::jsonb);
end $$;
create or replace function public.ypt_store_save_group(p_group uuid,p_theme text,p_icon text,p_tagline text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure();begin
 if not public.ypt_store_owns(u,'group_customization') then raise exception 'Unlock Group Customization first';end if;
 perform 1 from public.ypt_study_groups where id=p_group and owner_id=u for update;
 if not found then raise exception 'Only the group owner can customize this group';end if;
 if p_theme is null or p_theme not in ('gold','ocean','forest','amethyst','sunset','midnight','paper')
 or p_icon is null or char_length(p_icon) not between 1 and 8 or p_tagline is null or char_length(p_tagline)>100
 then raise exception 'Invalid group style';end if;
 insert into public.ypt_store_group_styles(group_id,theme,icon,tagline) values(p_group,p_theme,p_icon,p_tagline)
 on conflict(group_id) do update set theme=excluded.theme,icon=excluded.icon,tagline=excluded.tagline,updated_at=clock_timestamp();
 return public.ypt_store_my_groups();
end $$;
create or replace function public.ypt_store_gift_preview(p_code text,p_product text) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure();target uuid;p public.ypt_store_products%rowtype;n text;begin
 if not public.ypt_store_owns(u,'friend_gift') then raise exception 'Unlock Friend Gift Pass first';end if;
 select user_id into target from public.ypt_wallet_accounts where referral_code=upper(trim(p_code));
 if target is null then raise exception 'Friend code not found. Ask them for the code from their Wallet invite link.';end if;
 if target=u then raise exception 'You cannot gift yourself';end if;
 select * into p from public.ypt_store_products where code=p_product;
 if not found or not p.enabled or p.code='friend_gift' then raise exception 'Choose an available gift item';end if;
 select display_name into n from public.ypt_profiles where id=target;
 return jsonb_build_object('recipient_name',coalesce(n,'Learner'),'product_name',p.name,'price_paise',p.price_paise,
 'already_owned',public.ypt_store_owns(target,p.code),'recipient_code',upper(trim(p_code)));
end $$;
create or replace function public.ypt_store_send_gift(p_code text,p_product text,p_request uuid) returns jsonb
language plpgsql security definer set search_path=pg_catalog,public as $$
declare u uuid:=public.ypt_wallet_ensure();target uuid;p public.ypt_store_products%rowtype;previous public.ypt_store_gifts%rowtype;
 cost bigint;debit bigint;credit record;gift_uuid uuid;t timestamptz;begin
 if p_request is null then raise exception 'Gift request ID required';end if;
 if not public.ypt_store_owns(u,'friend_gift') then raise exception 'Unlock Friend Gift Pass first';end if;
 select user_id into target from public.ypt_wallet_accounts where referral_code=upper(trim(p_code));
 if target is null or target=u then raise exception 'Choose a valid friend code, not your own';end if;
 -- Deterministic lock order makes crossed gifts and recipient purchases safe.
 perform 1 from public.ypt_wallet_accounts where user_id in (u,target) order by user_id for update;
 select * into previous from public.ypt_store_gifts where sender_id=u and request_id=p_request;
 if found then
 if previous.recipient_id is distinct from target or previous.product_code is distinct from p_product then raise exception 'Request already used for a different gift';end if;
 return public.ypt_store_snapshot()||jsonb_build_object('gift_status','already_sent');end if;
 select * into p from public.ypt_store_products where code=p_product for share;
 if not found or not p.enabled or p.code='friend_gift' then raise exception 'Choose an available gift item';end if;
 if public.ypt_store_owns(target,p.code) then raise exception 'Your friend already owns this item. No credits charged';end if;
 t:=clock_timestamp();cost:=p.price_paise;
 if (select coalesce(sum(remaining_paise),0) from public.ypt_wallet_ledger where user_id=u and expires_at>t)<cost
 then raise exception 'Insufficient unexpired wallet credits';end if;
 insert into public.ypt_store_gifts(sender_id,recipient_id,product_code,price_paise,request_id,created_at)
 values(u,target,p.code,p.price_paise,p_request,t) returning id into gift_uuid;
 for credit in select id,remaining_paise from public.ypt_wallet_ledger where user_id=u and expires_at>t and remaining_paise>0
 order by expires_at,earned_at,id for update loop
 debit:=least(cost,credit.remaining_paise);update public.ypt_wallet_ledger set remaining_paise=remaining_paise-debit where id=credit.id;
 insert into public.ypt_store_gift_debits(gift_id,credit_id,amount_paise) values(gift_uuid,credit.id,debit);
 cost:=cost-debit;exit when cost=0;end loop;
 if cost<>0 then raise exception 'Gift could not be completed; no credits charged';end if;
 return public.ypt_store_snapshot()||jsonb_build_object('gift_status','sent','gift_id',gift_uuid);
end $$;

revoke all on function public.ypt_store_snapshot(),public.ypt_store_buy(text,uuid),public.ypt_store_report(text,date),public.ypt_store_save_preferences(jsonb),public.ypt_store_my_groups(),public.ypt_store_save_group(uuid,text,text,text),public.ypt_store_gift_preview(text,text),public.ypt_store_send_gift(text,text,uuid) from public,anon;
grant execute on function public.ypt_store_snapshot(),public.ypt_store_buy(text,uuid),public.ypt_store_report(text,date),public.ypt_store_save_preferences(jsonb),public.ypt_store_my_groups(),public.ypt_store_save_group(uuid,text,text,text),public.ypt_store_gift_preview(text,text),public.ypt_store_send_gift(text,text,uuid) to authenticated;
notify pgrst,'reload schema';
commit;
