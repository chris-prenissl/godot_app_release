@tool
class_name FixtureSeededProjectFile
extends RealProjectFileFixture

## [RealProjectFileFixture] variant for tests that also want a fixture written to the real
## path up front (most cases — reading a preset, patching a version). Subclasses override
## [method _real_resource_path] and [method _fixture_text]; `after_each` is inherited
## unchanged and restores whatever was really there before the fixture got written.


func _fixture_text() -> String:
	return ""


func before_each() -> void:
	super.before_each()
	_write(_fixture_text())
