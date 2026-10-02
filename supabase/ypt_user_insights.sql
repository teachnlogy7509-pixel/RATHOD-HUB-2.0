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
