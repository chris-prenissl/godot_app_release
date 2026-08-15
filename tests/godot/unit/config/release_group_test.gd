@tool
extends GutTest

class _FixtureBacked:
	extends FixtureSeededProjectFile

	const _FIXTURE_PATH := "res://tests/fixtures/ios_basic/export_presets.cfg"

	func _real_resource_path() -> String:
		return AppReleaseStrings.export_presets_path

	func _fixture_text() -> String:
		var fixture := FileAccess.open(_FIXTURE_PATH, FileAccess.READ)
		var text := fixture.get_as_text()
		fixture.close()
		return text

	func _make_valid_ios_target() -> AppReleaseTarget:
		var target := AppReleaseTarget.new()
		target.export_preset = "iOS"
		target.export_options_plist = "tests/fixtures/ios_basic/ExportOptions.plist"
		return target


class TestName:
	extends GutTest

	func test_setting_name_also_sets_resource_name() -> void:
		var group := AppReleaseGroup.new()
		group.name = "Beta"
		assert_eq(group.resource_name, "Beta")


class TestTargets:
	extends GutTest

	func test_defaults_to_empty() -> void:
		var group := AppReleaseGroup.new()
		assert_true(group.targets.is_empty())


class TestEnabledTargets:
	extends GutTest

	func test_filters_disabled() -> void:
		var enabled_target := AppReleaseTarget.new()
		enabled_target.enabled = true
		var disabled_target := AppReleaseTarget.new()
		disabled_target.enabled = false

		var group := AppReleaseGroup.new()
		group.targets = [enabled_target, disabled_target]

		var result := group.enabled_targets()
		assert_eq(result.size(), 1)
		assert_eq(result[0], enabled_target)

	func test_returns_empty_array_for_a_group_with_no_targets() -> void:
		var group := AppReleaseGroup.new()
		assert_true(group.enabled_targets().is_empty())


class TestRunnableTargets:
	extends _FixtureBacked

	func test_includes_only_enabled_and_valid_targets() -> void:
		var valid_target := _make_valid_ios_target()
		valid_target.enabled = true

		var invalid_target := _make_valid_ios_target()
		invalid_target.enabled = true
		invalid_target.fastlane_lane = ""

		var disabled_target := _make_valid_ios_target()
		disabled_target.enabled = false

		var group := AppReleaseGroup.new()
		group.targets = [valid_target, invalid_target, disabled_target]

		var result := group.runnable_targets()
		assert_eq(result.size(), 1)
		assert_eq(result[0], valid_target)

	func test_returns_empty_array_for_a_group_with_no_targets() -> void:
		var group := AppReleaseGroup.new()
		assert_true(group.runnable_targets().is_empty())
