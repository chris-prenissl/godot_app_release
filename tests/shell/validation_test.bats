setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
}

@test "require_var fails when the named variable is unset" {
	run require_var SOME_UNSET_VAR
	[ "$status" -eq 1 ]
	[[ "$output" == *"SOME_UNSET_VAR is not set"* ]]
}

@test "require_var passes when the named variable is set" {
	SOME_VAR="value"
	run require_var SOME_VAR
	[ "$status" -eq 0 ]
}

@test "wants_help returns true for -h" {
	run wants_help -h
	[ "$status" -eq 0 ]
}

@test "wants_help returns true for --help" {
	run wants_help --help
	[ "$status" -eq 0 ]
}

@test "wants_help returns false for other arguments" {
	run wants_help foo
	[ "$status" -ne 0 ]
}

@test "wants_help returns false for no arguments" {
	run wants_help
	[ "$status" -ne 0 ]
}

@test "parse_args fails with no arguments" {
	run parse_args
	[ "$status" -eq 2 ]
	[[ "$output" == *"no run.env given"* ]]
}

@test "parse_args fails with more than three arguments" {
	run parse_args a b c d
	[ "$status" -eq 2 ]
	[[ "$output" == *"expected at most 3 arguments"* ]]
}

@test "parse_args fails when the run.env path does not exist" {
	run parse_args /no/such/run.env
	[ "$status" -eq 2 ]
	[[ "$output" == *"run.env not found"* ]]
}

@test "parse_args succeeds with an existing run.env path" {
	local env_file="$BATS_TEST_TMPDIR/run.env"
	touch "$env_file"
	run parse_args "$env_file"
	[ "$status" -eq 0 ]
}

@test "parse_args accepts an optional second argument for the log path" {
	local env_file="$BATS_TEST_TMPDIR/run.env"
	touch "$env_file"
	parse_args "$env_file" "$BATS_TEST_TMPDIR/custom.log"
	[ "$LOG" = "$BATS_TEST_TMPDIR/custom.log" ]
}

@test "parse_args defaults PHASE to all when the third argument is omitted" {
	local env_file="$BATS_TEST_TMPDIR/run.env"
	touch "$env_file"
	parse_args "$env_file"
	[ "$PHASE" = "all" ]
}

@test "parse_args accepts export as the third argument" {
	local env_file="$BATS_TEST_TMPDIR/run.env"
	touch "$env_file"
	parse_args "$env_file" "" export
	[ "$PHASE" = "export" ]
}

@test "parse_args accepts upload as the third argument" {
	local env_file="$BATS_TEST_TMPDIR/run.env"
	touch "$env_file"
	parse_args "$env_file" "" upload
	[ "$PHASE" = "upload" ]
}

@test "parse_args rejects an unknown phase" {
	local env_file="$BATS_TEST_TMPDIR/run.env"
	touch "$env_file"
	run parse_args "$env_file" "" bogus
	[ "$status" -eq 2 ]
	[[ "$output" == *"unknown phase \"bogus\""* ]]
}
