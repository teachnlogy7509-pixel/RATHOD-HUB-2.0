-- 1) Community reactions: 😂 (hasna) aur 😢 (rona) allow karo (purane emoji bhi allowed rahenge)
do $$ declare c text; begin
  for c in select conname from pg_constraint where conrelid='public.ypt_community_reactions'::regclass and contype='c' and pg_get_constraintdef(oid) ilike '%reaction_type%' loop
    execute format('alter table public.ypt_community_reactions drop constraint %I', c);
  end loop;
end $$;
alter table public.ypt_community_reactions add constraint ypt_community_reactions_reaction_type_check
  check (reaction_type in ('👍','❤️','🔥','🎉','💡','👏','😂','😢'));

-- 2) Welcome coupon (login par sabko dikhe, redeem ke baad hat jaye)
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

-- 3) Coupon "RATHOD HUB 2.0 GIFT" ko sabko dikhao (spelling/space/dash ka farak nahi padta)
update public.ypt_access_coupons set show_to_all=true
 where regexp_replace(upper(code),'[^A-Z0-9]','','g')='RATHODHUB20GIFT'
returning code, plan, duration_days, max_uses, used_count, active, expires_at, show_to_all;
