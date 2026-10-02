-- Replace YOUR_LOGIN_NAME with the exact Name/Username used to create your account.
insert into public.ypt_admins(user_id)
select user_id from public.ypt_login_names
where lower(username)=lower('YOUR_LOGIN_NAME')
on conflict(user_id) do nothing;

select p.display_name,a.user_id from public.ypt_admins a
left join public.ypt_profiles p on p.id=a.user_id;
