extends GutTest

class _WithInstance:
	extends GutTest

	var _ci_release_instance

	func before_each() -> void:
		_ci_release_instance = load("res://addons/app_release/scripts/ci_release.gd").new()

	func after_each() -> void:
		if is_instance_valid(_ci_release_instance):
			_ci_release_instance.free()


class TestParseOptions:
	extends _WithInstance

	func test_reads_key_value_pairs() -> void:
		var options: Dictionary = _ci_release_instance._parse_options(
			PackedStringArray(["--target", "t1", "--version", "1.0.0"])
		)
		assert_eq(options, {"target": "t1", "version": "1.0.0"})

	func test_reads_switches_without_a_value() -> void:
		var options: Dictionary = _ci_release_instance._parse_options(
			PackedStringArray(["--target", "t1", "--debug"])
		)
		assert_eq(options, {"target": "t1", "debug": true})

	func test_reads_list_switch() -> void:
		var options: Dictionary = _ci_release_instance._parse_options(PackedStringArray(["--list"]))
		assert_eq(options, {"list": true})

	func test_fails_on_argument_without_leading_dashes() -> void:
		var options: Dictionary = _ci_release_instance._parse_options(
			PackedStringArray(["target", "t1"])
		)
		assert_eq(options, {})

	func test_fails_when_flag_is_missing_its_value() -> void:
		var options: Dictionary = _ci_release_instance._parse_options(
			PackedStringArray(["--target"])
		)
		assert_eq(options, {})

	func test_returns_empty_dict_for_no_arguments() -> void:
		var options: Dictionary = _ci_release_instance._parse_options(PackedStringArray([]))
		assert_eq(options, {})


class TestProjectRelative:
	extends _WithInstance

	func test_strips_res_prefix() -> void:
		var result = _ci_release_instance._project_relative("res://addons/app_release")
		assert_eq(result, "addons/app_release")


class TestAddonProjectPath:
	extends _WithInstance

	func test_returns_addon_dir_relative_to_project_root() -> void:
		var result = _ci_release_instance._addon_project_path()
		assert_eq(result, "addons/app_release")
