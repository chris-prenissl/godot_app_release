extends GutTest

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
