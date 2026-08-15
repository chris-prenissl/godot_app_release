setup_fake_path() {
	FAKE_BIN_DIR="$BATS_TEST_TMPDIR/fake_bin"
	mkdir -p "$FAKE_BIN_DIR"
	cp "$BATS_TEST_DIRNAME/fake_bin/"* "$FAKE_BIN_DIR/"
	chmod +x "$FAKE_BIN_DIR"/*

	FAKE_BIN_LOG="$BATS_TEST_TMPDIR/fake_bin.log"
	export FAKE_BIN_LOG
	: > "$FAKE_BIN_LOG"

	export PATH="$FAKE_BIN_DIR:$PATH"
}

copy_fixture_project() {
	local fixture_dir="$BATS_TEST_DIRNAME/../fixtures/ios_basic"
	PROJECT_DIR="$BATS_TEST_TMPDIR/project"
	mkdir -p "$PROJECT_DIR"
	cp -R "$fixture_dir"/. "$PROJECT_DIR/"
	sed -i.bak "s#__ROOT__#$PROJECT_DIR#" "$PROJECT_DIR/run.env"
	rm -f "$PROJECT_DIR/run.env.bak"
}
