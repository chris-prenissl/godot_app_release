load 'helpers/fixtures'

setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
	setup_fake_path
	ROOT="$BATS_TEST_TMPDIR/project"
	mkdir -p "$ROOT"
	touch "$ROOT/Gemfile"
	PLATFORM="ios"
	LANE="beta"
	ARTIFACT="$ROOT/build/ios/App Release.ipa"
}

@test "run_fastlane dies when the project has no Gemfile" {
	rm -f "$ROOT/Gemfile"
	run run_fastlane
	[ "$status" -eq 1 ]
	[[ "$output" == *"no Gemfile in $ROOT"* ]]
}

@test "run_fastlane runs bundle install when bundle check fails" {
	cat > "$FAKE_BIN_DIR/bundle" <<EOF
#!/usr/bin/env bash
echo "bundle \$*" >> "$FAKE_BIN_LOG"
[ "\$1" = "check" ] && exit 1
exit 0
EOF
	chmod +x "$FAKE_BIN_DIR/bundle"
	run run_fastlane
	[ "$status" -eq 0 ]
	grep -q "bundle install" "$FAKE_BIN_LOG"
}

@test "run_fastlane skips bundle install when bundle check succeeds" {
	run run_fastlane
	[ "$status" -eq 0 ]
	grep -qv "bundle install" "$FAKE_BIN_LOG"
}

@test "run_fastlane invokes bundle exec fastlane with the platform and lane" {
	run run_fastlane
	grep -q "bundle exec fastlane ios beta" "$FAKE_BIN_LOG"
}

@test "run_fastlane exports IPA_PATH for an .ipa artifact" {
	(
		run_fastlane
		[ "$IPA_PATH" = "$ARTIFACT" ]
	)
}

@test "run_fastlane exports APK_PATH for an .apk artifact" {
	PLATFORM="android"
	LANE="firebase"
	ARTIFACT="$ROOT/build/android/App Release.apk"
	(
		run_fastlane
		[ "$APK_PATH" = "$ARTIFACT" ]
	)
}

@test "run_fastlane exports AAB_PATH for an .aab artifact" {
	PLATFORM="android"
	LANE="internal"
	ARTIFACT="$ROOT/build/android/App Release.aab"
	(
		run_fastlane
		[ "$AAB_PATH" = "$ARTIFACT" ]
	)
}
