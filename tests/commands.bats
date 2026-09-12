load helpers
setup()    { setup_env; }
teardown() { teardown_env; }

nightly() { write_config <<'CFG'
[schedule]
22:00-06:00 daily
[sites]
reddit.com
CFG
}
locked_nightly() { write_config <<'CFG'
[schedule]
22:00-06:00 daily
[options]
lock = true
[sites]
reddit.com
CFG
}

@test "version prints the version" {
  run main version
  [ "$status" -eq 0 ]
  [[ "$output" == "social-block 0.1.0" ]]
}

@test "unknown command is a usage error" {
  run main frobnicate
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage:"* ]]
}

# ---- apply / reconcile ----

@test "apply blocks inside the window and unblocks outside it" {
  nightly
  at '2026-09-12 23:00'; run main apply
  [ "$status" -eq 0 ]
  [[ "$output" == "social-block: on (22:00-06:00 daily)" ]]
  grep -q '^0.0.0.0 reddit.com' "$SOCIAL_BLOCK_HOSTS"
  at '2026-09-13 06:00'; run main apply
  [[ "$output" == "social-block: off (no window active)" ]]
  ! grep -q 'reddit.com' "$SOCIAL_BLOCK_HOSTS"
}

@test "apply says nothing and writes nothing when already converged" {
  nightly
  at '2026-09-12 23:00'; main apply
  touch -d '2000-01-01' "$SOCIAL_BLOCK_HOSTS"
  run main apply
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(stat -c %Y "$SOCIAL_BLOCK_HOSTS")" = "$(date -d 2000-01-01 +%s)" ]
}

@test "an override wins until it expires, then is deleted" {
  nightly
  at '2026-09-12 23:00'
  write_override off "$(date -d '2026-09-13 06:00' +%s)"
  main apply
  ! grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
  at '2026-09-13 05:59'; main apply
  ! grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
  at '2026-09-13 22:00'; main apply
  grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
  [ ! -e "$SOCIAL_BLOCK_STATE/override" ]
}

@test "a corrupt override is ignored and removed" {
  nightly
  mkdir -p "$SOCIAL_BLOCK_STATE"; echo garbage > "$SOCIAL_BLOCK_STATE/override"
  at '2026-09-12 23:00'; main apply
  grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
  [ ! -e "$SOCIAL_BLOCK_STATE/override" ]
}

@test "invalid config fails open: block removed, exit 4, error shown once by the daemon path" {
  nightly
  at '2026-09-12 23:00'; main apply
  write_config <<'CFG'
[schedule]
25:00-06:00
CFG
  run main apply
  [ "$status" -eq 4 ]
  [[ "$output" == *'config:2: bad time "25:00"'* ]]
  ! grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
  run reconcile quiet            # same error again: silent
  [ "$status" -eq 4 ]
  [ -z "$output" ]
  echo 'junk' >> "$SOCIAL_BLOCK_CONFIG"   # still invalid, but a different error set: spoken again
  run reconcile quiet
  [[ "$output" == *'bad time "25:00"'* ]]
}

@test "an override is honoured even while the config is invalid" {
  write_config <<'CFG'
[schedule]
nonsense
[sites]
reddit.com
CFG
  at '2026-09-12 12:00'
  write_override on "$(date -d '2026-09-13 12:00' +%s)"
  run main apply
  [ "$status" -eq 4 ]
  grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
}

@test "apply refuses without write access and names the fix" {
  nightly
  chmod 0555 "$TMP"
  run main apply
  chmod 0755 "$TMP"
  [ "$status" -eq 1 ]
  [[ "$output" == *"sudo social-block apply"* ]]
}

# ---- on / off / lock ----

@test "off lifts the block until the next boundary; on forces it" {
  nightly
  at '2026-09-12 23:00'; main apply
  run main off
  [ "$status" -eq 0 ]
  [[ "$output" == "social-block: off until Sun 06:00" ]]
  ! grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
  [ "$(sed -n 2p "$SOCIAL_BLOCK_STATE/override")" = "until=$(date -d '2026-09-13 06:00' +%s)" ]
  at '2026-09-13 12:00'; main apply
  run main on
  [[ "$output" == "social-block: on until Sun 22:00" ]]
  grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
}

@test "lock refuses off during a window, allows it outside one, never refuses on" {
  locked_nightly
  at '2026-09-12 23:00'; main apply
  run main off
  [ "$status" -eq 3 ]
  [[ "$output" == *"locked"* ]]
  [[ "$output" == *"22:00-06:00 daily"* ]]
  grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
  [ ! -e "$SOCIAL_BLOCK_STATE/override" ]
  at '2026-09-13 12:00'
  run main on;  [ "$status" -eq 0 ]
  run main off; [ "$status" -eq 0 ]
}

@test "on/off with an empty schedule expire in 24 hours" {
  write_config <<'CFG'
[sites]
reddit.com
CFG
  at '2026-09-12 12:00'
  run main on
  [[ "$output" == "social-block: on until Sun 12:00" ]]
}

@test "on/off still work with an invalid config" {
  write_config <<'CFG'
[schedule]
junk
[sites]
reddit.com
CFG
  at '2026-09-12 12:00'
  run main on
  [ "$status" -eq 0 ]
  grep -q reddit.com "$SOCIAL_BLOCK_HOSTS"
}

# ---- status / check ----

@test "status reports state, schedule, next change and override" {
  nightly
  at '2026-09-12 23:00'; main apply; main off
  run main status
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "social-block: OFF (override until Sun 06:00)" ]
  [[ "$output" == *"schedule: 1 window(s), 1 site(s), lock off"* ]]
  [[ "$output" == *"  22:00-06:00 daily"* ]]
  [[ "$output" == *"next change: Sun 06:00 (in 7h 0m)"* ]]
  [[ "$output" == *"override: off until Sun 06:00"* ]]
}

@test "status flags a hosts file that is out of sync" {
  nightly
  at '2026-09-12 23:00'
  run main status
  [ "${lines[0]}" = "social-block: ON (22:00-06:00 daily)" ]
  [[ "$output" == *"hosts: off — out of sync"* ]]
}

@test "status with an invalid config exits 4 and says so" {
  write_config <<'CFG'
[schedule]
junk
CFG
  run main status
  [ "$status" -eq 4 ]
  [[ "$output" == *"config:2:"* ]]
  [[ "$output" == *"INVALID"* ]]
}

@test "check validates the installed config or a named file" {
  nightly
  run main check
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *": ok — 1 window(s), 1 site(s), lock off" ]]
  [ "${lines[1]}" = "  22:00-06:00 daily" ]
  printf '[schedule]\n9:00-17:00 weekdays\n' > "$TMP/other"
  run main check "$TMP/other"
  [ "$status" -eq 0 ]
  [[ "$output" == *"(no sites — nothing will ever be blocked)"* ]]
  printf 'garbage\n' > "$TMP/bad"
  run main check "$TMP/bad"
  [ "$status" -eq 4 ]
  [[ "$output" == 'bad:1: "garbage" is outside any section'* ]]
}
