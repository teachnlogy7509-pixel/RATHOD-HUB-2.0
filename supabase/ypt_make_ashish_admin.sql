-- Makes the exact login name ASHISH RATHOR an app admin.
insert into public.ypt_admins(user_id)
select user_id from public.ypt_login_names
where lower(trim(username))='ashish rathor'
on conflict(user_id) do nothing;

select p.display_name,a.user_id from public.ypt_admins a
left join public.ypt_profiles p on p.id=a.user_id;
