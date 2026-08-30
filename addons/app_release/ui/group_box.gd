@tool
extends PanelContainer

## The panel for one [AppReleaseGroup]: its heading, its target columns, and one button
## that releases the whole group.
##
## Every signal a column emits is forwarded unchanged, so [code]ui/release_dock.gd[/code]
## only has to listen to the groups.

const _TargetColumn := preload("target_column.gd")

## A column's Fetch button was pressed.
signal fetch_requested(store_id: String)
## A column's Release button was pressed.
signal release_requested(target_id: String)
## A column's Stop button was pressed.
signal stop_requested(target_id: String)
## The group's own Release button was pressed — release every runnable target in it.
signal release_group_requested()
## A column's CI command was copied.
signal ci_command_copied(target_label: String)
## A column's pid was copied.
signal pid_copied(target_label: String)
## A column's tester groups or debug checkbox changed.
signal settings_changed()

## Group this panel shows.
var group: AppReleaseGroup
## Target id to its [code]target_column.gd[/code] control.
var columns: Dictionary = {}

var _release_button: Button


func setup(release_group: AppReleaseGroup, targets: Array[AppReleaseTarget]) -> void:
	group = release_group
	add_theme_stylebox_override("panel", _panel_style())
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	add_child(box)

	var group_label := label()

	var title := Label.new()
	title.text = group_label
	title.add_theme_font_size_override("font_size", 17)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var built: Array[Control] = []
	for target in targets:
		var column := _TargetColumn.new()
		column.setup(target)
		var config_error := target.get_configuration_error()
		if not config_error.is_empty():
			column.set_status(AppReleaseStrings.status_target_setup_missing_format % config_error)
		column.fetch_requested.connect(func(store_id: String) -> void: fetch_requested.emit(store_id))
		column.release_requested.connect(
			func(target_id: String) -> void: release_requested.emit(target_id)
		)
		column.stop_requested.connect(
			func(target_id: String) -> void: stop_requested.emit(target_id)
		)
		column.ci_command_copied.connect(
			func(target_label: String) -> void: ci_command_copied.emit(target_label)
		)
		column.pid_copied.connect(
			func(target_label: String) -> void: pid_copied.emit(target_label)
		)
		column.settings_changed.connect(func() -> void: settings_changed.emit())
		columns[target.target_id()] = column
		built.append(column)

	var targets_row := AppReleaseUiLayout.chain(built)
	targets_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(targets_row)

	_release_button = Button.new()
	_release_button.text = AppReleaseStrings.label_release_group_format % group_label
	_release_button.pressed.connect(func() -> void: release_group_requested.emit())
	box.add_child(_release_button)


func label() -> String:
	return group.name if not group.name.is_empty() else str(AppReleaseStrings.label_unnamed_group)


func set_release_button_disabled(value: bool) -> void:
	_release_button.disabled = value


static func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0, 0, 0, 0)
	style.border_width_left = 1
	style.border_width_top = 1
	style.border_width_right = 1
	style.border_width_bottom = 1
	style.border_color = Color(1, 1, 1, 0.25)
	style.content_margin_left = 6
	style.content_margin_top = 6
	style.content_margin_right = 6
	style.content_margin_bottom = 6
	return style
