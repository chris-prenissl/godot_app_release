load 'helpers/fixtures'

setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
	setup_fake_path
	GODOT_BIN="$FAKE_BIN_DIR/godot"
	ROOT="$BATS_TEST_TMPDIR/project"
	mkdir -p "$ROOT"
	EXPORT_PRESET="iOS"
	ARTIFACT_PATH="build/ios/App Release.ipa"
	ARTIFACT="$ROOT/$ARTIFACT_PATH"
	DEBUG_BUILD=0
}

@test "godot_export uses --export-release by default" {
	godot_export
	grep -q -- "--export-release" "$FAKE_BIN_LOG"
	grep -qv -- "--export-debug" "$FAKE_BIN_LOG"
}

@test "godot_export uses --export-debug when DEBUG_BUILD is 1" {
	DEBUG_BUILD=1
	godot_export
	grep -q -- "--export-debug" "$FAKE_BIN_LOG"
}

@test "godot_export passes the export preset and creates the artifact directory" {
	godot_export
	grep -q -- "iOS" "$FAKE_BIN_LOG"
	[ -f "$ARTIFACT" ]
}

@test "godot_export_pack fails when PCK_PATH is unset" {
	unset PCK_PATH
	run godot_export_pack
	[ "$status" -eq 1 ]
	[[ "$output" == *"PCK_PATH is not set"* ]]
}

@test "godot_export_pack invokes godot with --export-pack and produces the pck" {
	PCK_PATH="ios/App Release.pck"
	godot_export_pack
	grep -q -- "--export-pack" "$FAKE_BIN_LOG"
	[ -f "$ROOT/$PCK_PATH" ]
}
