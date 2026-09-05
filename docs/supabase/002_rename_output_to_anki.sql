-- Only if 001 was applied before the Output → Anki rename.
alter table public.sessions    rename column output       to anki;
alter table public.clock_state rename column daily_output to daily_anki;
