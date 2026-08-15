load 'helpers/fixtures'

setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
}

@test "resolve_godot_bin uses a preset GODOT_BIN as-is" {
	setup_fake_path
	GODOT_BIN="$FAKE_BIN_DIR/godot"
	run resolve_godot_bin
	[ "$status" -eq 0 ]
	[ "$GODOT_BIN" = "$FAKE_BIN_DIR/godot" ]
}

@test "resolve_godot_bin falls back to godot on PATH when unset" {
	setup_fake_path
	unset GODOT_BIN
	run resolve_godot_bin
	[ "$status" -eq 0 ]
	[[ "$output" == *"Godot: $FAKE_BIN_DIR/godot"* ]]
}

@test "resolve_godot_bin dies when no godot binary can be found" {
	unset GODOT_BIN
	mkdir -p "$BATS_TEST_TMPDIR/empty_path"
	local original_path="$PATH"
	PATH="$BATS_TEST_TMPDIR/empty_path"
	run resolve_godot_bin
	PATH="$original_path"
	[ "$status" -eq 1 ]
	[[ "$output" == *"godot binary not found"* ]]
}

@test "resolve_godot_bin dies when GODOT_BIN points at a non-executable file" {
	GODOT_BIN="$BATS_TEST_TMPDIR/not-executable"
	touch "$GODOT_BIN"
	run resolve_godot_bin
	[ "$status" -eq 1 ]
	[[ "$output" == *"is not executable"* ]]
}
