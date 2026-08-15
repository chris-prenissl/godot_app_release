setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
}

@test "resolve_groups trims whitespace and drops empty entries" {
	RELEASE_GROUPS=" internal , , beta "
	resolve_groups
	[ "$RELEASE_GROUPS" = "internal,beta" ]
}

@test "resolve_groups leaves an already-clean list untouched" {
	RELEASE_GROUPS="internal,beta"
	resolve_groups
	[ "$RELEASE_GROUPS" = "internal,beta" ]
}

@test "resolve_groups reports none for empty input without failing" {
	RELEASE_GROUPS=""
	run resolve_groups
	[ "$status" -eq 0 ]
	[[ "$output" == *"none"* ]]
}

@test "resolve_groups reports none when RELEASE_GROUPS is unset" {
	unset RELEASE_GROUPS
	run resolve_groups
	[ "$status" -eq 0 ]
	[[ "$output" == *"none"* ]]
}

@test "resolve_groups rejects an all-numeric group list" {
	RELEASE_GROUPS="123,456"
	run resolve_groups
	[ "$status" -eq 2 ]
	[[ "$output" == *"look like numbers"* ]]
}

@test "resolve_groups rejects a single numeric group" {
	RELEASE_GROUPS="123"
	run resolve_groups
	[ "$status" -eq 2 ]
}

@test "resolve_groups accepts a mixed alphanumeric group name" {
	RELEASE_GROUPS="beta2"
	run resolve_groups
	[ "$status" -eq 0 ]
}

@test "resolve_groups echoes the resolved list on success" {
	RELEASE_GROUPS="internal-testers"
	run resolve_groups
	[[ "$output" == *"Tester groups: internal-testers"* ]]
}
