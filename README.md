# RATHOD Focus 2.0

A responsive, local-first YPT-style study system for RATHOD HUB.

## Included

- Stopwatch and Pomodoro focus timer
- Subjects, daily goals, recent sessions and streaks
- Realtime study-room presence after Supabase connection
- Daily/weekly/monthly analytics and study calendar
- Daily tasks and subject breakdown
- Study groups and weekly leaderboard foundation
- Supabase Auth, Realtime and RLS-ready SQL
- Mobile and desktop layouts
- Local mode: timer, tasks, goals and analytics work before database setup
- Existing GyaanSetu community preserved at `community.html`

## Connect Supabase later

1. Run `supabase/ypt_full_schema.sql` in the Supabase SQL editor.
2. Open the app → **Settings**.
3. Paste the project URL and **publishable/anon key**.
4. Never paste a service-role key in browser code.
5. Create an account from the profile button and verify email if confirmation is enabled.

## Files

- `index.html` — RATHOD Focus app
- `ypt.css` — responsive UI
- `ypt.js` — local-first timer and Supabase sync
- `supabase/ypt_full_schema.sql` — YPT tables, RLS, realtime and leaderboard view
- `community.html` — previous GyaanSetu/YPT page preserved unchanged

The app deliberately uses an original RATHOD Focus design rather than copying YPT branding or assets.
