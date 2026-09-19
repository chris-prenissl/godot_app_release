extends GutTest


class TestSortedBySeverity:
	extends GutTest

	const _Level := AppReleaseEnvironment.Level

	func _entry(item_name: String, level: int) -> Dictionary:
		return {"name": item_name, "level": level}

	func _names(entries: Array[Dictionary]) -> Array:
		return entries.map(func(entry: Dictionary) -> String: return entry["name"])

	func test_errors_come_first_then_warnings_then_passing_checks() -> void:
		var sorted := AppReleaseEnvironment.sorted_by_severity([
			_entry("a", _Level.OK),
			_entry("b", _Level.WARNING),
			_entry("c", _Level.ERROR),
			_entry("d", _Level.OK),
		])
		assert_eq(_names(sorted), ["c", "b", "a", "d"])

	func test_keeps_the_original_order_within_a_level() -> void:
		var sorted := AppReleaseEnvironment.sorted_by_severity([
			_entry("x", _Level.ERROR),
			_entry("y", _Level.ERROR),
			_entry("z", _Level.ERROR),
		])
		assert_eq(_names(sorted), ["x", "y", "z"])
