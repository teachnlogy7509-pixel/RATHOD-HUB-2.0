# YPT Study by Rathod

A black, gold and red premium YPT-style study app with real Supabase data and secure Premium/VIP access.

## Included

- Stopwatch and Pomodoro focus timer
- Subjects, daily goals, recent sessions and streaks
- Real Supabase Auth and per-user sync
- Real-time VIP study-room presence (no demo users)
- Daily/weekly/monthly analytics and study calendar
- Daily tasks and subject breakdown
- Date-wise Daily History with completed/pending tasks and subject sessions
- Real authenticated learners shown in live presence
- Student Insights: all authenticated learners can view real date-wise subject durations and session timelines (private task text stays hidden)
- YPT-style clickable live-seat cards: tap a learner to open their insights
- Per-user monthly study calendar; tap any date for subject and session details
- Mobile dock and tablet-responsive insight layouts
- Mobile-first home with today total, D-day, subject play buttons, subject time and todo progress
- Phone-native timer, live seats, planner, calendar and insights layouts
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
3. In Authentication → Providers → Email, turn **Confirm email OFF** because the app uses private name-based login IDs.
4. Configure your Site URL and redirect URLs.
5. Open the app and create/login using name and password.

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

## Realtime and administration

- Realtime live-room chat with Supabase Realtime
- Admin-only notification and app-update publishing panel
- Notification bell and update/APK links
- Username login with recovery email and forgot-password flow
- FAQ, Terms, Privacy, Community Guidelines and Telegram contact links
- Installable PWA with original watermark-free YPT by Rathod logo
- Android WebView project and GitHub Actions APK build/release workflow

Run `supabase/ypt_app_features.sql`, then edit and run `supabase/ypt_make_admin.sql` with the exact admin login name.

## Offline Android mode and Focus Shield

The Android APK bundles the complete HTML/CSS/JS app and Supabase library inside the APK, so the timer, subjects, tasks, calendar, history and local analytics start without internet. Running timers persist timestamps in local storage and recover after backgrounding/restart; unsynced completed sessions queue locally and sync after login when internet returns.

The optional Accessibility Focus Shield turns on with an active timer and allows only YPT Study by Rathod and the official PW package `xyz.penpencil.physicswala`, plus essential Android system UI/settings/keyboard. The user must explicitly enable the service in Android Accessibility settings. Finish the timer to switch the shield off.

## Account edits and recovery

Logged-in users can open the profile button, enter their exact recovery email, and immediately change their username and/or password without OTP. Logged-out recovery accepts the exact username + recovery email + a new password; it is rate-limited to five failed attempts per hour. Run `supabase/ypt_app_features.sql` after this update.

Live seats use a three-column mobile grid with real names. Each seat provides separate Message and Insights actions; private messages are protected by sender/receiver RLS.
