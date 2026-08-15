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
	[ ! -d "$PROJECT_DIR/logs/.release.lock.testflight_ios" ]
	grep -q "bundle exec fastlane ios beta" "$FAKE_BIN_LOG"
}

@test "release.sh fails and writes a non-zero exit file when the Xcode project is missing" {
	rm -rf "$PROJECT_DIR/ios/App Release.xcodeproj"
	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" \
		"$PROJECT_DIR/run.env" "$PROJECT_DIR/manual.log"
	[ "$status" -eq 1 ]
	[[ "$output" == *"RELEASE testflight_ios FAILED"* ]]
	[ "$(cat "$PROJECT_DIR/manual.log.exit")" = "1" ]
	[ ! -d "$PROJECT_DIR/logs/.release.lock.testflight_ios" ]
}

@test "release.sh --help prints usage without running a release" {
	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" --help
	[ "$status" -eq 0 ]
	[[ "$output" == *"USAGE"* ]]
	[ ! -f "$PROJECT_DIR/manual.log.exit" ]
}

@test "release.sh export phase produces the artifact but never calls fastlane" {
	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" \
		"$PROJECT_DIR/run.env" "$PROJECT_DIR/export.log" export
	[ "$status" -eq 0 ]
	[ -f "$PROJECT_DIR/build/ios/App Release.ipa" ]
	! grep -q "fastlane" "$FAKE_BIN_LOG"
}

@test "release.sh upload phase dies when no artifact exists yet" {
	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" \
		"$PROJECT_DIR/run.env" "$PROJECT_DIR/upload.log" upload
	[ "$status" -eq 1 ]
	[[ "$output" == *"no artifact at"* ]]
	! grep -q "fastlane" "$FAKE_BIN_LOG"
}

@test "release.sh upload phase runs fastlane without re-exporting when the artifact already exists" {
	mkdir -p "$PROJECT_DIR/build/ios"
	echo "pre-existing artifact" > "$PROJECT_DIR/build/ios/App Release.ipa"

	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" \
		"$PROJECT_DIR/run.env" "$PROJECT_DIR/upload.log" upload
	[ "$status" -eq 0 ]
	grep -q "bundle exec fastlane ios beta" "$FAKE_BIN_LOG"
	! grep -q "xcodebuild" "$FAKE_BIN_LOG"
	! grep -q "^godot " "$FAKE_BIN_LOG"
	[ "$(cat "$PROJECT_DIR/build/ios/App Release.ipa")" = "pre-existing artifact" ]
}

@test "release.sh runs a real two-phase export-then-upload release across two separate processes" {
	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" \
		"$PROJECT_DIR/run.env" "$PROJECT_DIR/export.log" export
	[ "$status" -eq 0 ]
	[ -f "$PROJECT_DIR/build/ios/App Release.ipa" ]
	! grep -q "fastlane" "$FAKE_BIN_LOG"

	run bash "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh" \
		"$PROJECT_DIR/run.env" "$PROJECT_DIR/upload.log" upload
	[ "$status" -eq 0 ]
	grep -q "bundle exec fastlane ios beta" "$FAKE_BIN_LOG"

	# exported exactly once across the whole two-phase run — the upload phase
	# didn't re-export.
	local godot_invocations
	godot_invocations=$(grep -c "^godot " "$FAKE_BIN_LOG")
	[ "$godot_invocations" -eq 1 ]
}
