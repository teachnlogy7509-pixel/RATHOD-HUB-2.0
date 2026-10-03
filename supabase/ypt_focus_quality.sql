-- YPT by Rathod: optional Focus Quality metadata
-- Run once in the same Supabase project after the main YPT schema.

alter table public.ypt_focus_sessions
  add column if not exists focus_score integer,
  add column if not exists interruptions integer not null default 0,
  add column if not exists pause_count integer not null default 0;

alter table public.ypt_focus_sessions
  drop constraint if exists ypt_focus_sessions_focus_score_check;
alter table public.ypt_focus_sessions
  add constraint ypt_focus_sessions_focus_score_check
  check (focus_score is null or focus_score between 0 and 100);

alter table public.ypt_focus_sessions
  drop constraint if exists ypt_focus_sessions_interruptions_check;
alter table public.ypt_focus_sessions
  add constraint ypt_focus_sessions_interruptions_check
  check (interruptions >= 0 and pause_count >= 0);

create index if not exists ypt_focus_sessions_quality_idx
  on public.ypt_focus_sessions(user_id, session_date desc, focus_score)
  where focus_score is not null;
