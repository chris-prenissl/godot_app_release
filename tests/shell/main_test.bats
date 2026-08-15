load 'helpers/fixtures'

setup() {
	setup_fake_path
	copy_fixture_project

	sed -i.bak "s#^GODOT_BIN=.*#GODOT_BIN=\"$FAKE_BIN_DIR/godot\"#" "$PROJECT_DIR/run.env"
	rm -f "$PROJECT_DIR/run.env.bak"

	mkdir -p "$PROJECT_DIR/ios"
	cp -R "$BATS_TEST_DIRNAME/../fixtures/ios_basic/xcodeproj_stub/MyGame.xcodeproj" \
		"$PROJECT_DIR/ios/App Release.xcodeproj"
	touch "$PROJECT_DIR/Gemfile"
}

@test "release.sh succeeds end-to-end against the fixture project and fake toolchain" {
	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" \
		"$PROJECT_DIR/run.env" "$PROJECT_DIR/manual.log"
	[ "$status" -eq 0 ]
	[[ "$output" == *"RELEASE testflight_ios SUCCEEDED"* ]]
	[ -f "$PROJECT_DIR/build/ios/App Release.ipa" ]
	[ "$(cat "$PROJECT_DIR/manual.log.exit")" = "0" ]
	[ ! -d "$PROJECT_DIR/logs/.release.lock" ]
	grep -q "bundle exec fastlane ios beta" "$FAKE_BIN_LOG"
}

@test "release.sh fails and writes a non-zero exit file when the Xcode project is missing" {
	rm -rf "$PROJECT_DIR/ios/App Release.xcodeproj"
	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" \
		"$PROJECT_DIR/run.env" "$PROJECT_DIR/manual.log"
	[ "$status" -eq 1 ]
	[[ "$output" == *"RELEASE testflight_ios FAILED"* ]]
	[ "$(cat "$PROJECT_DIR/manual.log.exit")" = "1" ]
	[ ! -d "$PROJECT_DIR/logs/.release.lock" ]
}

@test "release.sh --help prints usage without running a release" {
	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"USAGE"* ]]
	[ ! -f "$PROJECT_DIR/manual.log.exit" ]
}
