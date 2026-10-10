-- YPT Study by Rathod: Live chat sirf VIP ke liye + 3 din baad messages hamesha ke liye delete
-- (safe to run more than once)

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
