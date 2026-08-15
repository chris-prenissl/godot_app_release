extends GutTest

class TestName:
	extends GutTest

	func test_setting_name_also_sets_resource_name() -> void:
		var group := AppReleaseGroup.new()
		group.name = "Beta"
		assert_eq(group.resource_name, "Beta")


class TestTargetIds:
	extends GutTest

	func test_defaults_to_empty() -> void:
		var group := AppReleaseGroup.new()
		assert_true(group.target_ids.is_empty())
