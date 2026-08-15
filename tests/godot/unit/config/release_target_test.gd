@tool
extends GutTest

const _FIXTURE_PATH := "res://tests/fixtures/ios_basic/export_presets.cfg"
const _BLANK_EXPORT_PATH_PRESET := """[preset.0]
name="Blank"
platform="iOS"
export_path=""

[preset.0.options]
application/bundle_identifier="com.example.blank"
"""


class _FixtureBacked:
	extends FixtureSeededProjectFile

	func _real_resource_path() -> String:
		return AppReleaseStrings.export_presets_path

	func _fixture_text() -> String:
		var fixture := FileAccess.open(_FIXTURE_PATH, FileAccess.READ)
		var text := fixture.get_as_text()
		fixture.close()
		return text

	func _write_export_presets(text: String) -> void:
		_write(text)

	func _make_valid_ios_target() -> AppReleaseTarget:
		var target := AppReleaseTarget.new()
		target.export_preset = "iOS"
		target.export_options_plist = "tests/fixtures/ios_basic/ExportOptions.plist"
		return target

	func _make_valid_android_target() -> AppReleaseTarget:
		var target := AppReleaseTarget.new()
		target.export_preset = "Android"
		return target


class TestStoreId:
	extends GutTest

	func test_returns_matching_string_constant() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.APP_STORE
		assert_eq(target.store_id(), AppReleaseStrings.store_app_store)


class TestDisplayLabel:
	extends GutTest

	func test_falls_back_to_store_label_with_preset_suffix() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.TESTFLIGHT
		target.export_preset = "iOS"
		assert_eq(target.display_label(), "TestFlight (iOS)")

	func test_uses_store_label_alone_when_preset_blank() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.FIREBASE
		assert_eq(target.display_label(), "Firebase App Distribution")

	func test_uses_play_track_for_play_store() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.PLAY
		target.play_track = "internal"
		assert_eq(target.display_label(), "Google Play Internal")

	func test_prefers_explicit_label_when_set() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.TESTFLIGHT
		target.label = "My Custom Column"
		assert_eq(target.display_label(), "My Custom Column")


class TestTargetId:
	extends GutTest

	func test_lowercases_and_sanitizes() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.TESTFLIGHT
		target.export_preset = "iOS"
		assert_eq(target.target_id(), "testflight_ios")

	func test_uses_play_track_instead_of_preset_for_play_store() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.PLAY
		target.export_preset = "Android"
		target.play_track = "internal"
		assert_eq(target.target_id(), "play_internal")


class TestReleaseNotesAreNotPossible:
	extends GutTest

	func test_true_for_app_store() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.APP_STORE
		assert_true(target.release_notes_are_not_possible())

	func test_false_for_testflight() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.TESTFLIGHT
		assert_false(target.release_notes_are_not_possible())


class TestReleaseNotesDestination:
	extends GutTest

	func test_maps_testflight_to_changelog_message() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.TESTFLIGHT
		assert_eq(target.release_notes_destination(), AppReleaseStrings.notes_destination["testflight"])

	func test_maps_app_store_to_not_uploaded_message() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.APP_STORE
		assert_eq(target.release_notes_destination(), AppReleaseStrings.notes_destination["app_store"])


class TestIsIos:
	extends GutTest

	func test_true_when_platform_is_ios() -> void:
		var target := AppReleaseTarget.new()
		target.platform = AppReleaseStrings.platform_ios
		assert_true(target.is_ios())

	func test_false_when_platform_is_android() -> void:
		var target := AppReleaseTarget.new()
		target.platform = AppReleaseStrings.platform_android
		assert_false(target.is_ios())


class TestIsAndroid:
	extends GutTest

	func test_true_when_platform_is_android() -> void:
		var target := AppReleaseTarget.new()
		target.platform = AppReleaseStrings.platform_android
		assert_true(target.is_android())

	func test_false_when_platform_is_ios() -> void:
		var target := AppReleaseTarget.new()
		target.platform = AppReleaseStrings.platform_ios
		assert_false(target.is_android())


class TestNeedsNativeProject:
	extends GutTest

	func test_true_only_for_ios() -> void:
		var ios_target := AppReleaseTarget.new()
		ios_target.platform = AppReleaseStrings.platform_ios
		assert_true(ios_target.needs_native_project())

		var android_target := AppReleaseTarget.new()
		android_target.platform = AppReleaseStrings.platform_android
		assert_false(android_target.needs_native_project())


class TestResolvedArtifactPath:
	extends _FixtureBacked

	func test_returns_artifact_path_when_set() -> void:
		var target := AppReleaseTarget.new()
		target.artifact_path = "custom/path.ipa"
		assert_eq(target.resolved_artifact_path(), "custom/path.ipa")

	func test_falls_back_to_preset_export_path_when_blank() -> void:
		var target := AppReleaseTarget.new()
		target.export_preset = "iOS"
		target.artifact_path = ""
		assert_eq(target.resolved_artifact_path(), "build/ios/App Release.ipa")

	func test_returns_empty_string_when_preset_not_found_and_blank() -> void:
		var target := AppReleaseTarget.new()
		assert_eq(target.resolved_artifact_path(), "")


class TestGetConfigurationError:
	extends _FixtureBacked

	func test_message_when_export_preset_blank() -> void:
		var target := AppReleaseTarget.new()
		assert_true(target.get_configuration_error().contains("No export preset selected."))

	func test_message_when_preset_not_found() -> void:
		var target := AppReleaseTarget.new()
		target.export_preset = "NoSuchPreset"
		assert_true(target.get_configuration_error().contains("no longer exists in export_presets.cfg"))

	func test_message_when_platform_unsupported() -> void:
		var target := _make_valid_ios_target()
		target.platform = "windows"
		assert_true(target.get_configuration_error().contains("has no supported store"))

	func test_message_when_store_not_allowed_for_platform() -> void:
		var target := _make_valid_ios_target()
		target.store = AppReleaseTarget.Store.PLAY
		assert_true(target.get_configuration_error().contains("is not available for"))

	func test_message_when_fastlane_lane_blank() -> void:
		var target := _make_valid_ios_target()
		target.fastlane_lane = ""
		assert_true(target.get_configuration_error().contains("No fastlane lane set."))

	func test_message_when_resolved_artifact_path_blank() -> void:
		_write_export_presets(_BLANK_EXPORT_PATH_PRESET)
		var target := AppReleaseTarget.new()
		target.export_preset = "Blank"
		var error := target.get_configuration_error()
		assert_true(error.contains("has no export_path and no artifact path is set"))

	func test_message_when_play_store_missing_track() -> void:
		var target := _make_valid_android_target()
		target.store = AppReleaseTarget.Store.PLAY
		target.play_track = ""
		assert_true(target.get_configuration_error().contains("Google Play targets need a track."))

	func test_message_when_ios_build_mode_is_godot_export() -> void:
		var target := _make_valid_ios_target()
		target.build_mode = AppReleaseTarget.BuildMode.GODOT_EXPORT
		assert_true(target.get_configuration_error().contains("pick a build mode"))

	func test_message_when_native_project_path_blank() -> void:
		var target := _make_valid_ios_target()
		target.native_project_path = ""
		assert_true(target.get_configuration_error().contains("needs a native project path"))

	func test_message_when_pck_path_blank() -> void:
		var target := _make_valid_ios_target()
		target.pck_path = ""
		assert_true(target.get_configuration_error().contains("needs a PCK path"))

	func test_message_when_export_options_plist_blank() -> void:
		var target := _make_valid_ios_target()
		target.export_options_plist = ""
		assert_true(target.get_configuration_error().contains("xcodebuild needs an export options plist"))

	func test_message_when_export_options_plist_file_missing() -> void:
		var target := _make_valid_ios_target()
		target.export_options_plist = "ios/NoSuchFile.plist"
		assert_true(target.get_configuration_error().contains("Export options plist not found"))

	func test_empty_string_for_fully_valid_ios_target() -> void:
		var target := _make_valid_ios_target()
		assert_eq(target.get_configuration_error(), "")

	func test_empty_string_for_fully_valid_android_target() -> void:
		var target := _make_valid_android_target()
		assert_eq(target.get_configuration_error(), "")


class TestReleaseKindId:
	extends GutTest

	func test_testflight_is_test_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.TESTFLIGHT
		assert_eq(target.release_kind_id(), AppReleaseTarget.RELEASE_KIND_TEST)

	func test_firebase_is_test_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.FIREBASE
		assert_eq(target.release_kind_id(), AppReleaseTarget.RELEASE_KIND_TEST)

	func test_app_store_is_store_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.APP_STORE
		assert_eq(target.release_kind_id(), AppReleaseTarget.RELEASE_KIND_STORE)

	func test_play_internal_track_is_test_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.PLAY
		target.play_track = "internal"
		assert_eq(target.release_kind_id(), AppReleaseTarget.RELEASE_KIND_TEST)

	func test_play_alpha_track_is_test_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.PLAY
		target.play_track = "alpha"
		assert_eq(target.release_kind_id(), AppReleaseTarget.RELEASE_KIND_TEST)

	func test_play_beta_track_is_test_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.PLAY
		target.play_track = "beta"
		assert_eq(target.release_kind_id(), AppReleaseTarget.RELEASE_KIND_TEST)

	func test_play_production_track_is_store_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.PLAY
		target.play_track = "production"
		assert_eq(target.release_kind_id(), AppReleaseTarget.RELEASE_KIND_STORE)

	func test_play_blank_track_is_test_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.PLAY
		target.play_track = ""
		assert_eq(target.release_kind_id(), AppReleaseTarget.RELEASE_KIND_TEST)


class TestReleaseKindLabel:
	extends GutTest

	func test_returns_label_for_test_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.TESTFLIGHT
		assert_eq(target.release_kind_label(), "Test")

	func test_returns_label_for_store_kind() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.APP_STORE
		assert_eq(target.release_kind_label(), "Store")
