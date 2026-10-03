-- YPT by Rathod: PRO & VIP Zone + one-coupon six-month access
-- Run once in the same Supabase project used by RATHOD-HUB-2.0.

-- One active coupon unlocks every PRO/VIP feature for about six months.
update public.ypt_access_coupons
set plan='vip', duration_days=183
where active=true;

create or replace function public.ypt_vip_zone_access()
returns boolean language sql stable security definer set search_path=public as $$
  select exists(select 1 from public.ypt_memberships m
    where m.user_id=auth.uid() and m.active=true and m.plan='vip'
      and (m.expires_at is null or m.expires_at>now()))
  or public.ypt_is_admin();
$$;
revoke all on function public.ypt_vip_zone_access() from public,anon;
grant execute on function public.ypt_vip_zone_access() to authenticated;

create table if not exists public.ypt_pw_classes(
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 class_date date not null, subject text not null, lecture_name text not null,
 duration_seconds integer not null default 0, progress_percent integer not null default 0 check(progress_percent between 0 and 100),
 questions_attempted integer not null default 0, wrong_answers integer not null default 0,
 completed boolean not null default false, started_at timestamptz, ended_at timestamptz, created_at timestamptz not null default now()
);
create table if not exists public.ypt_diary_entries(
 user_id uuid not null references auth.users(id) on delete cascade, entry_date date not null,
 mood text, entry_text text not null default '', tomorrow_plan text not null default '',
 class_done boolean not null default false, revision_done boolean not null default false, target_done boolean not null default false,
 updated_at timestamptz not null default now(), primary key(user_id,entry_date)
);
create table if not exists public.ypt_private_notes(
 id uuid primary key, user_id uuid not null references auth.users(id) on delete cascade,
 subject text not null, title text not null, body text not null, created_at timestamptz not null default now()
);
create table if not exists public.ypt_focus_partners(
 id uuid primary key default gen_random_uuid(), requester_id uuid not null references auth.users(id) on delete cascade,
 receiver_id uuid not null references auth.users(id) on delete cascade,
 status text not null default 'pending' check(status in('pending','accepted','rejected','cancelled')),
 created_at timestamptz not null default now(), responded_at timestamptz,
 check(requester_id<>receiver_id)
);
create index if not exists ypt_pw_classes_user_date_idx on public.ypt_pw_classes(user_id,class_date desc);
create index if not exists ypt_private_notes_user_idx on public.ypt_private_notes(user_id,created_at desc);
create index if not exists ypt_focus_partners_users_idx on public.ypt_focus_partners(requester_id,receiver_id,status);

alter table public.ypt_pw_classes enable row level security;
alter table public.ypt_diary_entries enable row level security;
alter table public.ypt_private_notes enable row level security;
alter table public.ypt_focus_partners enable row level security;
grant select,insert,update,delete on public.ypt_pw_classes,public.ypt_diary_entries,public.ypt_private_notes,public.ypt_focus_partners to authenticated;

drop policy if exists "vip owns pw classes" on public.ypt_pw_classes;
create policy "vip owns pw classes" on public.ypt_pw_classes for all to authenticated using(user_id=auth.uid() and public.ypt_vip_zone_access()) with check(user_id=auth.uid() and public.ypt_vip_zone_access());
drop policy if exists "vip owns diary" on public.ypt_diary_entries;
create policy "vip owns diary" on public.ypt_diary_entries for all to authenticated using(user_id=auth.uid() and public.ypt_vip_zone_access()) with check(user_id=auth.uid() and public.ypt_vip_zone_access());
drop policy if exists "vip owns notes" on public.ypt_private_notes;
create policy "vip owns notes" on public.ypt_private_notes for all to authenticated using(user_id=auth.uid() and public.ypt_vip_zone_access()) with check(user_id=auth.uid() and public.ypt_vip_zone_access());
drop policy if exists "partner participants read" on public.ypt_focus_partners;
create policy "partner participants read" on public.ypt_focus_partners for select to authenticated using((requester_id=auth.uid() or receiver_id=auth.uid()) and public.ypt_vip_zone_access());

create or replace function public.request_ypt_partner(p_username text)
returns jsonb language plpgsql security definer set search_path=public as $$
declare target uuid;
begin
 if not public.ypt_vip_zone_access() then return jsonb_build_object('success',false,'error','VIP access required'); end if;
 select user_id into target from public.ypt_login_names where lower(trim(username))=lower(trim(p_username)) limit 1;
 if target is null then return jsonb_build_object('success',false,'error','Username not found'); end if;
 if target=auth.uid() then return jsonb_build_object('success',false,'error','Choose another user'); end if;
 if exists(select 1 from public.ypt_focus_partners where status in('pending','accepted') and ((requester_id=auth.uid() and receiver_id=target) or (requester_id=target and receiver_id=auth.uid()))) then return jsonb_build_object('success',false,'error','Request or partnership already exists'); end if;
 insert into public.ypt_focus_partners(requester_id,receiver_id) values(auth.uid(),target);
 return jsonb_build_object('success',true);
end $$;

create or replace function public.respond_ypt_partner(p_request_id uuid,p_accept boolean)
returns jsonb language plpgsql security definer set search_path=public as $$
declare req public.ypt_focus_partners%rowtype;
begin
 select * into req from public.ypt_focus_partners where id=p_request_id and receiver_id=auth.uid() and status='pending' for update;
 if req.id is null then return jsonb_build_object('success',false,'error','Request not found'); end if;
 if p_accept then
  update public.ypt_focus_partners set status='cancelled',responded_at=now() where id<>req.id and status in('pending','accepted') and (requester_id in(req.requester_id,req.receiver_id) or receiver_id in(req.requester_id,req.receiver_id));
  update public.ypt_focus_partners set status='accepted',responded_at=now() where id=req.id;
 else update public.ypt_focus_partners set status='rejected',responded_at=now() where id=req.id; end if;
 return jsonb_build_object('success',true);
end $$;

create or replace function public.get_ypt_partner_state()
returns jsonb language plpgsql security definer set search_path=public as $$
declare rel public.ypt_focus_partners%rowtype; partner_id uuid; partner_name text; requests jsonb; my_sec bigint; partner_sec bigint;
begin
 select * into rel from public.ypt_focus_partners where status='accepted' and (requester_id=auth.uid() or receiver_id=auth.uid()) order by responded_at desc limit 1;
 if rel.id is not null then partner_id:=case when rel.requester_id=auth.uid() then rel.receiver_id else rel.requester_id end; select display_name into partner_name from public.ypt_profiles where id=partner_id; end if;
 select coalesce(jsonb_agg(jsonb_build_object('id',f.id,'display_name',coalesce(p.display_name,'Learner'))),'[]'::jsonb) into requests from public.ypt_focus_partners f left join public.ypt_profiles p on p.id=f.requester_id where f.receiver_id=auth.uid() and f.status='pending';
 select coalesce(sum(duration_seconds),0) into my_sec from public.ypt_focus_sessions where user_id=auth.uid() and session_date=current_date;
 if partner_id is not null then select coalesce(sum(duration_seconds),0) into partner_sec from public.ypt_focus_sessions where user_id=partner_id and session_date=current_date; else partner_sec:=0; end if;
 return jsonb_build_object('partner',case when partner_id is null then null else jsonb_build_object('id',partner_id,'display_name',coalesce(partner_name,'Learner')) end,'requests',requests,'my_today',my_sec,'partner_today',partner_sec);
end $$;
revoke all on function public.request_ypt_partner(text),public.respond_ypt_partner(uuid,boolean),public.get_ypt_partner_state() from public,anon;
grant execute on function public.request_ypt_partner(text),public.respond_ypt_partner(uuid,boolean),public.get_ypt_partner_state() to authenticated;
