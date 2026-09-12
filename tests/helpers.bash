# Shared bats setup: every test gets a throwaway hosts/config/state and a
# sourced copy of the tool, so nothing here can touch the real system.
setup_env() {
  TMP=$(mktemp -d)
  export SOCIAL_BLOCK_HOSTS=$TMP/hosts
  export SOCIAL_BLOCK_CONFIG=$TMP/config
  export SOCIAL_BLOCK_STATE=$TMP/state
  unset SOCIAL_BLOCK_NOW
  printf '127.0.0.1 localhost\n::1 localhost\n' > "$SOCIAL_BLOCK_HOSTS"
  # shellcheck source=bin/social-block
  source "$BATS_TEST_DIRNAME/../bin/social-block"
}
teardown_env() { rm -rf "$TMP"; }
write_config() { cat > "$SOCIAL_BLOCK_CONFIG"; }
# shellcheck disable=SC2034
at() { export SOCIAL_BLOCK_NOW=$1; NOW_OVERRIDE=$1; }
