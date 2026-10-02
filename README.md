# RATHOD Focus 2.0

A responsive, local-first YPT-style study app with real Supabase data and secure Premium/VIP access.

## Included

- Stopwatch and Pomodoro focus timer
- Subjects, daily goals, recent sessions and streaks
- Real Supabase Auth and per-user sync
- Real-time VIP study-room presence (no demo users)
- Daily/weekly/monthly analytics and study calendar
- Daily tasks and subject breakdown
- Real Premium study groups
- Real VIP weekly leaderboard
- Secure Premium/VIP memberships, expiry and coupon redemption RPC
- Mobile and desktop layouts
- Local mode for timer/tasks before login
- Previous community app preserved at `community.html`

## Supabase setup required

The frontend is configured for `https://oeacgchzyilgqzaqxssh.supabase.co` with its publishable browser key.

1. Open that project's Supabase SQL Editor.
2. Run the complete `supabase/ypt_full_schema.sql` file once.
3. In Authentication settings, configure your Site URL and redirect URLs.
4. Open the app and create/login to an account.

Never put a service-role key in frontend code or GitHub.

## Plans

- **Free:** timer, daily goals/tasks, calendar and local progress.
- **Premium:** advanced analytics and real study groups.
- **VIP:** Premium features plus realtime live room and weekly leaderboard.

Create coupon codes privately in Supabase SQL Editor, never in GitHub:

```sql
insert into public.ypt_access_coupons(code, plan, duration_days, max_uses)
values ('YOUR-PRIVATE-CODE', 'premium', 30, 1);
```

Use `vip` instead of `premium` for VIP access. Users redeem codes from the Premium & VIP screen; code validation runs server-side through `redeem_ypt_access`.

## Main files

- `index.html` — RATHOD Focus app
- `ypt.css` — responsive UI
- `ypt.js` — timer, real data sync and plan gates
- `supabase/ypt_full_schema.sql` — tables, RLS, realtime, memberships and RPCs
- `community.html` — previous community page preserved unchanged
