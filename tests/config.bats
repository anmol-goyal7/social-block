load helpers
setup()    { setup_env; }
teardown() { teardown_env; }

@test "parse_time accepts H:MM and HH:MM, rejects out-of-range" {
  [ "$(parse_time 22:00)" -eq 1320 ]
  [ "$(parse_time 6:05)" -eq 365 ]
  [ "$(parse_time 0:00)" -eq 0 ]
  ! parse_time 24:00
  ! parse_time 22:60
  ! parse_time 22:0
  ! parse_time 2200
}

@test "parse_days: names, ranges, wrapping ranges, lists, aliases, case" {
  [ "$(parse_days daily)" -eq 127 ]
  [ "$(parse_days weekdays)" -eq 31 ]
  [ "$(parse_days weekends)" -eq 96 ]
  [ "$(parse_days mon-fri)" -eq 31 ]
  [ "$(parse_days sat,sun)" -eq 96 ]
  [ "$(parse_days 'Mon, Wed ,fri')" -eq 21 ]
  [ "$(parse_days fri-mon)" -eq 113 ]      # fri sat sun mon = 16+32+64+1
  [ "$(parse_days mon-mon)" -eq 1 ]
  ! parse_days ''
  ! parse_days monday
  ! parse_days mon-
  ! parse_days 'mon,,fri'
}

@test "fmt_days canonicalises masks" {
  [ "$(fmt_days 127)" = daily ]
  [ "$(fmt_days 31)" = weekdays ]
  [ "$(fmt_days 96)" = weekends ]
  [ "$(fmt_days 21)" = "mon,wed,fri" ]
}

@test "a full config parses into windows, sites and lock" {
  write_config <<'CFG'
# a comment
[schedule]
22:00-06:00 daily      # trailing comment
9:00-17:00 mon-fri

[options]
lock = TRUE

[sites]
Reddit.com
x.com
CFG
  parse_config "$SOCIAL_BLOCK_CONFIG"
  [ "${#WINDOWS[@]}" -eq 2 ]
  [ "${WINDOWS[0]}" = "1320|360|127|22:00-06:00 daily" ]
  [ "${WINDOWS[1]}" = "540|1020|31|09:00-17:00 weekdays" ]
  [ "$LOCK" = true ]
  [ "${SITES[*]}" = "reddit.com x.com" ]
}

@test "missing days means daily" {
  write_config <<'CFG'
[schedule]
22:00-06:00
CFG
  parse_config "$SOCIAL_BLOCK_CONFIG"
  [ "${WINDOWS[0]}" = "1320|360|127|22:00-06:00 daily" ]
}

@test "every error is reported with its line number" {
  write_config <<'CFG'
nonsense before a section
[schedule]
25:00-06:00
22:00-22:00
22:00-06:00 someday
[options]
lock = maybe
colour = red
[sites]
not a host
-bad.com
[bogus]
whatever
CFG
  run parse_config "$SOCIAL_BLOCK_CONFIG"
  [ "$status" -eq 1 ]
  parse_config "$SOCIAL_BLOCK_CONFIG" || true
  [ "${#CONFIG_ERRORS[@]}" -eq 9 ]
  [[ "${CONFIG_ERRORS[0]}" == 'config:1: "nonsense before a section" is outside any section'* ]]
  [[ "${CONFIG_ERRORS[1]}" == 'config:3: bad time "25:00"' ]]
  [[ "${CONFIG_ERRORS[2]}" == 'config:4: window "22:00-22:00" starts and ends at the same time' ]]
  [[ "${CONFIG_ERRORS[3]}" == 'config:5: bad days "someday"'* ]]
  [[ "${CONFIG_ERRORS[4]}" == 'config:7: lock must be true or false, got "maybe"' ]]
  [[ "${CONFIG_ERRORS[5]}" == 'config:8: unknown option "colour"'* ]]
  [[ "${CONFIG_ERRORS[6]}" == 'config:10: not a hostname: "not a host"' ]]
  [[ "${CONFIG_ERRORS[7]}" == 'config:11: not a hostname: "-bad.com"' ]]
  [[ "${CONFIG_ERRORS[8]}" == 'config:12: unknown section [bogus]' ]]
}

@test "an unreadable config is one error" {
  run parse_config "$TMP/nope"
  [ "$status" -eq 1 ]
}

@test "an empty config is valid and empty" {
  : > "$SOCIAL_BLOCK_CONFIG"
  parse_config "$SOCIAL_BLOCK_CONFIG"
  [ "${#WINDOWS[@]}" -eq 0 ]
  [ "${#SITES[@]}" -eq 0 ]
  [ "$LOCK" = false ]
}
