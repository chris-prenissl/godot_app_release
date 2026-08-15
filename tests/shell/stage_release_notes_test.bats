setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
	ROOT="$BATS_TEST_TMPDIR"
	PLATFORM="android"
	VERSION="1.0.0"
	BUILD="1"
	mkdir -p "$ROOT"
}

@test "stage_release_notes is a no-op when RELEASE_NOTES_FILE is unset" {
	unset RELEASE_NOTES_FILE
	run stage_release_notes
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "stage_release_notes is a no-op when RELEASE_NOTES_FILE is empty" {
	RELEASE_NOTES_FILE="$BATS_TEST_TMPDIR/notes.txt"
	touch "$RELEASE_NOTES_FILE"
	run stage_release_notes
	[ "$status" -eq 0 ]
	[ -z "$output" ]
}

@test "stage_release_notes prints the notes prefixed with a pipe" {
	RELEASE_NOTES_FILE="$BATS_TEST_TMPDIR/notes.txt"
	printf 'Fixed a crash\nAdded a feature\n' > "$RELEASE_NOTES_FILE"
	run stage_release_notes
	[[ "$output" == *"  | Fixed a crash"* ]]
	[[ "$output" == *"  | Added a feature"* ]]
}

@test "stage_release_notes copies to PLAY_CHANGELOGS_DIR for android" {
	RELEASE_NOTES_FILE="$BATS_TEST_TMPDIR/notes.txt"
	echo "notes" > "$RELEASE_NOTES_FILE"
	PLATFORM="android"
	PLAY_CHANGELOGS_DIR="fastlane/metadata/android/en-US/changelogs"
	stage_release_notes
	[ -f "$ROOT/$PLAY_CHANGELOGS_DIR/1.txt" ]
	[ "$(cat "$ROOT/$PLAY_CHANGELOGS_DIR/1.txt")" = "notes" ]
}

@test "stage_release_notes skips PLAY_CHANGELOGS_DIR for ios" {
	RELEASE_NOTES_FILE="$BATS_TEST_TMPDIR/notes.txt"
	echo "notes" > "$RELEASE_NOTES_FILE"
	PLATFORM="ios"
	PLAY_CHANGELOGS_DIR="fastlane/metadata/android/en-US/changelogs"
	stage_release_notes
	[ ! -d "$ROOT/$PLAY_CHANGELOGS_DIR" ]
}

@test "stage_release_notes skips PLAY_CHANGELOGS_DIR when unset" {
	RELEASE_NOTES_FILE="$BATS_TEST_TMPDIR/notes.txt"
	echo "notes" > "$RELEASE_NOTES_FILE"
	PLATFORM="android"
	unset PLAY_CHANGELOGS_DIR
	run stage_release_notes
	[ "$status" -eq 0 ]
}

@test "stage_release_notes archives to RELEASE_NOTES_DIR with a version header" {
	RELEASE_NOTES_FILE="$BATS_TEST_TMPDIR/notes.txt"
	echo "notes body" > "$RELEASE_NOTES_FILE"
	RELEASE_NOTES_DIR="release-notes"
	stage_release_notes
	local archived="$ROOT/$RELEASE_NOTES_DIR/1.0.0-1.md"
	[ -f "$archived" ]
	[[ "$(cat "$archived")" == *"# 1.0.0 (build 1)"* ]]
	[[ "$(cat "$archived")" == *"notes body"* ]]
}

@test "stage_release_notes skips archiving when RELEASE_NOTES_DIR is unset" {
	RELEASE_NOTES_FILE="$BATS_TEST_TMPDIR/notes.txt"
	echo "notes" > "$RELEASE_NOTES_FILE"
	unset RELEASE_NOTES_DIR
	run stage_release_notes
	[ "$status" -eq 0 ]
	[[ "$output" != *"Notes archived"* ]]
}
