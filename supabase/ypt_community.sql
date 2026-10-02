-- YPT Study by Rathod: VIP-only realtime Community
-- Run once in the same Supabase project used by the app.

create or replace function public.ypt_has_active_vip()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.ypt_memberships
    where user_id = auth.uid()
      and active = true
      and plan = 'vip'
      and (expires_at is null or expires_at > now())
  ) or public.ypt_is_admin();
$$;
revoke all on function public.ypt_has_active_vip() from public, anon;
grant execute on function public.ypt_has_active_vip() to authenticated;

create table if not exists public.ypt_community_posts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  body text not null check (char_length(body) between 1 and 1200),
  created_at timestamptz not null default now()
);

create table if not exists public.ypt_community_comments (
  id uuid primary key default gen_random_uuid(),
  post_id uuid not null references public.ypt_community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  parent_comment_id uuid references public.ypt_community_comments(id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 60),
  body text not null check (char_length(body) between 1 and 600),
  created_at timestamptz not null default now()
);

create table if not exists public.ypt_community_reactions (
  post_id uuid not null references public.ypt_community_posts(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  reaction_type text not null check (reaction_type in ('👍','❤️','🔥','🎉','💡','👏')),
  created_at timestamptz not null default now(),
  primary key (post_id,user_id)
);

create index if not exists ypt_community_posts_created_idx on public.ypt_community_posts(created_at desc);
create index if not exists ypt_community_comments_post_idx on public.ypt_community_comments(post_id,created_at);
create index if not exists ypt_community_comments_parent_idx on public.ypt_community_comments(parent_comment_id);

alter table public.ypt_community_posts enable row level security;
alter table public.ypt_community_comments enable row level security;
alter table public.ypt_community_reactions enable row level security;

grant select,insert,update,delete on public.ypt_community_posts to authenticated;
grant select,insert,update,delete on public.ypt_community_comments to authenticated;
grant select,insert,update,delete on public.ypt_community_reactions to authenticated;

drop policy if exists "vip reads community posts" on public.ypt_community_posts;
create policy "vip reads community posts" on public.ypt_community_posts for select to authenticated using (public.ypt_has_active_vip());
drop policy if exists "vip creates own community posts" on public.ypt_community_posts;
create policy "vip creates own community posts" on public.ypt_community_posts for insert to authenticated with check (public.ypt_has_active_vip() and user_id=auth.uid());
drop policy if exists "owners manage community posts" on public.ypt_community_posts;
create policy "owners manage community posts" on public.ypt_community_posts for update to authenticated using (user_id=auth.uid() or public.ypt_is_admin()) with check (user_id=auth.uid() or public.ypt_is_admin());
drop policy if exists "owners delete community posts" on public.ypt_community_posts;
create policy "owners delete community posts" on public.ypt_community_posts for delete to authenticated using (user_id=auth.uid() or public.ypt_is_admin());

drop policy if exists "vip reads community comments" on public.ypt_community_comments;
create policy "vip reads community comments" on public.ypt_community_comments for select to authenticated using (public.ypt_has_active_vip());
drop policy if exists "vip creates own community comments" on public.ypt_community_comments;
create policy "vip creates own community comments" on public.ypt_community_comments for insert to authenticated with check (public.ypt_has_active_vip() and user_id=auth.uid());
drop policy if exists "owners manage community comments" on public.ypt_community_comments;
create policy "owners manage community comments" on public.ypt_community_comments for update to authenticated using (user_id=auth.uid() or public.ypt_is_admin()) with check (user_id=auth.uid() or public.ypt_is_admin());
drop policy if exists "owners delete community comments" on public.ypt_community_comments;
create policy "owners delete community comments" on public.ypt_community_comments for delete to authenticated using (user_id=auth.uid() or public.ypt_is_admin());

drop policy if exists "vip reads community reactions" on public.ypt_community_reactions;
create policy "vip reads community reactions" on public.ypt_community_reactions for select to authenticated using (public.ypt_has_active_vip());
drop policy if exists "vip manages own reactions" on public.ypt_community_reactions;
create policy "vip manages own reactions" on public.ypt_community_reactions for all to authenticated using (public.ypt_has_active_vip() and user_id=auth.uid()) with check (public.ypt_has_active_vip() and user_id=auth.uid());

-- Keep replies inside the same post as their parent comment.
create or replace function public.ypt_validate_comment_parent()
returns trigger language plpgsql set search_path=public as $$
begin
  if new.parent_comment_id is not null and not exists (
    select 1 from public.ypt_community_comments c where c.id=new.parent_comment_id and c.post_id=new.post_id
  ) then raise exception 'Reply parent must belong to the same post'; end if;
  return new;
end $$;
drop trigger if exists ypt_comment_parent_guard on public.ypt_community_comments;
create trigger ypt_comment_parent_guard before insert or update on public.ypt_community_comments for each row execute function public.ypt_validate_comment_parent();

-- Enable Supabase Realtime safely if tables are not already published.
do $$ begin
  alter publication supabase_realtime add table public.ypt_community_posts;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.ypt_community_comments;
exception when duplicate_object then null; end $$;
do $$ begin
  alter publication supabase_realtime add table public.ypt_community_reactions;
exception when duplicate_object then null; end $$;
