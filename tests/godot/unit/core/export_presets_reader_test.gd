extends GutTest

const _FIXTURE_PATH := "res://tests/fixtures/ios_basic/export_presets.cfg"


class _FixtureBacked:
	extends GutTest

	var _real_export_presets_path: String
	var _preset_ios: Dictionary
	var _preset_android: Dictionary

	func before_each() -> void:
		_real_export_presets_path = ProjectSettings.globalize_path(AppReleaseStrings.export_presets_path)
		var fixture := FileAccess.open(_FIXTURE_PATH, FileAccess.READ)
		var text := fixture.get_as_text()
		fixture.close()

		var sink := FileAccess.open(_real_export_presets_path, FileAccess.WRITE)
		sink.store_string(text)
		sink.close()

		_preset_ios = AppReleasePresets.find_preset("iOS")
		_preset_android = AppReleasePresets.find_preset("Android")

	func after_each() -> void:
		if FileAccess.file_exists(_real_export_presets_path):
			DirAccess.remove_absolute(_real_export_presets_path)


class TestListPresets:
	extends _FixtureBacked

	func test_returns_both_presets_from_fixture() -> void:
		assert_eq(AppReleasePresets.list_presets().size(), 2)

	func test_maps_platform_ios_and_android_correctly() -> void:
		assert_eq(_preset_ios["platform"], AppReleaseStrings.platform_ios)
		assert_eq(_preset_android["platform"], AppReleaseStrings.platform_android)


class TestFindPreset:
	extends _FixtureBacked

	func test_returns_matching_dict_for_known_name() -> void:
		assert_eq(_preset_ios["export_path"], "build/ios/App Release.ipa")

	func test_returns_empty_dict_for_unknown_name() -> void:
		assert_true(AppReleasePresets.find_preset("no such preset").is_empty())


class TestBundleIdentifierOf:
	extends _FixtureBacked

	func test_reads_ios_bundle_id() -> void:
		assert_eq(AppReleasePresets.bundle_identifier_of(_preset_ios), "com.example.apprelease.ios")

	func test_reads_android_package_name() -> void:
		assert_eq(AppReleasePresets.bundle_identifier_of(_preset_android), "com.example.apprelease.android")

	func test_returns_empty_string_for_empty_preset() -> void:
		assert_eq(AppReleasePresets.bundle_identifier_of({}), "")


class TestAppleTeamIdOf:
	extends _FixtureBacked

	func test_reads_team_id_for_ios() -> void:
		assert_eq(AppReleasePresets.apple_team_id_of(_preset_ios), "ABCDE12345")

	func test_returns_empty_string_for_android() -> void:
		assert_eq(AppReleasePresets.apple_team_id_of(_preset_android), "")


class TestVersionOf:
	extends _FixtureBacked

	func test_falls_back_to_application_short_version_when_version_name_absent() -> void:
		var version := AppReleasePresets.version_of(_preset_ios)
		assert_eq(version["version"], "1.0.0")
		assert_eq(version["build"], 1)

	func test_prefers_version_name_and_version_code_when_present() -> void:
		var version := AppReleasePresets.version_of(_preset_android)
		assert_eq(version["version"], "2.5.0")
		assert_eq(version["build"], 7)

	func test_returns_placeholder_for_empty_preset() -> void:
		var version := AppReleasePresets.version_of({})
		assert_eq(version["version"], AppReleaseStrings.placeholder_version)
		assert_eq(version["build"], 1)


class TestUsesGradleBuild:
	extends _FixtureBacked

	func test_true_for_android_preset() -> void:
		assert_true(AppReleasePresets.uses_gradle_build(_preset_android))

	func test_false_for_ios_preset() -> void:
		assert_false(AppReleasePresets.uses_gradle_build(_preset_ios))


class TestGetAndroidExportFormat:
	extends _FixtureBacked

	func test_reads_export_format_key() -> void:
		assert_eq(
			AppReleasePresets.get_android_export_format(_preset_android),
			AppReleasePresets.FORMAT_AAB
		)

	func test_returns_apk_for_empty_preset() -> void:
		assert_eq(AppReleasePresets.get_android_export_format({}), AppReleasePresets.FORMAT_APK)


class TestGetFirstPresetForPlatform:
	extends _FixtureBacked

	func test_returns_matching_preset_for_platform() -> void:
		var preset := AppReleasePresets.get_first_preset_for_platform(AppReleaseStrings.platform_ios)
		assert_eq(preset["name"], "iOS")

	func test_filters_by_android_export_format_when_given() -> void:
		var matching := AppReleasePresets.get_first_preset_for_platform(
			AppReleaseStrings.platform_android, AppReleasePresets.FORMAT_AAB
		)
		assert_eq(matching["name"], "Android")

		var not_matching := AppReleasePresets.get_first_preset_for_platform(
			AppReleaseStrings.platform_android, AppReleasePresets.FORMAT_APK
		)
		assert_true(not_matching.is_empty())


class TestPresetsModifiedTime:
	extends _FixtureBacked

	func test_returns_positive_value_when_file_exists() -> void:
		assert_gt(AppReleasePresets.presets_modified_time(), 0)

	func test_returns_zero_when_no_export_presets_cfg() -> void:
		DirAccess.remove_absolute(_real_export_presets_path)
		assert_eq(AppReleasePresets.presets_modified_time(), 0)


class TestPresetNameHint:
	extends _FixtureBacked

	func test_joins_preset_names_with_commas() -> void:
		assert_eq(AppReleasePresets.preset_name_hint(), "iOS,Android")
