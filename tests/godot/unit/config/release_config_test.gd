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

	func _group_of(targets: Array[AppReleaseTarget]) -> AppReleaseGroup:
		var group := AppReleaseGroup.new()
		group.targets = targets
		return group


class TestBundleIdentifierFor:
	extends GutTest

	func test_ios_and_android() -> void:
		var config := AppReleaseConfig.new()
		config.ios_bundle_id = "com.example.ios"
		config.android_package_name = "com.example.android"

		assert_eq(config.bundle_identifier_for(AppReleaseStrings.platform_ios), "com.example.ios")
		assert_eq(config.bundle_identifier_for(AppReleaseStrings.platform_android), "com.example.android")

	func test_unknown_platform_returns_empty_string() -> void:
		var config := AppReleaseConfig.new()
		assert_eq(config.bundle_identifier_for("unknown"), "")


class TestIdentityError:
	extends GutTest

	func test_when_ios_bundle_id_not_blank() -> void:
		var config := AppReleaseConfig.new()
		config.ios_bundle_id = "com.example.ios"

		assert_eq(config.identity_error(AppReleaseStrings.platform_ios), "")

	func test_when_android_package_not_blank() -> void:
		var config := AppReleaseConfig.new()
		config.android_package_name = "com.example.android"

		assert_eq(config.identity_error(AppReleaseStrings.platform_android), "")

	func test_ios_error_message() -> void:
		var config := AppReleaseConfig.new()

		assert_eq(
			config.identity_error(AppReleaseStrings.platform_ios),
			"No iOS bundle id set in release_config.tres."
		)

	func test_android_error_message() -> void:
		var config := AppReleaseConfig.new()

		assert_eq(
			config.identity_error(AppReleaseStrings.platform_android),
			"No Android package name set in release_config.tres."
		)

	func test_unknown_platform_does_not_blame_android() -> void:
		var config := AppReleaseConfig.new()
		assert_ne(config.identity_error("unknown"), "")
		assert_ne(
			config.identity_error("unknown"), "No Android package name set in release_config.tres."
		)


class TestAllTargets:
	extends GutTest

	func test_flattens_targets_across_groups_in_order() -> void:
		var target_a := AppReleaseTarget.new()
		var target_b := AppReleaseTarget.new()
		var target_c := AppReleaseTarget.new()

		var group_a := AppReleaseGroup.new()
		group_a.targets = [target_a, target_b]
		var group_b := AppReleaseGroup.new()
		group_b.targets = [target_c]

		var config := AppReleaseConfig.new()
		config.release_groups = [group_a, group_b]

		assert_eq(config.all_targets(), [target_a, target_b, target_c])

	func test_skips_null_groups() -> void:
		var target := AppReleaseTarget.new()
		var group := AppReleaseGroup.new()
		group.targets = [target]

		var config := AppReleaseConfig.new()
		config.release_groups = [null, group]

		assert_eq(config.all_targets(), [target])

	func test_returns_empty_array_for_config_with_no_groups() -> void:
		var config := AppReleaseConfig.new()
		assert_true(config.all_targets().is_empty())


class TestEnabledTargets:
	extends GutTest

	func test_filters_disabled() -> void:
		var enabled_target := AppReleaseTarget.new()
		enabled_target.enabled = true
		var disabled_target := AppReleaseTarget.new()
		disabled_target.enabled = false

		var group := AppReleaseGroup.new()
		group.targets = [enabled_target, disabled_target]

		var config := AppReleaseConfig.new()
		config.release_groups = [group]

		var result := config.enabled_targets()
		assert_eq(result.size(), 1)
		assert_eq(result[0], enabled_target)


class TestFindTarget:
	extends GutTest

	func test_matches_by_target_id() -> void:
		var target := AppReleaseTarget.new()
		target.store = AppReleaseTarget.Store.TESTFLIGHT
		target.export_preset = "iOS"

		var group := AppReleaseGroup.new()
		group.targets = [target]

		var config := AppReleaseConfig.new()
		config.release_groups = [group]

		assert_eq(config.find_target("testflight_ios"), target)

	func test_returns_null_for_unknown_id() -> void:
		var config := AppReleaseConfig.new()
		assert_null(config.find_target("no_such_target"))


class TestActiveStoreIds:
	extends GutTest

	func test_deduplicates() -> void:
		var target_a := AppReleaseTarget.new()
		target_a.store = AppReleaseTarget.Store.TESTFLIGHT
		target_a.enabled = true
		var target_b := AppReleaseTarget.new()
		target_b.store = AppReleaseTarget.Store.TESTFLIGHT
		target_b.enabled = true
		var target_c := AppReleaseTarget.new()
		target_c.store = AppReleaseTarget.Store.PLAY
		target_c.enabled = true

		var group := AppReleaseGroup.new()
		group.targets = [target_a, target_b, target_c]

		var config := AppReleaseConfig.new()
		config.release_groups = [group]

		var store_ids := config.active_store_ids()
		assert_eq(store_ids.size(), 2)
		assert_true(AppReleaseStrings.store_testflight in store_ids)
		assert_true(AppReleaseStrings.store_play in store_ids)


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

		var config := AppReleaseConfig.new()
		config.release_groups = [_group_of([valid_target, invalid_target, disabled_target])]

		var result := config.runnable_targets()
		assert_eq(result.size(), 1)
		assert_eq(result[0], valid_target)


class TestLoadProjectConfig:
	extends RealProjectFileFixture

	func _real_resource_path() -> String:
		return AppReleaseStrings.config_resource_path

	func test_returns_null_when_no_config_resource_exists() -> void:
		assert_null(AppReleaseConfig.load_project_config())

	func test_returns_loaded_config_when_resource_exists() -> void:
		var config := AppReleaseConfig.new()
		config.ios_bundle_id = "com.example.saved"
		ResourceSaver.save(config, AppReleaseStrings.config_resource_path)

		var loaded := AppReleaseConfig.load_project_config()
		assert_not_null(loaded)
		assert_eq(loaded.ios_bundle_id, "com.example.saved")

	func test_cache_mode_replace_returns_the_same_instance_across_calls() -> void:
		var config := AppReleaseConfig.new()
		ResourceSaver.save(config, AppReleaseStrings.config_resource_path)

		var first := AppReleaseConfig.load_project_config(ResourceLoader.CACHE_MODE_REPLACE)
		var second := AppReleaseConfig.load_project_config(ResourceLoader.CACHE_MODE_REPLACE)
		assert_eq(first, second)

	func test_default_cache_mode_ignore_returns_a_fresh_instance_each_call() -> void:
		var config := AppReleaseConfig.new()
		ResourceSaver.save(config, AppReleaseStrings.config_resource_path)

		var first := AppReleaseConfig.load_project_config()
		var second := AppReleaseConfig.load_project_config()
		assert_ne(first, second)
