@tool
extends TabContainer

const _TargetColumn := preload("target_column.gd")
const _SetupPanel := preload("setup_panel.gd")

const _POLL_INTERVAL := 0.5
const _TAB_FONT_SIZE_INCREASE := 6
const _EXIT_FILE_GRACE_TICKS := 4

var _config: AppReleaseConfig

var _version_edit: LineEdit
var _build_edit: SpinBox
var _groups_edit: LineEdit
var _notes_edit: TextEdit
var _notes_hint: Label
var _debug_check: CheckBox
var _status_label: Label
var _open_setup_button: Button
var _stop_button: Button
var _log_view: TextEdit
var _columns_box: HBoxContainer
var _release_tab: PanelContainer
var _setup_panel: _SetupPanel

var _columns: Dictionary = {}
var _group_release_buttons: Dictionary = {}

var _poll_timer: Timer
var _fetch_timer: Timer
var _confirm_dialog: ConfirmationDialog
var _runs: Dictionary = {}
var _batch_targets: Dictionary = {}
var _batch_export_queue: Dictionary = {}

var _fetch_pid := -1
var _fetch_store := ""
var _fetch_out_path := ""
var _fetch_queue: PackedStringArray = []
var _store_rows: Dictionary = {}

var _pending_target_ids: PackedStringArray = []

var _fetched_once := false
var _config_modified_time := 0
var _setup_tab_index := 0


func _init() -> void:
	_build_ui()


func _ready() -> void:
	_setup_tab_index = get_tab_idx_from_control(_setup_panel)
	current_tab = get_tab_idx_from_control(_release_tab)
	_setup_tab_bar_size()

	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null and not filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem.filesystem_changed.connect(_on_filesystem_changed)

	_reload_config()


func _setup_tab_bar_size() -> void:
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme == null:
		return

	var base_size := editor_theme.get_font_size("font_size", "TabContainer")
	if base_size <= 0:
		base_size = editor_theme.get_default_font_size()
	if base_size > 0:
		add_theme_font_size_override("font_size", base_size + _TAB_FONT_SIZE_INCREASE)

	tab_alignment = TabBar.ALIGNMENT_CENTER


func _on_filesystem_changed() -> void:
	if _config_modified_time == _current_config_modified_time():
		return
	_reload_config()

func on_export_presets_changed() -> void:
	_reload_config()


func _current_config_modified_time() -> int:
	var path := ProjectSettings.globalize_path(AppReleaseStrings.config_resource_path)
	if not FileAccess.file_exists(path):
		return 0
	return int(FileAccess.get_modified_time(path))


func _build_ui() -> void:
	_setup_panel = _SetupPanel.new()
	_setup_panel.name = AppReleaseStrings.tab_setup
	_setup_panel.config_changed.connect(_reload_config)
	add_child(_setup_panel)

	_release_tab = PanelContainer.new()
	_release_tab.name = AppReleaseStrings.tab_release
	add_child(_release_tab)

	var root := VBoxContainer.new()
	_release_tab.add_child(root)

	root.add_child(_build_form())

	var status_row := HBoxContainer.new()
	root.add_child(status_row)

	_status_label = Label.new()
	_status_label.text = AppReleaseStrings.label_idle
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status_row.add_child(_status_label)

	_open_setup_button = Button.new()
	_open_setup_button.text = AppReleaseStrings.label_open_setup
	_open_setup_button.tooltip_text = AppReleaseStrings.tooltip_open_setup
	_open_setup_button.visible = false
	_open_setup_button.pressed.connect(_show_setup_tab)
	status_row.add_child(_open_setup_button)

	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	_columns_box = HBoxContainer.new()
	_columns_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_child(_columns_box)

	var log_box := VBoxContainer.new()
	log_box.custom_minimum_size = Vector2(0, 300)
	split.add_child(log_box)
	log_box.add_child(_label(AppReleaseStrings.label_log))
	_log_view = TextEdit.new()
	_log_view.editable = false
	_log_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_log_view.scroll_fit_content_height = false
	log_box.add_child(_log_view)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = AppReleaseStrings.dialog_title
	_confirm_dialog.ok_button_text = AppReleaseStrings.dialog_ok
	_confirm_dialog.confirmed.connect(_on_release_confirmed)
	add_child(_confirm_dialog, false, Node.INTERNAL_MODE_BACK)

	_poll_timer = Timer.new()
	_poll_timer.wait_time = _POLL_INTERVAL
	_poll_timer.timeout.connect(_on_poll)
	add_child(_poll_timer, false, Node.INTERNAL_MODE_BACK)

	_fetch_timer = Timer.new()
	_fetch_timer.wait_time = _POLL_INTERVAL
	_fetch_timer.timeout.connect(_on_fetch_store_poll)
	add_child(_fetch_timer, false, Node.INTERNAL_MODE_BACK)


func _build_form() -> Control:
	var top := HBoxContainer.new()

	var grid := GridContainer.new()
	grid.columns = 2
	grid.custom_minimum_size = Vector2(340, 0)
	top.add_child(grid)

	grid.add_child(_label(AppReleaseStrings.label_version_name))
	_version_edit = LineEdit.new()
	_version_edit.placeholder_text = AppReleaseStrings.placeholder_version
	_version_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_version_edit.text_submitted.connect(func(_text: String) -> void: _apply_version_to_presets())
	_version_edit.focus_exited.connect(_apply_version_to_presets)
	_version_edit.text_changed.connect(func(_text: String) -> void: _update_ci_commands())
	grid.add_child(_version_edit)

	grid.add_child(_label(AppReleaseStrings.label_build_number))
	_build_edit = SpinBox.new()
	_build_edit.min_value = 1
	_build_edit.max_value = 2100000000
	_build_edit.step = 1
	_build_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_edit.value_changed.connect(func(_value: float) -> void: _apply_version_to_presets())
	_build_edit.value_changed.connect(func(_value: float) -> void: _update_ci_commands())
	grid.add_child(_build_edit)

	grid.add_child(_label(AppReleaseStrings.label_test_groups))
	_groups_edit = LineEdit.new()
	_groups_edit.placeholder_text = AppReleaseStrings.placeholder_groups
	_groups_edit.tooltip_text = AppReleaseStrings.tooltip_groups
	_groups_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_groups_edit.text_changed.connect(
		func(text: String) -> void:
			_store_setting(AppReleaseStrings.setting_last_groups, text)
			_update_ci_commands()
	)
	grid.add_child(_groups_edit)

	var notes_box := VBoxContainer.new()
	notes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(notes_box)
	notes_box.add_child(_label(AppReleaseStrings.label_release_notes))
	_notes_edit = TextEdit.new()
	_notes_edit.custom_minimum_size = Vector2(0, 84)
	_notes_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_edit.placeholder_text = AppReleaseStrings.placeholder_notes
	_notes_edit.text_changed.connect(
		func() -> void: _store_setting(AppReleaseStrings.setting_last_notes, _notes_edit.text)
	)
	notes_box.add_child(_notes_edit)

	_notes_hint = Label.new()
	_notes_hint.text = AppReleaseStrings.hint_notes_discarded
	_notes_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_notes_hint.add_theme_font_size_override("font_size", 11)
	_notes_hint.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	_notes_hint.visible = false
	notes_box.add_child(_notes_hint)

	var side_box := VBoxContainer.new()
	side_box.custom_minimum_size = Vector2(220, 0)
	top.add_child(side_box)

	_debug_check = CheckBox.new()
	_debug_check.text = AppReleaseStrings.label_debug_build
	_debug_check.tooltip_text = AppReleaseStrings.tooltip_debug
	_debug_check.toggled.connect(_on_debug_toggled)
	side_box.add_child(_debug_check)

	_stop_button = Button.new()
	_stop_button.text = AppReleaseStrings.label_stop
	_stop_button.disabled = true
	_stop_button.pressed.connect(_on_stop_pressed)
	side_box.add_child(_stop_button)

	return top


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _reload_config() -> void:
	_config_modified_time = _current_config_modified_time()
	_config = AppReleaseConfig.load_project_config(ResourceLoader.CACHE_MODE_REPLACE)
	_wire_config_signals()
	_rebuild_columns()
	_restore_form_state()
	_setup_panel.refresh()
	_update_status_for_config()

func _on_config_content_changed() -> void:
	_wire_config_signals()
	_rebuild_columns()
	_restore_form_state()
	_setup_panel.refresh()
	_update_status_for_config()


func _wire_config_signals() -> void:
	if _config == null:
		return
	_connect_once(_config.changed, _on_config_content_changed)
	for group in _config.release_groups:
		if group == null:
			continue
		_connect_once(group.changed, _on_config_content_changed)
		for target in group.targets:
			if target == null:
				continue
			_connect_once(target.changed, _on_config_content_changed)


static func _connect_once(source: Signal, callable: Callable) -> void:
	if not source.is_connected(callable):
		source.connect(callable)


func _update_status_for_config() -> void:
	if _config == null:
		_open_setup_button.visible = true
		_status_label.text = AppReleaseStrings.error_no_config
		return

	var enabled := _config.enabled_targets()
	if enabled.is_empty():
		_open_setup_button.visible = true
		_status_label.text = AppReleaseStrings.error_no_targets
		return

	if _config.runnable_targets().is_empty():
		_open_setup_button.visible = true
		_status_label.text = AppReleaseStrings.error_targets_need_setup_format % ", ".join(
			enabled.map(func(target: AppReleaseTarget) -> String: return target.display_label())
		)
		return

	_open_setup_button.visible = false


func _show_setup_tab() -> void:
	current_tab = _setup_tab_index

func _rebuild_columns() -> void:
	for child in _columns_box.get_children():
		_columns_box.remove_child(child)
		child.queue_free()
	_columns.clear()
	_group_release_buttons.clear()

	if _config == null:
		return

	var group_boxes: Array[Control] = []
	for group in _config.release_groups:
		if group == null:
			continue
		var targets := group.enabled_targets()
		if targets.is_empty():
			continue
		group_boxes.append(_build_group_box(group, targets))

	if group_boxes.is_empty():
		return
	_columns_box.add_child(_chain(group_boxes))

	_notes_hint.visible = _config.enabled_targets().any(
		func(candidate: AppReleaseTarget) -> bool: return candidate.release_notes_are_not_possible()
	)

	for store_id: String in _store_rows:
		_fill_store_columns(store_id, _store_rows[store_id])

	_update_buttons()


func _build_group_box(group: AppReleaseGroup, targets: Array[AppReleaseTarget]) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _group_panel_style())
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var box := VBoxContainer.new()
	panel.add_child(box)

	var group_label: String = (
		group.name if not group.name.is_empty() else str(AppReleaseStrings.label_unnamed_group)
	)

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
		column.fetch_requested.connect(_on_fetch_store_requested)
		column.release_requested.connect(_on_release_pressed)
		column.ci_command_copied.connect(_on_ci_command_copied)
		_columns[target.target_id()] = column
		built.append(column)

	var targets_row := _chain(built)
	targets_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(targets_row)

	var release_group_button := Button.new()
	release_group_button.text = AppReleaseStrings.label_release_group_format % group_label
	release_group_button.pressed.connect(_on_release_group_pressed.bind(group))
	box.add_child(release_group_button)
	_group_release_buttons[group] = release_group_button

	return panel


static func _group_panel_style() -> StyleBoxFlat:
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


## Nests `controls` pairwise into a resizable [HSplitContainer] chain — the same shape for
## a row of target columns within a group, or a row of group boxes across the whole panel.
static func _chain(controls: Array[Control]) -> Control:
	var chain: Control = controls[controls.size() - 1]
	for i in range(controls.size() - 2, -1, -1):
		var pair := HSplitContainer.new()
		pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pair.add_child(controls[i])
		pair.add_child(chain)
		chain = pair
	chain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return chain

func _restore_form_state() -> void:
	_groups_edit.text = str(_load_setting(AppReleaseStrings.setting_last_groups, ""))
	_notes_edit.text = str(_load_setting(AppReleaseStrings.setting_last_notes, ""))
	_debug_check.set_pressed_no_signal(
		bool(_load_setting(AppReleaseStrings.setting_last_debug, false))
	)

	if _config == null:
		return
	var targets := _config.enabled_targets()
	if targets.is_empty():
		return
	var preset := AppReleasePresets.find_preset(targets[0].export_preset)
	var version := AppReleasePresets.version_of(preset)
	_version_edit.text = str(version["version"])
	_build_edit.set_value_no_signal(int(version["build"]))


func _apply_version_to_presets() -> void:
	if _config == null:
		return
	var version := _version_edit.text.strip_edges()
	var build := int(_build_edit.value)
	if not AppReleaseVersionPatcher.is_valid_version(version):
		return

	var patched: PackedStringArray = []
	for target in _config.enabled_targets():
		if target.export_preset in patched:
			continue
		if AppReleaseVersionPatcher.patch(target.export_preset, version, build) == OK:
			patched.append(target.export_preset)
	if not patched.is_empty():
		_status_label.text = AppReleaseStrings.status_presets_updated_format % [version, build]


func _update_ci_commands() -> void:
	if _config == null:
		return
	for target_id: String in _columns:
		var column: _TargetColumn = _columns[target_id]
		column.set_ci_command(_ci_command_for(column.target))

func _ci_command_for(target: AppReleaseTarget) -> String:
	var addon_dir := AppReleaseStrings.addon_dir().trim_prefix(
		AppReleaseStrings.resource_path_prefix
	)
	var arguments: PackedStringArray = [
		"--target %s" % target.target_id(),
		"--version %s" % _version_edit.text.strip_edges(),
		"--build %d" % int(_build_edit.value),
	]
	var groups := _groups_edit.text.strip_edges()
	if not groups.is_empty() and target.supports_tester_groups:
		arguments.append("--groups \"%s\"" % groups)
	if _debug_check.button_pressed and target.allow_debug_build:
		arguments.append("--debug")

	var run_env_relative_path := "%s/%s" % [
		AppReleaseStrings.work_dir_name,
		AppReleaseStrings.run_env_file_format % target.target_id(),
	]
	return "godot --headless --path . --script %s/%s -- %s && bash %s/%s %s" % [
		addon_dir,
		AppReleaseStrings.ci_release_script,
		" ".join(arguments),
		addon_dir,
		AppReleaseStrings.release_script_posix,
		run_env_relative_path,
	]


func _on_ci_command_copied(target_label: String) -> void:
	_status_label.text = AppReleaseStrings.status_ci_copied_format % target_label


func _on_release_pressed(target_id: String) -> void:
	_request_release(PackedStringArray([target_id]))


func _on_release_group_pressed(group: AppReleaseGroup) -> void:
	_request_release(PackedStringArray(
		group.enabled_targets().map(func(target: AppReleaseTarget) -> String: return target.target_id())
	))


func _update_group_release_buttons() -> void:
	for group: AppReleaseGroup in _group_release_buttons:
		var button: Button = _group_release_buttons[group]
		button.disabled = group.runnable_targets().is_empty() or not _runs.is_empty()


func _request_release(target_ids: PackedStringArray) -> void:
	if target_ids.is_empty() or not _runs.is_empty() or _config == null:
		return

	var runnable: Array[AppReleaseTarget] = []
	var skipped: Array[Dictionary] = []
	var ios_supported := AppReleaseProcess.is_macos()

	for target_id in target_ids:
		var target := _config.find_target(target_id)
		if target == null:
			continue
		var error := target.get_configuration_error()
		if error.is_empty():
			error = _config.identity_error(target.platform)
		if error.is_empty() and target.is_ios() and not ios_supported:
			error = AppReleaseStrings.tooltip_ios_needs_macos
		if error.is_empty():
			runnable.append(target)
		else:
			skipped.append({"target": target, "reason": error})

	if runnable.is_empty():
		var reasons: PackedStringArray = []
		for entry in skipped:
			reasons.append("%s: %s" % [entry["target"].display_label(), entry["reason"]])
		_status_label.text = (
			reasons[0] if reasons.size() == 1
			else AppReleaseStrings.status_nothing_to_release_format % "; ".join(reasons)
		)
		return

	_pending_target_ids = PackedStringArray(
		runnable.map(func(target: AppReleaseTarget) -> String: return target.target_id())
	)
	_confirm_dialog.dialog_text = _release_confirm_text(runnable, skipped)
	_confirm_dialog.popup_centered()


func _release_confirm_text(runnable: Array[AppReleaseTarget], skipped: Array[Dictionary]) -> String:
	var blocks: PackedStringArray = []
	for target in runnable:
		blocks.append("\n".join(_target_summary_lines(target)))
	var body := "\n\n".join(blocks)

	if not skipped.is_empty():
		var skip_lines: PackedStringArray = ["Skipped:"]
		for entry in skipped:
			skip_lines.append("  %s — %s" % [entry["target"].display_label(), entry["reason"]])
		body += "\n\n" + "\n".join(skip_lines)

	return AppReleaseStrings.dialog_text_format % body


func _target_summary_lines(target: AppReleaseTarget) -> PackedStringArray:
	var build_type := "debug" if _debug_check.button_pressed else "release"
	var lines: PackedStringArray = [
		"Target:     %s" % target.display_label(),
		"Preset:     %s [%s]" % [target.export_preset, target.platform],
		"Build mode: %s" % AppReleaseTarget.BuildMode.keys()[target.build_mode],
		"Build type: %s" % build_type,
		"Version:    %s (build %d)" % [_version_edit.text.strip_edges(), int(_build_edit.value)],
	]
	var groups := _groups_edit.text.strip_edges()
	if not groups.is_empty() and target.supports_tester_groups:
		lines.append("Groups:     %s" % groups)

	if not _notes_edit.text.strip_edges().is_empty():
		lines.append("")
		lines.append(target.release_notes_destination())
	return lines


func _on_release_confirmed() -> void:
	var target_ids := _pending_target_ids
	_pending_target_ids = PackedStringArray()
	if target_ids.is_empty() or not _runs.is_empty() or _config == null:
		return

	var targets: Array[AppReleaseTarget] = []
	for target_id in target_ids:
		var target := _config.find_target(target_id)
		if target != null:
			targets.append(target)
	if targets.is_empty():
		return

	var version := _version_edit.text.strip_edges()
	var build := int(_build_edit.value)
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var notes_file := AppReleaseRunContext.write_notes_file(_notes_edit.text, timestamp)
	var groups := _groups_edit.text.strip_edges()
	var debug_build := _debug_check.button_pressed

	_start_batch(targets, version, build, notes_file, groups, debug_build)
	if _runs.is_empty():
		return

	var build_type := "debug" if debug_build else "release"
	if targets.size() == 1:
		var run: AppReleaseRun = _runs.values()[0]
		_status_label.text = AppReleaseStrings.status_running_format % [
			targets[0].display_label(), build_type, run.pid,
		]
	else:
		_status_label.text = AppReleaseStrings.status_running_batch_format % [
			targets.size(), build_type,
		]
	_update_buttons()


func _start_batch(
	targets: Array[AppReleaseTarget], version: String, build: int,
	notes_file: String, groups: String, debug_build: bool
) -> void:
	if _config == null or targets.is_empty():
		return

	var patched_presets: PackedStringArray = []
	for target in targets:
		if target.export_preset in patched_presets:
			continue
		if AppReleaseVersionPatcher.patch(target.export_preset, version, build) != OK:
			_status_label.text = "Could not patch %s — see the Output panel." % target.export_preset
			return
		patched_presets.append(target.export_preset)

	for target in targets:
		if AppReleaseRunContext.write_run_env(
			_config, target, version, build, notes_file, groups, debug_build
		) != OK:
			_status_label.text = AppReleaseStrings.error_start_failed
			return
	AppReleaseRunContext.write_run_config(_config)

	_log_view.text = ""

	if targets.size() == 1:
		if _spawn_run(targets[0], "", AppReleaseRun.Phase.SINGLE) != null:
			_update_buttons()
			_poll_timer.start()
		return

	var batch_id := Time.get_datetime_string_from_system().replace(":", "-")
	var ids: PackedStringArray = []
	for target in targets:
		ids.append(target.target_id())
	_batch_targets[batch_id] = ids
	_batch_export_queue[batch_id] = ids.duplicate()

	_spawn_next_batch_export(batch_id)
	_update_buttons()
	_poll_timer.start()

func _spawn_next_batch_export(batch_id: String) -> void:
	if not _batch_export_queue.has(batch_id):
		return

	var queue: PackedStringArray = _batch_export_queue[batch_id]
	if queue.is_empty():
		_batch_export_queue.erase(batch_id)
		_start_batch_uploads(batch_id)
		return

	var target_id: String = queue[0]
	queue.remove_at(0)
	_batch_export_queue[batch_id] = queue

	var target := _config.find_target(target_id) if _config != null else null
	if target == null:
		_spawn_next_batch_export(batch_id)
		return

	if _spawn_run(target, batch_id, AppReleaseRun.Phase.EXPORT) == null:
		_abort_batch(batch_id)


func _start_batch_uploads(batch_id: String) -> void:
	var target_ids: PackedStringArray = _batch_targets.get(batch_id, [])
	_batch_targets.erase(batch_id)
	if _config == null:
		return
	for target_id in target_ids:
		var target := _config.find_target(target_id)
		if target != null:
			_spawn_run(target, batch_id, AppReleaseRun.Phase.UPLOAD)


func _abort_batch(batch_id: String) -> void:
	var remaining: PackedStringArray = _batch_export_queue.get(batch_id, [])
	_batch_export_queue.erase(batch_id)
	_batch_targets.erase(batch_id)
	if not remaining.is_empty():
		_append_log("Release group stopped: %d target(s) not started.\n" % remaining.size())

func _spawn_run(
	target: AppReleaseTarget, batch_id: String, phase: AppReleaseRun.Phase
) -> AppReleaseRun:
	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var run := AppReleaseRun.new()
	run.target_id = target.target_id()
	run.batch_id = batch_id
	run.phase = phase
	run.log_path = _log_path_for(target, phase, timestamp)
	DirAccess.remove_absolute(run.log_path + AppReleaseStrings.exit_code_suffix)

	var arguments: PackedStringArray = [
		AppReleaseRunContext.run_env_path(target.target_id()), run.log_path,
	]
	if phase == AppReleaseRun.Phase.EXPORT:
		arguments.append("export")
	elif phase == AppReleaseRun.Phase.UPLOAD:
		arguments.append("upload")

	var command := AppReleaseProcess.release_command(arguments)
	run.pid = OS.create_process(str(command["executable"]), command["arguments"])
	if run.pid <= 0:
		_status_label.text = AppReleaseStrings.error_start_failed
		push_error("App Release: could not start %s." % command["executable"])
		return null

	_runs[run.target_id] = run
	return run


func _log_path_for(target: AppReleaseTarget, phase: AppReleaseRun.Phase, timestamp: String) -> String:
	var logs_root := ProjectSettings.globalize_path(
		AppReleaseStrings.resource_path_prefix
	).path_join(_config.logs_dir)
	DirAccess.make_dir_recursive_absolute(logs_root)
	if phase == AppReleaseRun.Phase.SINGLE:
		return logs_root.path_join(
			AppReleaseStrings.log_file_format % [target.target_id(), timestamp]
		)
	var phase_name := "export" if phase == AppReleaseRun.Phase.EXPORT else "upload"
	return logs_root.path_join(
		AppReleaseStrings.log_file_phase_format % [target.target_id(), phase_name, timestamp]
	)


func _on_stop_pressed() -> void:
	for run: AppReleaseRun in _runs.values().duplicate():
		AppReleaseProcess.kill_process_tree(run.pid)
		_read_new_log_output(run)
		_append_log(AppReleaseStrings.log_stopped_by_user, _log_label_for(run))
		_finish_run(run, AppReleaseStrings.status_stopped_format % _running_label(run), false)
	_poll_timer.stop()


func _on_poll() -> void:
	for run: AppReleaseRun in _runs.values().duplicate():
		_poll_run(run)
	if _runs.is_empty():
		_poll_timer.stop()


func _poll_run(run: AppReleaseRun) -> void:
	_read_new_log_output(run)
	if run.pid <= 0 or OS.is_process_running(run.pid):
		return

	var exit_code: Variant = _read_exit_code(run)
	if exit_code == null:
		run.exit_wait_ticks += 1
		if run.exit_wait_ticks < _EXIT_FILE_GRACE_TICKS:
			return

	_read_new_log_output(run)
	if exit_code == null:
		_finish_run(
			run, "%s — the release script exited without a status." % _running_label(run), false
		)
		push_error("App Release: no exit status from the release script, see %s" % run.log_path)
		return
	if int(exit_code) == 0:
		_finish_run(run, AppReleaseStrings.status_success_format % _running_label(run), true)
		return
	_finish_run(
		run, AppReleaseStrings.status_failed_format % [int(exit_code), _running_label(run)], false
	)
	push_error("App Release: release failed, see log: %s" % run.log_path)


func _read_exit_code(run: AppReleaseRun) -> Variant:
	if run.log_path.is_empty():
		return null

	var path := run.log_path + AppReleaseStrings.exit_code_suffix
	if not FileAccess.file_exists(path):
		return null
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var text := file.get_as_text().strip_edges()
	file.close()
	if not text.is_valid_int():
		return null
	return int(text)


func _finish_run(run: AppReleaseRun, status: String, succeeded: bool) -> void:
	_runs.erase(run.target_id)
	_status_label.text = status
	_update_buttons()

	if run.phase != AppReleaseRun.Phase.EXPORT:
		return
	if succeeded:
		_spawn_next_batch_export(run.batch_id)
	else:
		_abort_batch(run.batch_id)


func _running_label(run: AppReleaseRun) -> String:
	if _config == null:
		return run.target_id
	var target := _config.find_target(run.target_id)
	return target.display_label() if target != null else run.target_id

func _log_label_for(run: AppReleaseRun) -> String:
	return _running_label(run) if _runs.size() > 1 else ""


func _read_new_log_output(run: AppReleaseRun) -> void:
	if run.log_path.is_empty() or not FileAccess.file_exists(run.log_path):
		return
	var file := FileAccess.open(run.log_path, FileAccess.READ)
	if file == null:
		return
	var length := file.get_length()
	if length <= run.log_read_len:
		file.close()
		return
	file.seek(run.log_read_len)
	var new_text := file.get_buffer(length - run.log_read_len).get_string_from_utf8()
	file.close()
	run.log_read_len = length
	_append_log(new_text, _log_label_for(run))


func _append_log(text: String, label: String = "") -> void:
	if not label.is_empty():
		text = "[%s] %s" % [label, text]
	_log_view.text += text
	_log_view.scroll_vertical = _log_view.get_line_count()


func _on_debug_toggled(pressed: bool) -> void:
	_store_setting(AppReleaseStrings.setting_last_debug, pressed)
	_update_buttons()


func _update_buttons() -> void:
	var running := not _runs.is_empty()
	_stop_button.disabled = not running
	var ios_supported := AppReleaseProcess.is_macos()
	for target_id in _columns:
		var column: _TargetColumn = _columns[target_id]
		column.update_buttons(running, _debug_check.button_pressed, ios_supported)

	_update_group_release_buttons()
	_update_ci_commands()


func fetch_all_stores() -> void:
	if _config == null:
		return
	_fetch_queue = _config.active_store_ids()
	if _fetch_pid <= 0 and not _fetch_queue.is_empty():
		_start_fetch_store(_pop_fetch_queue())


func _on_fetch_store_requested(store_id: String) -> void:
	_start_fetch_store(store_id)


func _start_fetch_store(store_id: String) -> void:
	if store_id.is_empty() or _config == null:
		return
	if _fetch_pid > 0:
		if OS.is_process_running(_fetch_pid):
			AppReleaseProcess.kill_process_tree(_fetch_pid)
		_fetch_pid = -1
		_fetch_timer.stop()

	AppReleaseRunContext.write_run_config(_config)
	_fetch_out_path = AppReleaseRunContext.releases_path(store_id)
	var stderr_path := _fetch_out_path + AppReleaseStrings.stderr_suffix
	DirAccess.remove_absolute(_fetch_out_path)
	DirAccess.remove_absolute(stderr_path)
	_fetch_store = store_id

	var command := AppReleaseProcess.fetch_command(
		store_id, _fetch_out_path, stderr_path, _config.extra_path_entries
	)
	_fetch_pid = OS.create_process(str(command["executable"]), command["arguments"])
	if _fetch_pid <= 0:
		_set_store_status(store_id, AppReleaseStrings.status_error_format % "cannot start ruby")
		return
	_set_store_status(store_id, AppReleaseStrings.status_fetching)
	_fetch_timer.start()


func _on_fetch_store_poll() -> void:
	if _fetch_pid > 0 and OS.is_process_running(_fetch_pid):
		return
	_fetch_timer.stop()
	_fetch_pid = -1

	var rows: Array = []
	var error := ""
	var file := FileAccess.open(_fetch_out_path, FileAccess.READ)
	if file == null:
		error = "list_releases.rb wrote no output: %s" % _read_fetch_store_stderr()
	else:
		var text := file.get_as_text()
		file.close()
		var data: Variant = JSON.parse_string(text)
		if data == null or not data is Dictionary:
			error = "invalid JSON from list_releases.rb: %s" % _read_fetch_store_stderr()
		elif data.has("error"):
			error = str(data["error"])
		else:
			rows = data.get("releases", [])

	if error.is_empty():
		_store_rows[_fetch_store] = rows
		_fill_store_columns(_fetch_store, rows)
	else:
		_set_store_status(_fetch_store, AppReleaseStrings.status_error_format % error)
		_append_log(AppReleaseStrings.log_fetch_failed_format % [_fetch_store, error])
		push_error("App Release: release list (%s): %s" % [_fetch_store, error])

	if not _fetch_queue.is_empty():
		_start_fetch_store(_pop_fetch_queue())


func _pop_fetch_queue() -> String:
	if _fetch_queue.is_empty():
		return ""
	var next := _fetch_queue[0]
	_fetch_queue.remove_at(0)
	return next


func _read_fetch_store_stderr() -> String:
	var file := FileAccess.open(_fetch_out_path + AppReleaseStrings.stderr_suffix, FileAccess.READ)
	if file == null:
		return AppReleaseStrings.error_no_stderr
	var text := file.get_as_text().strip_edges()
	file.close()
	if text.is_empty():
		return AppReleaseStrings.error_empty_stderr

	var meaningful: PackedStringArray = []
	for raw_line in text.split("\n", false):
		var line := raw_line.strip_edges()
		if line.is_empty() or line.begins_with("from ") or line.begins_with("/"):
			continue
		meaningful.append(line)
		if meaningful.size() >= 4:
			break
	var summary := "\n".join(meaningful) if not meaningful.is_empty() else text
	return summary.left(600)


func _set_store_status(store_id: String, text: String) -> void:
	for target_id in _columns:
		var column: _TargetColumn = _columns[target_id]
		if column.target.store_id() == store_id:
			column.set_status(text)


func _fill_store_columns(store_id: String, rows: Array) -> void:
	for target_id in _columns:
		var column: _TargetColumn = _columns[target_id]
		if column.target.store_id() == store_id:
			column.fill(rows)


func _store_setting(key: String, value: Variant) -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings != null:
		settings.set_setting(key, value)


func _load_setting(key: String, fallback: Variant) -> Variant:
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(key):
		return fallback
	return settings.get_setting(key)

func on_main_screen_shown() -> void:
	_reload_config()

	if _fetched_once:
		return
	_fetched_once = true
	fetch_all_stores()
