RELEASE_SH="$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"

setup() {
	ROOT="$BATS_TEST_TMPDIR/project"
	mkdir -p "$ROOT"
}

@test "setup_logging creates the logs directory" {
	bash -c "
		source '$RELEASE_SH'
		ROOT='$ROOT'
		LOGS_DIR='logs'
		LOG=''
		TARGET_ID='t'
		setup_logging
	"
	[ -d "$ROOT/logs" ]
}

@test "setup_logging derives a timestamped default log path under LOGS_DIR" {
	bash -c "
		source '$RELEASE_SH'
		ROOT='$ROOT'
		LOGS_DIR='logs'
		LOG=''
		TARGET_ID='mytarget'
		setup_logging
		echo \"\$LOG\" > '$ROOT/marker.txt'
	"
	local logged_path
	logged_path="$(cat "$ROOT/marker.txt")"
	[[ "$logged_path" == "$ROOT/logs/release_mytarget_"*".log" ]]
}

@test "setup_logging respects an explicitly given LOG path" {
	local custom_log="$ROOT/custom/manual.log"
	bash -c "
		source '$RELEASE_SH'
		ROOT='$ROOT'
		LOGS_DIR='logs'
		LOG='$custom_log'
		TARGET_ID='t'
		setup_logging
		echo \"\$LOG\" > '$ROOT/marker.txt'
	"
	[ "$(cat "$ROOT/marker.txt")" = "$custom_log" ]
	[ -d "$ROOT/custom" ]
}

@test "setup_logging removes a stale .exit file at the log path" {
	local custom_log="$ROOT/manual.log"
	echo "0" > "$custom_log.exit"
	bash -c "
		source '$RELEASE_SH'
		ROOT='$ROOT'
		LOGS_DIR='logs'
		LOG='$custom_log'
		TARGET_ID='t'
		setup_logging
	"
	[ ! -f "$custom_log.exit" ]
}

@test "setup_logging writes subsequent output into the log file" {
	local custom_log="$ROOT/manual.log"
	bash -c "
		source '$RELEASE_SH'
		ROOT='$ROOT'
		LOGS_DIR='logs'
		LOG='$custom_log'
		TARGET_ID='t'
		setup_logging
		echo 'hello from after setup_logging'
	"
	[ -f "$custom_log" ]
	grep -q "hello from after setup_logging" "$custom_log"
}
