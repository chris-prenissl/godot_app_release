@tool
extends GutTest


class TestLastNotes:
	extends GutTest

	var _restore: String = ""
	var _had_cache := false

	func before_each() -> void:
		var path := AppReleaseRunFiles.notes_cache_path()
		_had_cache = FileAccess.file_exists(path)
		if _had_cache:
			var file := FileAccess.open(path, FileAccess.READ)
			_restore = file.get_as_text()
			file.close()
		DirAccess.remove_absolute(path)

	func after_each() -> void:
		if _had_cache:
			AppReleaseRunFiles.write_last_notes(_restore)
		else:
			DirAccess.remove_absolute(AppReleaseRunFiles.notes_cache_path())

	func test_reads_an_empty_string_when_nothing_was_written() -> void:
		assert_eq(AppReleaseRunFiles.read_last_notes(), "")

	func test_round_trips_the_notes() -> void:
		AppReleaseRunFiles.write_last_notes("Fixed the thing.\nAnd the other thing.")
		assert_eq(AppReleaseRunFiles.read_last_notes(), "Fixed the thing.\nAnd the other thing.")

	func test_overwrites_the_previous_notes() -> void:
		AppReleaseRunFiles.write_last_notes("old")
		AppReleaseRunFiles.write_last_notes("new")
		assert_eq(AppReleaseRunFiles.read_last_notes(), "new")

	func test_caches_inside_the_projects_own_work_directory() -> void:
		var path := AppReleaseRunFiles.notes_cache_path()
		assert_true(
			path.begins_with(AppReleaseRunFiles.work_dir()),
			"%s is outside the project's work directory" % path
		)
