load 'helpers/fixtures'

setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
	setup_fake_path
	copy_fixture_project

	ROOT="$PROJECT_DIR"
	NATIVE_PROJECT_PATH="ios/App Release.xcodeproj"
	XCODE_SCHEME="App Release"
	IOS_EXPORT_OPTIONS="ExportOptions.plist"
	VERSION="1.0.0"
	BUILD="1"
	DEBUG_BUILD=0
	ARTIFACT="$ROOT/build/ios/App Release.ipa"

	mkdir -p "$ROOT/ios"
	cp -R "$BATS_TEST_DIRNAME/../fixtures/ios_basic/xcodeproj_stub/MyGame.xcodeproj" \
		"$ROOT/ios/App Release.xcodeproj"
}

@test "build_ios_with_xcode fails fast when the Xcode project directory is missing" {
	rm -rf "$ROOT/ios/App Release.xcodeproj"
	run build_ios_with_xcode
	[ "$status" -eq 1 ]
	[[ "$output" == *"Xcode project not found"* ]]
}

@test "build_ios_with_xcode fails when a required var is missing" {
	XCODE_SCHEME=""
	run build_ios_with_xcode
	[ "$status" -eq 1 ]
	[[ "$output" == *"XCODE_SCHEME is not set"* ]]
}

@test "build_ios_with_xcode invokes archive then exportArchive via the fake xcodebuild" {
	run build_ios_with_xcode
	[ "$status" -eq 0 ]
	grep -q "xcodebuild archive" "$FAKE_BIN_LOG"
	grep -q "xcodebuild -exportArchive" "$FAKE_BIN_LOG"
}

@test "build_ios_with_xcode produces the artifact at ARTIFACT" {
	run build_ios_with_xcode
	[ "$status" -eq 0 ]
	[ -f "$ARTIFACT" ]
}

@test "build_ios_with_xcode passes the project, scheme and export options to xcodebuild" {
	run build_ios_with_xcode
	grep -q -- "-project $ROOT/ios/App Release.xcodeproj" "$FAKE_BIN_LOG"
	grep -q -- "-scheme App Release" "$FAKE_BIN_LOG"
	grep -q -- "-exportOptionsPlist $ROOT/ExportOptions.plist" "$FAKE_BIN_LOG"
}

@test "build_ios_with_xcode passes MARKETING_VERSION and CURRENT_PROJECT_VERSION to the archive step" {
	run build_ios_with_xcode
	grep -q "MARKETING_VERSION=1.0.0" "$FAKE_BIN_LOG"
	grep -q "CURRENT_PROJECT_VERSION=1" "$FAKE_BIN_LOG"
}

@test "build_ios_with_xcode uses the Release configuration by default" {
	run build_ios_with_xcode
	grep -q -- "-configuration Release" "$FAKE_BIN_LOG"
}

@test "build_ios_with_xcode uses the Debug configuration when DEBUG_BUILD is 1" {
	DEBUG_BUILD=1
	run build_ios_with_xcode
	grep -q -- "-configuration Debug" "$FAKE_BIN_LOG"
}

@test "build_ios_with_xcode dies when xcodebuild -exportArchive produces no ipa" {
	cat > "$FAKE_BIN_DIR/xcodebuild" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$FAKE_BIN_DIR/xcodebuild"

	run build_ios_with_xcode
	[ "$status" -eq 1 ]
	[[ "$output" == *"produced no .ipa"* ]]
}

@test "build_ios_with_xcode never invokes the real xcodebuild" {
	run build_ios_with_xcode
	[ "$status" -eq 0 ]
	run bash -c "command -v xcodebuild"
	[[ "$output" == "$FAKE_BIN_DIR/xcodebuild" ]]
}
