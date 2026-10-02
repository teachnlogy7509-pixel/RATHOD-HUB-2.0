-- Run after ypt_full_schema.sql. Allows every authenticated real learner's timer
-- to appear in the dashboard live list; full Live Room UI can remain VIP-gated.
drop policy if exists "vip view ypt live" on public.ypt_live_sessions;
drop policy if exists "authenticated view ypt live" on public.ypt_live_sessions;
create policy "authenticated view ypt live"
on public.ypt_live_sessions for select to authenticated using (true);

drop policy if exists "vip own live insert" on public.ypt_live_sessions;
drop policy if exists "ypt own live insert" on public.ypt_live_sessions;
create policy "authenticated own live insert"
on public.ypt_live_sessions for insert to authenticated
with check (auth.uid()=user_id);

drop policy if exists "vip own live update" on public.ypt_live_sessions;
drop policy if exists "ypt own live update" on public.ypt_live_sessions;
create policy "authenticated own live update"
on public.ypt_live_sessions for update to authenticated
using (auth.uid()=user_id) with check (auth.uid()=user_id);
