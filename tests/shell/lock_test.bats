setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
	LOCK_DIR="$BATS_TEST_TMPDIR/.release.lock"
}

@test "acquire_lock creates the lock dir and writes its own pid" {
	acquire_lock
	[ -d "$LOCK_DIR" ]
	[ "$(cat "$LOCK_DIR/pid")" = "$$" ]
	[ "$LOCK_HELD" -eq 1 ]
}

@test "acquire_lock fails when a live process holds the lock" {
	mkdir "$LOCK_DIR"
	echo "$$" >"$LOCK_DIR/pid"
	run acquire_lock
	[ "$status" -eq 2 ]
	[[ "$output" == *"another release is already running"* ]]
}

@test "acquire_lock removes a stale lock from a dead pid and re-acquires" {
	mkdir "$LOCK_DIR"
	echo "999999" >"$LOCK_DIR/pid"
	run acquire_lock
	[ "$status" -eq 0 ]
}

@test "acquire_lock removing a stale lock actually replaces the pid file" {
	mkdir "$LOCK_DIR"
	echo "999999" >"$LOCK_DIR/pid"
	acquire_lock
	[ "$(cat "$LOCK_DIR/pid")" = "$$" ]
}

@test "acquire_lock treats a lock dir with no pid file as stale" {
	mkdir "$LOCK_DIR"
	run acquire_lock
	[ "$status" -eq 0 ]
	[ "$(cat "$LOCK_DIR/pid")" = "$$" ]
}

@test "on_exit releases the lock when LOCK_HELD is 1" {
	mkdir "$LOCK_DIR"
	LOCK_HELD=1
	LOG="$BATS_TEST_TMPDIR/x.log"
	TARGET_ID=t
	on_exit
	[ ! -d "$LOCK_DIR" ]
}

@test "on_exit does not touch the lock dir when LOCK_HELD is 0" {
	mkdir "$LOCK_DIR"
	LOCK_HELD=0
	LOG="$BATS_TEST_TMPDIR/x.log"
	TARGET_ID=t
	on_exit
	[ -d "$LOCK_DIR" ]
}

@test "on_exit writes the exit status to <log>.exit" {
	LOCK_HELD=0
	LOG="$BATS_TEST_TMPDIR/x.log"
	TARGET_ID=t
	set +e
	false
	on_exit
	[ "$(cat "$LOG.exit")" = "1" ]
}

@test "on_exit skips writing an exit file when LOG is unset" {
	LOCK_HELD=0
	LOG=""
	TARGET_ID=t
	on_exit
	run bash -c "shopt -s nullglob; echo \"$BATS_TEST_TMPDIR\"/*.exit"
	[ -z "$output" ]
}
