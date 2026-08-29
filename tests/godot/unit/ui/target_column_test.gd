extends GutTest

const _TargetColumn := preload("res://addons/app_release/ui/target_column.gd")

var _column: Node


func before_each() -> void:
	var target := AppReleaseTarget.new()
	target.export_preset = "PresetA"
	target.label = "Alpha"

	_column = _TargetColumn.new()
	add_child_autofree(_column)
	_column.setup(target)


func test_no_pid_is_shown_while_the_target_is_idle() -> void:
	assert_false(_column.shows_pid())
	assert_eq(_column.pid_text(), "")


func test_a_running_target_shows_its_pid() -> void:
	_column.set_pid(4321)

	assert_true(_column.shows_pid())
	assert_eq(_column.pid_text(), "4321")


func test_the_pid_disappears_once_the_target_stops() -> void:
	_column.set_pid(4321)
	_column.set_pid(-1)

	assert_false(_column.shows_pid())
	assert_eq(_column.pid_text(), "")


func test_the_pid_follows_the_target_from_export_into_upload() -> void:
	_column.set_pid(4321)
	_column.set_pid(9876)

	assert_eq(_column.pid_text(), "9876")


func test_copying_the_pid_reports_the_target_it_belongs_to() -> void:
	_column.set_pid(4321)
	watch_signals(_column)

	_column._on_copy_pid_pressed()

	assert_signal_emitted_with_parameters(_column, "pid_copied", ["Alpha"])


func test_copying_does_nothing_when_no_pid_is_shown() -> void:
	watch_signals(_column)

	_column._on_copy_pid_pressed()

	assert_signal_not_emitted(_column, "pid_copied")
