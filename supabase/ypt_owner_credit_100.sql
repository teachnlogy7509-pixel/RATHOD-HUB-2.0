-- Run ONLY in RATHOD HUB's oeacgchzyilgqzaqxssh Supabase SQL Editor.
-- Existing exact app owner account ONLY. This does not create admin privileges.
-- Adds ₹100 reward credits once, not ₹100 on every rerun. Requires reward-store SQL first.
begin;
do $$
declare owner_id uuid:='07518017-1cfe-4b8e-b50f-807368123d4c';t timestamptz;expiry timestamptz;
begin
 if not exists(select 1 from auth.users where id=owner_id) then
  raise exception 'Exact Rathod Hub owner account not found. No credit added. Verify the project and owner ID.';end if;
 if not exists(select 1 from public.ypt_admins where user_id=owner_id) then
  raise exception 'Owner is not a server-verified admin. No credit added. Verify existing admin membership first.';end if;
 insert into public.ypt_wallet_accounts(user_id) values(owner_id) on conflict do nothing;
 perform 1 from public.ypt_wallet_accounts where user_id=owner_id for update;
 t:=clock_timestamp();expiry:=((t at time zone 'Asia/Kolkata')+interval '6 months') at time zone 'Asia/Kolkata';
 insert into public.ypt_wallet_ledger(user_id,kind,amount_paise,remaining_paise,source_key,earned_at,expires_at)
 values(owner_id,'admin_credit',10000,10000,'owner-credit-100-v1',t,expiry)
 on conflict(user_id,kind,source_key) do nothing;
end $$;
select p.display_name,l.user_id,l.amount_paise/100.0 as credited_rupees,l.earned_at,l.expires_at
from public.ypt_wallet_ledger l left join public.ypt_profiles p on p.id=l.user_id
where l.user_id='07518017-1cfe-4b8e-b50f-807368123d4c' and l.kind='admin_credit' and l.source_key='owner-credit-100-v1';
commit;
