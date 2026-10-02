-- Works for old and new accounts. Name matching is case-insensitive.
insert into public.ypt_admins(user_id)
select user_id from public.ypt_login_names where lower(trim(username))='ashish rathor'
union
select id from public.ypt_profiles where lower(trim(display_name))='ashish rathor'
union
select id from auth.users where lower(trim(coalesce(raw_user_meta_data->>'full_name','')))='ashish rathor'
on conflict(user_id) do nothing;

select p.display_name,a.user_id from public.ypt_admins a
left join public.ypt_profiles p on p.id=a.user_id;
