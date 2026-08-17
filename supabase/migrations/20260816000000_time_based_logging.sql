-- Time-based logging, replacing fixed meal slots.
--
-- Why: Desayuno/Almuerzo/Merienda/Cena is a US/European convention that fits
-- Argentine eating hours poorly — dinner at 22:00 and merienda at 18:00 do not
-- slot cleanly. Logging against the clock is both simpler and a better fit for
-- the market, and it removes a taxonomy the user has to agree with before they
-- can record a snack.
--
-- Also adds weekly_rate_kg, which onboarding needs to turn a goal into a
-- calorie delta and which the original schema had nowhere to put.

-- ---------------------------------------------------------------------------
-- 1. Rate of change toward the goal
-- ---------------------------------------------------------------------------

-- kg per week. 0 for "mantener"; typically 0.25–1.0 when losing or gaining.
-- Capped at 2 because anything beyond that is not a target worth encouraging.
alter table public.profiles
  add column weekly_rate_kg numeric(3,2)
    check (weekly_rate_kg is null or weekly_rate_kg between 0 and 2);

comment on column public.profiles.weekly_rate_kg is
  'Target rate of weight change in kg/week. Combined with goal to derive the '
  'daily calorie delta applied on top of TDEE.';

-- ---------------------------------------------------------------------------
-- 2. diary_entries: a date + meal slot becomes an instant
-- ---------------------------------------------------------------------------

-- timestamptz, not timestamp: it stores an absolute instant and lets the client
-- render in the user's zone. Argentina is UTC-3 with no DST today, but that is
-- a policy that has changed before and storing naive local time would make any
-- future change unrecoverable.
alter table public.diary_entries
  add column logged_at timestamptz;

-- Carry over anything already logged. Midday rather than midnight so an entry
-- does not shift to the previous day when rendered west of UTC.
update public.diary_entries
   set logged_at = (logged_on::timestamp + interval '12 hours') at time zone 'America/Argentina/Buenos_Aires'
 where logged_at is null;

alter table public.diary_entries
  alter column logged_at set not null;

drop index if exists public.diary_entries_user_date_idx;

alter table public.diary_entries
  drop column meal_slot,
  drop column logged_on;

-- The diary screen queries "one user, one day, in order". Descending matches
-- the default render order.
create index diary_entries_user_time_idx
  on public.diary_entries (user_id, logged_at desc);

comment on column public.diary_entries.logged_at is
  'When the food was eaten, as an absolute instant. The diary groups these by '
  'hour in the user''s local timezone; there are no fixed meal slots.';

-- No longer referenced anywhere.
drop type if exists public.meal_slot;
