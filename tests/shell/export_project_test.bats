load 'helpers/fixtures'

setup() {
	source "$BATS_TEST_DIRNAME/../../addons/app_release/scripts/release.sh"
	setup_fake_path
	copy_fixture_project

	ROOT="$PROJECT_DIR"
	GODOT_BIN="$FAKE_BIN_DIR/godot"
	EXPORT_PRESET="iOS"
	ARTIFACT_PATH="build/ios/App Release.ipa"
	ARTIFACT="$ROOT/$ARTIFACT_PATH"
	DEBUG_BUILD=0
	VERSION="1.0.0"
	BUILD="1"
	NATIVE_PROJECT_PATH="ios/App Release.xcodeproj"
	XCODE_SCHEME="App Release"
	IOS_EXPORT_OPTIONS="ExportOptions.plist"
	PCK_PATH="ios/App Release.pck"

	mkdir -p "$ROOT/ios"
	cp -R "$BATS_TEST_DIRNAME/../fixtures/ios_basic/xcodeproj_stub/MyGame.xcodeproj" \
		"$ROOT/ios/App Release.xcodeproj"
}

@test "export_project dies for BUILD_MODE=GODOT_EXPORT on iOS" {
	BUILD_MODE="GODOT_EXPORT"
	PLATFORM="ios"
	run export_project
	[ "$status" -eq 1 ]
	[[ "$output" == *"cannot work for iOS"* ]]
}

@test "export_project runs a plain godot export for BUILD_MODE=GODOT_EXPORT on android" {
	BUILD_MODE="GODOT_EXPORT"
	PLATFORM="android"
	ARTIFACT_PATH="build/android/App Release.aab"
	ARTIFACT="$ROOT/$ARTIFACT_PATH"
	run export_project
	[ "$status" -eq 0 ]
	grep -q -- "--export-release" "$FAKE_BIN_LOG"
	grep -qv "xcodebuild" "$FAKE_BIN_LOG"
	[ -f "$ARTIFACT" ]
}

@test "export_project only exports for BUILD_MODE=REGENERATE_NATIVE_PROJECT on android" {
	BUILD_MODE="REGENERATE_NATIVE_PROJECT"
	PLATFORM="android"
	ARTIFACT_PATH="build/android/App Release.aab"
	ARTIFACT="$ROOT/$ARTIFACT_PATH"
	run export_project
	[ "$status" -eq 0 ]
	grep -qv "xcodebuild" "$FAKE_BIN_LOG"
}

@test "export_project runs godot export then xcodebuild for BUILD_MODE=REGENERATE_NATIVE_PROJECT on iOS" {
	BUILD_MODE="REGENERATE_NATIVE_PROJECT"
	PLATFORM="ios"
	run export_project
	[ "$status" -eq 0 ]
	grep -q -- "--export-release" "$FAKE_BIN_LOG"
	grep -q "xcodebuild archive" "$FAKE_BIN_LOG"
	grep -q "xcodebuild -exportArchive" "$FAKE_BIN_LOG"
	[ -f "$ARTIFACT" ]
}

@test "export_project only exports for BUILD_MODE=PCK_ONLY on android" {
	BUILD_MODE="PCK_ONLY"
	PLATFORM="android"
	ARTIFACT_PATH="build/android/App Release.aab"
	ARTIFACT="$ROOT/$ARTIFACT_PATH"
	run export_project
	[ "$status" -eq 0 ]
	grep -qv "xcodebuild" "$FAKE_BIN_LOG"
}

@test "export_project exports the pck then runs xcodebuild for BUILD_MODE=PCK_ONLY on iOS" {
	BUILD_MODE="PCK_ONLY"
	PLATFORM="ios"
	run export_project
	[ "$status" -eq 0 ]
	grep -q -- "--export-pack" "$FAKE_BIN_LOG"
	grep -qv -- "--export-release" "$FAKE_BIN_LOG"
	grep -q "xcodebuild archive" "$FAKE_BIN_LOG"
	[ -f "$ARTIFACT" ]
}

@test "export_project fails on an unknown BUILD_MODE" {
	BUILD_MODE="NONSENSE"
	PLATFORM="android"
	run export_project
	[ "$status" -eq 2 ]
	[[ "$output" == *"unknown BUILD_MODE: NONSENSE"* ]]
}

@test "export_project dies when the expected artifact is missing after export" {
	BUILD_MODE="GODOT_EXPORT"
	PLATFORM="android"
	ARTIFACT_PATH="build/android/App Release.aab"
	ARTIFACT="$ROOT/$ARTIFACT_PATH"
	cat > "$FAKE_BIN_DIR/godot" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
	chmod +x "$FAKE_BIN_DIR/godot"
	run export_project
	[ "$status" -eq 1 ]
	[[ "$output" == *"expected artifact missing after export"* ]]
}
