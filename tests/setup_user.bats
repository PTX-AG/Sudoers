#!/usr/bin/env bats

SCRIPT="${BATS_TEST_DIRNAME}/../setup_user.sh"

@test "--help displays usage" {
  run bash -c "$SCRIPT --help"
  [ "$status" -eq 0 ]
  [[ "$output" =~ Usage: ]]
}

@test "--dry-run flag shows dry-run messages" {
  run bash -c "$SCRIPT --dry-run --username testuser"
  [ "$status" -eq 0 ]
  [[ "$output" =~ \[DRY-RUN\] ]]
}
