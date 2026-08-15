setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
	ROOT="$BATS_TEST_TMPDIR"
	LOGS_DIR="logs"
	KEEP_LOGS=2
	mkdir -p "$ROOT/$LOGS_DIR" "$ROOT/.release_tools"
}

@test "rotate_logs keeps the newest KEEP_LOGS logs and deletes the rest" {
	for i in 1 2 3 4; do
		touch -t "202401010${i}00" "$ROOT/$LOGS_DIR/release_t_20240101_0${i}0000.log"
	done
	rotate_logs
	local count
	count=$(ls "$ROOT/$LOGS_DIR"/release_*.log | wc -l)
	[ "$count" -eq 2 ]
}

@test "rotate_logs deletes the .exit sibling of a pruned log" {
	for i in 1 2 3 4; do
		local log="$ROOT/$LOGS_DIR/release_t_20240101_0${i}0000.log"
		touch -t "202401010${i}00" "$log"
		echo 0 >"$log.exit"
	done
	rotate_logs
	local exit_count
	exit_count=$(ls "$ROOT/$LOGS_DIR"/release_*.log.exit 2>/dev/null | wc -l)
	[ "$exit_count" -eq 2 ]
}

@test "rotate_logs never deletes the current LOG even if it is old" {
	LOG="$ROOT/$LOGS_DIR/release_t_20240101_010000.log"
	touch -t 202401010100 "$LOG"
	for i in 2 3 4; do
		touch -t "202401010${i}00" "$ROOT/$LOGS_DIR/release_t_20240101_0${i}0000.log"
	done
	rotate_logs
	[ -f "$LOG" ]
}

@test "rotate_logs does nothing when fewer than KEEP_LOGS logs exist" {
	touch "$ROOT/$LOGS_DIR/release_t_20240101_010000.log"
	rotate_logs
	local count
	count=$(ls "$ROOT/$LOGS_DIR"/release_*.log | wc -l)
	[ "$count" -eq 1 ]
}

@test "rotate_logs prunes stale .release_notes_* scratch files except the current one" {
	touch "$ROOT/.release_tools/.release_notes_old.txt"
	RELEASE_NOTES_FILE="$ROOT/.release_tools/.release_notes_current.txt"
	touch "$RELEASE_NOTES_FILE"
	rotate_logs
	[ ! -f "$ROOT/.release_tools/.release_notes_old.txt" ]
	[ -f "$RELEASE_NOTES_FILE" ]
}

@test "rotate_logs prunes all scratch notes when RELEASE_NOTES_FILE is unset" {
	touch "$ROOT/.release_tools/.release_notes_old.txt"
	RELEASE_NOTES_FILE=""
	rotate_logs
	[ ! -f "$ROOT/.release_tools/.release_notes_old.txt" ]
}
