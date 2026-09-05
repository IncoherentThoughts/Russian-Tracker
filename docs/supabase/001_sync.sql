-- Russian Tracker sync schema (ADR 0003). Paste into the Supabase SQL editor once.

create table public.clock_state (
  user_id            uuid primary key references auth.users (id) on delete cascade,
  is_running         boolean          not null default false,
  run_started_at     timestamptz,
  mode               text             not null default 'grammar',
  study_day          timestamptz      not null default '1970-01-01',
  daily_base         double precision not null default 0,
  daily_grammar      double precision not null default 0,
  daily_immersion    double precision not null default 0,
  daily_output       double precision not null default 0,
  daily_goal         double precision not null default 14400,
  last_action_at     timestamptz      not null default '1970-01-01',
  last_action_device text             not null default '',
  updated_at         timestamptz      not null default now()
);

create table public.sessions (
  user_id        uuid             not null references auth.users (id) on delete cascade,
  date           date             not null,
  duration       double precision not null default 0,
  grammar        double precision not null default 0,
  immersion      double precision not null default 0,
  output         double precision not null default 0,
  is_manual_edit boolean          not null default false,
  updated_at     timestamptz      not null default now(),
  primary key (user_id, date)
);

alter table public.clock_state enable row level security;
alter table public.sessions    enable row level security;

create policy "own clock" on public.clock_state
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own sessions" on public.sessions
  for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- Realtime: full old rows so a delete carries the Study Day.
alter table public.clock_state replica identity full;
alter table public.sessions    replica identity full;
alter publication supabase_realtime add table public.clock_state, public.sessions;
