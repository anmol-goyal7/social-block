load helpers
setup()    { setup_env; }
teardown() { teardown_env; }

# 2026-09-12 is a Saturday.
cfg() { write_config; parse_config "$SOCIAL_BLOCK_CONFIG"; }
epoch() { date -d "$1" +%s; }

@test "same-day window: start inclusive, end exclusive, day filter" {
  cfg <<'CFG'
[schedule]
9:00-17:00 mon-fri
CFG
  schedule_active "$(epoch '2026-09-11 09:00')"          # Fri
  [ "$ACTIVE_LABEL" = "09:00-17:00 weekdays" ]
  schedule_active "$(epoch '2026-09-11 16:59')"
  ! schedule_active "$(epoch '2026-09-11 17:00')"
  ! schedule_active "$(epoch '2026-09-11 08:59')"
  ! schedule_active "$(epoch '2026-09-12 12:00')"        # Sat
}

@test "midnight window belongs to the day it starts on" {
  cfg <<'CFG'
[schedule]
22:00-06:00 mon-fri
CFG
  schedule_active "$(epoch '2026-09-11 22:00')"          # Fri night
  schedule_active "$(epoch '2026-09-12 02:00')"          # Sat 02:00: started Fri -> blocked
  ! schedule_active "$(epoch '2026-09-12 06:00')"
  ! schedule_active "$(epoch '2026-09-12 22:00')"        # Sat night: not a weekday
  ! schedule_active "$(epoch '2026-09-14 02:00')"        # Mon 02:00: would have started Sun
  schedule_active "$(epoch '2026-09-14 22:30')"          # Mon night
}

@test "overlapping windows and an empty schedule" {
  cfg <<'CFG'
[schedule]
22:00-06:00
20:00-23:00 sat
CFG
  schedule_active "$(epoch '2026-09-12 21:00')"
  [ "$ACTIVE_LABEL" = "20:00-23:00 sat" ]
  schedule_active "$(epoch '2026-09-12 22:30')"
  [ "$ACTIVE_LABEL" = "22:00-06:00 daily" ]
  cfg <<'CFG'
[schedule]
CFG
  ! schedule_active "$(epoch '2026-09-12 22:30')"
}

@test "next_boundary: into and out of a nightly window" {
  cfg <<'CFG'
[schedule]
22:00-06:00 daily
CFG
  [ "$(next_boundary "$(epoch '2026-09-12 12:00')")" = "$(epoch '2026-09-12 22:00')" ]
  [ "$(next_boundary "$(epoch '2026-09-12 23:00')")" = "$(epoch '2026-09-13 06:00')" ]
  [ "$(next_boundary "$(epoch '2026-09-13 06:00')")" = "$(epoch '2026-09-13 22:00')" ]
}

@test "next_boundary skips days the filter excludes" {
  cfg <<'CFG'
[schedule]
22:00-06:00 mon-fri
CFG
  [ "$(next_boundary "$(epoch '2026-09-12 06:00')")" = "$(epoch '2026-09-14 22:00')" ]   # Sat morning -> Mon night
}

@test "next_boundary sees through overlapping windows" {
  cfg <<'CFG'
[schedule]
22:00-06:00
20:00-23:00 sat
CFG
  # Sat 21:00: the 23:00 end of the short window flips nothing, the nightly one carries on
  [ "$(next_boundary "$(epoch '2026-09-12 21:00')")" = "$(epoch '2026-09-13 06:00')" ]
}

@test "next_boundary: none when the schedule is empty or total" {
  cfg <<'CFG'
[schedule]
CFG
  ! next_boundary "$(epoch '2026-09-12 12:00')"
  cfg <<'CFG'
[schedule]
0:00-12:00
12:00-0:00
CFG
  ! next_boundary "$(epoch '2026-09-12 12:00')"
}

@test "now_epoch honours SOCIAL_BLOCK_NOW" {
  at '2026-09-12 22:00'
  [ "$(now_epoch)" = "$(epoch '2026-09-12 22:00')" ]
}

@test "formatting helpers" {
  [ "$(fmt_epoch "$(epoch '2026-09-13 06:00')")" = "Sun 06:00" ]
  [ "$(fmt_delta 45)" = "0m" ]
  [ "$(fmt_delta 3600)" = "1h 0m" ]
  [ "$(fmt_delta 11520)" = "3h 12m" ]
  [ "$(fmt_delta 90000)" = "1d 1h 0m" ]
}

@test "next_boundary does not depend on the timezone" {
  # "+1 day" after a time is a UTC+1 offset to GNU date; this pins the fix.
  cfg <<'CFG'
[schedule]
22:00-06:00 daily
CFG
  for tz in UTC America/New_York Asia/Kolkata Pacific/Auckland; do
    export TZ=$tz
    [ "$(next_boundary "$(epoch '2026-09-12 23:00')")" = "$(epoch '2026-09-13 06:00')" ]
    [ "$(next_boundary "$(epoch '2026-09-12 12:00')")" = "$(epoch '2026-09-12 22:00')" ]
  done
  unset TZ
}

@test "next_boundary is right across a DST change" {
  # New York falls back on 2026-11-01 at 02:00; the 06:00 end still means 06:00 wall-clock.
  cfg <<'CFG'
[schedule]
22:00-06:00 daily
CFG
  export TZ=America/New_York
  [ "$(next_boundary "$(epoch '2026-10-31 23:00')")" = "$(epoch '2026-11-01 06:00')" ]
  [ "$(next_boundary "$(epoch '2026-11-01 06:00')")" = "$(epoch '2026-11-01 22:00')" ]
  unset TZ
}
