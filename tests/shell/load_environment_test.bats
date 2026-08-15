load 'helpers/fixtures'

setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
	copy_fixture_project
}

write_minimal_env() {
	cat > "$PROJECT_DIR/minimal.env" <<EOF
PROJECT_ROOT="$PROJECT_DIR"
TARGET_ID="t"
PLATFORM="ios"
STORE="testflight"
LANE="beta"
EXPORT_PRESET="iOS"
BUILD_MODE="REGENERATE_NATIVE_PROJECT"
ARTIFACT_PATH="build/ios/App Release.ipa"
VERSION="1.0.0"
BUILD="1"
EOF
}

@test "load_environment derives ROOT, LOCK_DIR and ARTIFACT from the run.env fixture" {
	ENV_FILE="$PROJECT_DIR/run.env"
	load_environment
	[ "$ROOT" = "$PROJECT_DIR" ]
	[ "$LOCK_DIR" = "$PROJECT_DIR/logs/.release.lock.testflight_ios" ]
	[ "$ARTIFACT" = "$PROJECT_DIR/build/ios/App Release.ipa" ]
}

@test "load_environment fails when a required variable is missing" {
	write_minimal_env
	sed -i.bak '/^PLATFORM=/d' "$PROJECT_DIR/minimal.env"
	ENV_FILE="$PROJECT_DIR/minimal.env"
	run load_environment
	[ "$status" -eq 1 ]
	[[ "$output" == *"PLATFORM is not set"* ]]
}

@test "load_environment defaults LOGS_DIR to logs when unset" {
	write_minimal_env
	ENV_FILE="$PROJECT_DIR/minimal.env"
	load_environment
	[ "$LOGS_DIR" = "logs" ]
}

@test "load_environment defaults KEEP_LOGS to 20 when unset" {
	write_minimal_env
	ENV_FILE="$PROJECT_DIR/minimal.env"
	load_environment
	[ "$KEEP_LOGS" = "20" ]
}

@test "load_environment defaults DEBUG_BUILD to 0 when unset" {
	write_minimal_env
	ENV_FILE="$PROJECT_DIR/minimal.env"
	load_environment
	[ "$DEBUG_BUILD" = "0" ]
}

@test "load_environment honors an explicit LOGS_DIR and KEEP_LOGS" {
	write_minimal_env
	{
		echo 'LOGS_DIR="custom-logs"'
		echo 'KEEP_LOGS="5"'
	} >> "$PROJECT_DIR/minimal.env"
	ENV_FILE="$PROJECT_DIR/minimal.env"
	load_environment
	[ "$LOGS_DIR" = "custom-logs" ]
	[ "$KEEP_LOGS" = "5" ]
	[ "$LOCK_DIR" = "$PROJECT_DIR/custom-logs/.release.lock.t" ]
}

@test "load_environment gives two different targets two different lock dirs" {
	write_minimal_env
	ENV_FILE="$PROJECT_DIR/minimal.env"
	load_environment
	local first_lock_dir="$LOCK_DIR"

	sed -i.bak 's/TARGET_ID="t"/TARGET_ID="other"/' "$PROJECT_DIR/minimal.env"
	load_environment
	local second_lock_dir="$LOCK_DIR"

	[ "$first_lock_dir" != "$second_lock_dir" ]
}

@test "load_environment overrides PATH when EXTRA_PATH is set" {
	write_minimal_env
	echo 'EXTRA_PATH="/custom/bin:/usr/bin"' >> "$PROJECT_DIR/minimal.env"
	ENV_FILE="$PROJECT_DIR/minimal.env"
	(
		load_environment
		[ "$PATH" = "/custom/bin:/usr/bin" ]
	)
}

@test "load_environment leaves PATH untouched when EXTRA_PATH is unset" {
	write_minimal_env
	local original_path="$PATH"
	ENV_FILE="$PROJECT_DIR/minimal.env"
	load_environment
	[ "$PATH" = "$original_path" ]
}
