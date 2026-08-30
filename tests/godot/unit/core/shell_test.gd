extends GutTest

class TestRubyMajorVersion:
	extends GutTest

	func test_parses_standard_output() -> void:
		assert_eq(AppReleaseShell.ruby_major_version("ruby 3.2.1p31 (2023-03-30 revision) [x86_64]"), 3)

	func test_parses_double_digit_major() -> void:
		assert_eq(AppReleaseShell.ruby_major_version("ruby 10.0.0"), 10)

	func test_returns_zero_for_garbage() -> void:
		assert_eq(AppReleaseShell.ruby_major_version("not a version string"), 0)

	func test_returns_zero_for_empty_string() -> void:
		assert_eq(AppReleaseShell.ruby_major_version(""), 0)


class TestGodotBinary:
	extends GutTest

	func test_returns_override_path_verbatim_when_given() -> void:
		assert_eq(AppReleaseShell.godot_binary("/custom/path/to/godot"), "/custom/path/to/godot")
