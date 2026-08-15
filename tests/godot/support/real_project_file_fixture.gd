@tool
class_name RealProjectFileFixture
extends GutTest

## Shared GUT base for tests that must swap content into a real `res://` path for the
## duration of one test — e.g. `res://export_presets.cfg` or `res://release_config.tres`,
## both hardcoded on the production side (see the gut-add-unit-test skill's
## "Fixture-Swap Pattern": the source stays hardcoded to the real project path on purpose,
## the test swaps the file instead).
##
## Backs up whatever is already at that path before the test runs and restores it
## afterward, instead of unconditionally deleting — so running this suite can never
## destroy a real `export_presets.cfg`/`release_config.tres` a developer happens to have
## in this project. Subclasses override [method _real_resource_path]; see also
## [FixtureSeededProjectFile] for tests that also want a fixture written up front.

var _real_path: String
var _had_original: bool
var _original_text: String


func _real_resource_path() -> String:
	assert(false, "RealProjectFileFixture: override _real_resource_path().")
	return ""


func before_each() -> void:
	_real_path = ProjectSettings.globalize_path(_real_resource_path())
	_had_original = FileAccess.file_exists(_real_path)
	if _had_original:
		var original := FileAccess.open(_real_path, FileAccess.READ)
		_original_text = original.get_as_text()
		original.close()


func after_each() -> void:
	if _had_original:
		_write(_original_text)
	elif FileAccess.file_exists(_real_path):
		DirAccess.remove_absolute(_real_path)


func _write(text: String) -> void:
	var sink := FileAccess.open(_real_path, FileAccess.WRITE)
	sink.store_string(text)
	sink.close()
