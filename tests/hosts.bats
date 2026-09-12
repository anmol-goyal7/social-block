load helpers
setup()    { setup_env; }
teardown() { teardown_env; }

@test "render_region emits v4 and v6 lines with www/m variants" {
  SITES=(reddit.com t.co)
  run render_region
  [ "${lines[0]}" = "# BEGIN social-block" ]
  [ "${lines[1]}" = "0.0.0.0 reddit.com www.reddit.com m.reddit.com" ]
  [ "${lines[2]}" = ":: reddit.com www.reddit.com m.reddit.com" ]
  [ "${lines[3]}" = "0.0.0.0 t.co www.t.co m.t.co" ]
  [ "${lines[4]}" = ":: t.co www.t.co m.t.co" ]
  [ "${lines[5]}" = "# END social-block" ]
  [ "${#lines[@]}" -eq 6 ]
}

@test "write_hosts on adds the region after everything else and keeps it" {
  SITES=(reddit.com)
  write_hosts on
  region_present
  [ "$(sed -n 1,2p "$SOCIAL_BLOCK_HOSTS")" = $'127.0.0.1 localhost\n::1 localhost' ]
  [ "$(sed -n 3p "$SOCIAL_BLOCK_HOSTS")" = "# BEGIN social-block" ]
  [ "$(tail -n1 "$SOCIAL_BLOCK_HOSTS")" = "# END social-block" ]
}

@test "write_hosts is idempotent and leaves a matching file untouched" {
  SITES=(reddit.com)
  write_hosts on
  touch -d '2000-01-01' "$SOCIAL_BLOCK_HOSTS"
  ! write_hosts on
  [ "$(stat -c %Y "$SOCIAL_BLOCK_HOSTS")" = "$(date -d 2000-01-01 +%s)" ]
  [ "$(grep -c 'BEGIN social-block' "$SOCIAL_BLOCK_HOSTS")" -eq 1 ]
}

@test "write_hosts off removes the region and restores the original bytes" {
  SITES=(reddit.com)
  orig=$(cat "$SOCIAL_BLOCK_HOSTS")
  write_hosts on
  write_hosts off
  ! region_present
  [ "$(cat "$SOCIAL_BLOCK_HOSTS")" = "$orig" ]
  ! write_hosts off
}

@test "duplicate, damaged and stale regions are all collapsed" {
  SITES=(reddit.com)
  {
    echo '# BEGIN social-block'; echo '0.0.0.0 old.example'; echo '# END social-block'
    echo '1.2.3.4 keep.me'
    echo '# BEGIN social-block'; echo '0.0.0.0 unterminated.example'
  } >> "$SOCIAL_BLOCK_HOSTS"
  write_hosts on
  [ "$(grep -c 'BEGIN social-block' "$SOCIAL_BLOCK_HOSTS")" -eq 1 ]
  grep -q '1.2.3.4 keep.me' "$SOCIAL_BLOCK_HOSTS"
  ! grep -q 'old.example' "$SOCIAL_BLOCK_HOSTS"
  ! grep -q 'unterminated' "$SOCIAL_BLOCK_HOSTS"
  grep -q '0.0.0.0 reddit.com' "$SOCIAL_BLOCK_HOSTS"
}

@test "a file without a trailing newline still gets a well-formed region" {
  SITES=(reddit.com)
  printf '127.0.0.1 localhost' > "$SOCIAL_BLOCK_HOSTS"
  write_hosts on
  [ "$(sed -n 1p "$SOCIAL_BLOCK_HOSTS")" = "127.0.0.1 localhost" ]
  [ "$(sed -n 2p "$SOCIAL_BLOCK_HOSTS")" = "# BEGIN social-block" ]
}

@test "mode is preserved across the atomic replace" {
  SITES=(reddit.com)
  chmod 0604 "$SOCIAL_BLOCK_HOSTS"
  write_hosts on
  [ "$(stat -c %a "$SOCIAL_BLOCK_HOSTS")" = 604 ]
  [ -z "$(ls "$TMP" | grep 'hosts\.')" ]     # no temp file left behind
}
