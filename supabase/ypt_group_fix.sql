-- YPT Study by Rathod: study group join fix (safe to run more than once)

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

-- 5) Group ke members + is hafte ki study (sirf member dekh sakta hai)
create or replace function public.get_ypt_group_members(p_group uuid)
returns table(user_id uuid,display_name text,avatar_url text,role text,week_seconds bigint)
language sql stable security definer set search_path=public as $$
  select m.user_id,coalesce(p.display_name,'Learner'),p.avatar_url,m.role,
    coalesce((select sum(s.duration_seconds) from public.ypt_focus_sessions s
      where s.user_id=m.user_id and s.session_date>=date_trunc('week',current_date)::date),0)::bigint
  from public.ypt_group_members m left join public.ypt_profiles p on p.id=m.user_id
  where m.group_id=p_group and exists(select 1 from public.ypt_group_members x where x.group_id=p_group and x.user_id=auth.uid())
  order by 5 desc
$$;
revoke all on function public.get_ypt_group_members(uuid) from public,anon;
grant execute on function public.get_ypt_group_members(uuid) to authenticated;
