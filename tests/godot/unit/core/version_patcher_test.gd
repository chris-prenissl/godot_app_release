extends GutTest

const _FIXTURE_PATH := "res://tests/fixtures/ios_basic/export_presets.cfg"


class _FixtureBacked:
	extends FixtureSeededProjectFile

	func _real_resource_path() -> String:
		return AppReleaseStrings.export_presets_path

	func _fixture_text() -> String:
		var fixture := FileAccess.open(_FIXTURE_PATH, FileAccess.READ)
		var text := fixture.get_as_text()
		fixture.close()
		return text

	func _read_real_export_presets() -> String:
		var file := FileAccess.open(_real_path, FileAccess.READ)
		var text := file.get_as_text()
		file.close()
		return text


class TestIsValidVersion:
	extends GutTest

	func test_accepts_semver() -> void:
		assert_true(AppReleaseVersionPatcher.is_valid_version("1.2.3"))

	func test_accepts_letters_underscore_plus_and_dash() -> void:
		assert_true(AppReleaseVersionPatcher.is_valid_version("1.0.0-beta+build_1"))

	func test_rejects_empty_string() -> void:
		assert_false(AppReleaseVersionPatcher.is_valid_version(""))

	func test_rejects_spaces() -> void:
		assert_false(AppReleaseVersionPatcher.is_valid_version("1.0 0"))

	func test_rejects_slashes() -> void:
		assert_false(AppReleaseVersionPatcher.is_valid_version("1.0/0"))


class TestPatchText:
	extends GutTest

	const _SECTION := "preset.0.options"

	func test_rewrites_quoted_version_and_build_keys() -> void:
		var text := "[preset.0.options]\nversion/name=\"1.0.0\"\nversion/code=1\n"
		var patched := AppReleaseVersionPatcher._patch_text(text, _SECTION, "2.0.0", 5)
		assert_true(patched.contains("version/name=\"2.0.0\""))
		assert_true(patched.contains("version/code=5"))
		assert_false(patched.contains("version/code=\"5\""), "version/code stays unquoted")

	func test_rewrites_quoted_application_version_key() -> void:
		var text := "[preset.0.options]\napplication/short_version=\"1.0.0\"\napplication/version=\"1\"\n"
		var patched := AppReleaseVersionPatcher._patch_text(text, _SECTION, "2.0.0", 5)
		assert_true(patched.contains("application/short_version=\"2.0.0\""))
		assert_true(patched.contains("application/version=\"5\""), "application/version stays quoted")

	func test_only_touches_matching_section() -> void:
		var text := (
			"[preset.0.options]\nversion/name=\"1.0.0\"\n"
			+ "[preset.1.options]\nversion/name=\"1.0.0\"\n"
		)
		var patched := AppReleaseVersionPatcher._patch_text(text, _SECTION, "2.0.0", 5)
		var lines := patched.split("\n")
		assert_eq(lines[1], "version/name=\"2.0.0\"")
		assert_eq(lines[3], "version/name=\"1.0.0\"")

	func test_returns_text_unchanged_when_section_not_found() -> void:
		var text := "[preset.1.options]\nversion/name=\"1.0.0\"\n"
		var patched := AppReleaseVersionPatcher._patch_text(text, _SECTION, "2.0.0", 5)
		assert_eq(patched, text)

	func test_leaves_unrelated_keys_in_section_untouched() -> void:
		var text := "[preset.0.options]\napplication/bundle_identifier=\"com.example.app\"\nversion/name=\"1.0.0\"\n"
		var patched := AppReleaseVersionPatcher._patch_text(text, _SECTION, "2.0.0", 5)
		assert_true(patched.contains("application/bundle_identifier=\"com.example.app\""))


class TestPatch:
	extends _FixtureBacked

	func test_rewrites_version_and_build_in_matching_options_section() -> void:
		var result := AppReleaseVersionPatcher.patch("iOS", "2.0.0", 5)
		assert_eq(result, OK)

		var text := _read_real_export_presets()
		assert_true(text.contains("application/short_version=\"2.0.0\""))
		assert_true(text.contains("application/version=\"5\""))

	func test_leaves_other_presets_untouched() -> void:
		AppReleaseVersionPatcher.patch("iOS", "2.0.0", 5)

		var text := _read_real_export_presets()
		assert_true(text.contains("version/name=\"2.5.0\""))
		assert_true(text.contains("version/code=7"))

	func test_is_a_no_op_when_version_and_build_already_match() -> void:
		var before := _read_real_export_presets()
		var result := AppReleaseVersionPatcher.patch("iOS", "1.0.0", 1)
		assert_eq(result, OK)
		assert_eq(_read_real_export_presets(), before)

	func test_returns_err_invalid_parameter_for_bad_version() -> void:
		var result := AppReleaseVersionPatcher.patch("iOS", "1.0 0", 5)
		assert_eq(result, ERR_INVALID_PARAMETER)
		assert_push_error("invalid version")

	func test_returns_err_invalid_parameter_for_non_positive_build() -> void:
		var result := AppReleaseVersionPatcher.patch("iOS", "1.0.0", 0)
		assert_eq(result, ERR_INVALID_PARAMETER)
		assert_push_error("build number must be a positive integer")

	func test_returns_err_invalid_parameter_for_blank_preset_name() -> void:
		var result := AppReleaseVersionPatcher.patch("", "1.0.0", 1)
		assert_eq(result, ERR_INVALID_PARAMETER)
		assert_push_error("no preset name given")

	func test_returns_err_does_not_exist_for_unknown_preset() -> void:
		var result := AppReleaseVersionPatcher.patch("no such preset", "1.0.0", 1)
		assert_eq(result, ERR_DOES_NOT_EXIST)
		assert_push_error("is not in export_presets.cfg")
