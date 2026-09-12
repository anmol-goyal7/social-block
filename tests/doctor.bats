load helpers
setup()    { setup_env; }
teardown() { teardown_env; }

@test "chrome_doh_mode reads Local State in compact and pretty form" {
  echo '{"dns_over_https":{"mode":"secure","templates":"https://x/dns-query"},"other":1}' > "$TMP/ls"
  [ "$(chrome_doh_mode "$TMP/ls")" = secure ]
  printf '{\n  "dns_over_https": {\n    "mode": "off",\n    "templates": ""\n  }\n}\n' > "$TMP/ls"
  [ "$(chrome_doh_mode "$TMP/ls")" = off ]
  echo '{"something":"else"}' > "$TMP/ls"       # Chrome only writes the key once it is changed
  [ "$(chrome_doh_mode "$TMP/ls")" = automatic ]
  [ "$(chrome_doh_mode "$TMP/missing")" = unknown ]
}

@test "firefox_trr_mode reads prefs.js" {
  echo 'user_pref("network.trr.mode", 5);' > "$TMP/prefs.js"
  [ "$(firefox_trr_mode "$TMP/prefs.js")" = 5 ]
  echo 'user_pref("network.trr.mode",2);' > "$TMP/prefs.js"
  [ "$(firefox_trr_mode "$TMP/prefs.js")" = 2 ]
  echo 'user_pref("browser.startup.page", 1);' > "$TMP/prefs.js"
  [ "$(firefox_trr_mode "$TMP/prefs.js")" = unset ]
}

@test "doctor reports config and hosts checks and exits 1 on a cross" {
  printf '[schedule]\n22:00-06:00\n[sites]\nreddit.com\n' > "$SOCIAL_BLOCK_CONFIG"
  at '2026-09-12 23:00'
  HOME=$TMP run main doctor
  [[ "$output" == *"config: 1 window(s), 1 site(s), lock off"* ]]
  [[ "$output" == *"hosts: region missing but the schedule says ON"* ]]
  [ "$status" -eq 1 ]
  main apply
  HOME=$TMP run main doctor
  [[ "$output" == *"✓ hosts: matches (ON)"* ]]
}

@test "doctor finds browser profiles under HOME and flags secure DNS" {
  printf '[schedule]\n22:00-06:00\n[sites]\nreddit.com\n' > "$SOCIAL_BLOCK_CONFIG"
  at '2026-09-12 12:00'
  mkdir -p "$TMP/.config/google-chrome" "$TMP/.mozilla/firefox/abc.default"
  echo '{"dns_over_https":{"mode":"secure"}}' > "$TMP/.config/google-chrome/Local State"
  echo 'user_pref("network.trr.mode", 3);' > "$TMP/.mozilla/firefox/abc.default/prefs.js"
  HOME=$TMP run main doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ google-chrome: secure DNS is ON"* ]]
  [[ "$output" == *"✗ firefox: DNS-over-HTTPS is ON (network.trr.mode = 3)"* ]]
  echo '{"dns_over_https":{"mode":"off"}}' > "$TMP/.config/google-chrome/Local State"
  echo 'user_pref("network.trr.mode", 5);' > "$TMP/.mozilla/firefox/abc.default/prefs.js"
  HOME=$TMP run main doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ google-chrome: secure DNS is off"* ]]
  [[ "$output" == *"✓ firefox: DNS-over-HTTPS is off"* ]]
}
