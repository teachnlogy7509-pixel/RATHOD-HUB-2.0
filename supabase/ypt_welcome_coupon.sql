-- YPT Study by Rathod: Welcome coupon (login par sabko dikhe, redeem ke baad hat jaye)
alter table public.ypt_access_coupons add column if not exists show_to_all boolean not null default false;

create or replace function public.get_ypt_public_coupon()
returns table(code text, plan text, duration_days integer)
language sql stable security definer set search_path=public as $$
  select c.code,c.plan,c.duration_days
  from public.ypt_access_coupons c
  where auth.uid() is not null and c.show_to_all and c.active
    and (c.expires_at is null or c.expires_at>now())
    and (c.max_uses is null or c.used_count<c.max_uses)
    and not exists(select 1 from public.ypt_coupon_redemptions r where r.coupon_id=c.id and r.user_id=auth.uid())
  order by c.created_at desc limit 1
$$;
revoke all on function public.get_ypt_public_coupon() from public,anon;
grant execute on function public.get_ypt_public_coupon() to authenticated;

-- 👇 Jis coupon ko sabko dikhana hai uska code yaha likho (quotes ke andar), phir Run karo
update public.ypt_access_coupons set show_to_all=true where upper(code)=upper('YAHAN_APNA_COUPON_CODE_LIKHO');
