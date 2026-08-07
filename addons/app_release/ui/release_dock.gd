@tool
extends TabContainer

const _TargetColumn := preload("target_column.gd")
const _SetupPanel := preload("setup_panel.gd")

const _POLL_INTERVAL := 0.5
const _EXIT_FILE_GRACE_TICKS := 4

var _config: AppReleaseConfig

var _version_edit: LineEdit
var _build_edit: SpinBox
var _groups_edit: LineEdit
var _notes_edit: TextEdit
var _notes_hint: Label
var _debug_check: CheckBox
var _status_label: Label
var _stop_button: Button
var _log_view: TextEdit
var _columns_box: VBoxContainer
var _setup_panel: _SetupPanel

var _columns: Dictionary = {}

var _poll_timer: Timer
var _fetch_timer: Timer
var _confirm_dialog: ConfirmationDialog

var _pid := -1
var _log_path := ""
var _log_read_len := 0
var _running_target_id := ""
var _exit_wait_ticks := 0

var _fetch_pid := -1
var _fetch_store := ""
var _fetch_out_path := ""
var _fetch_queue: PackedStringArray = []

var _pending_target_id := ""
var _fetched_once := false
var _config_modified_time := 0


func _init() -> void:
	_build_ui()


func _ready() -> void:
	var filesystem := EditorInterface.get_resource_filesystem()
	if filesystem != null and not filesystem.filesystem_changed.is_connected(_on_filesystem_changed):
		filesystem.filesystem_changed.connect(_on_filesystem_changed)

	_reload_config()


func _on_filesystem_changed() -> void:
	if _config_modified_time == _current_config_modified_time():
		return
	_reload_config()


func _current_config_modified_time() -> int:
	var path := ProjectSettings.globalize_path(AppReleaseStrings.config_resource_path)
	if not FileAccess.file_exists(path):
		return 0
	return int(FileAccess.get_modified_time(path))


func _build_ui() -> void:
	var release_tab := PanelContainer.new()
	release_tab.name = AppReleaseStrings.tab_release
	add_child(release_tab)

	var root := VBoxContainer.new()
	release_tab.add_child(root)

	root.add_child(_build_form())

	var split := VSplitContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(split)

	_columns_box = VBoxContainer.new()
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

	_setup_panel = _SetupPanel.new()
	_setup_panel.name = AppReleaseStrings.tab_setup
	_setup_panel.config_changed.connect(_reload_config)
	add_child(_setup_panel)

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

	_status_label = Label.new()
	_status_label.text = AppReleaseStrings.label_idle
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	side_box.add_child(_status_label)

	return top


func _label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	return label


func _reload_config() -> void:
	_config_modified_time = _current_config_modified_time()
	_config = AppReleaseConfig.load_project_config()
	_rebuild_columns()
	_restore_form_state()
	_setup_panel.refresh()
	if _config == null:
		_status_label.text = AppReleaseStrings.error_no_config
		current_tab = get_tab_count() - 1


func _rebuild_columns() -> void:
	for child in _columns_box.get_children():
		child.queue_free()
	_columns.clear()

	if _config == null:
		return
	var targets := _config.enabled_targets()
	if targets.is_empty():
		_columns_box.add_child(_label(AppReleaseStrings.error_no_targets))
		return

	var built: Array[Control] = []
	for target in targets:
		var column := _TargetColumn.new()
		column.setup(target)
		column.fetch_requested.connect(_on_fetch_store_requested)
		column.release_requested.connect(_on_release_pressed)
		column.ci_command_copied.connect(_on_ci_command_copied)
		_columns[target.target_id()] = column
		built.append(column)

	var chain: Control = built[built.size() - 1]
	for i in range(built.size() - 2, -1, -1):
		var pair := HSplitContainer.new()
		pair.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		pair.size_flags_vertical = Control.SIZE_EXPAND_FILL
		pair.add_child(built[i])
		pair.add_child(chain)
		chain = pair
	chain.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	chain.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns_box.add_child(chain)

	_notes_hint.visible = targets.any(
		func(candidate: AppReleaseTarget) -> bool: return candidate.release_notes_are_not_possible()
	)

	_update_buttons()


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

	return "godot --headless --path . --script %s/%s -- %s && bash %s/%s .release_tools/run.env" % [
		addon_dir,
		AppReleaseStrings.ci_release_script,
		" ".join(arguments),
		addon_dir,
		AppReleaseStrings.release_script_posix,
	]


func _on_ci_command_copied(target_label: String) -> void:
	_status_label.text = AppReleaseStrings.status_ci_copied_format % target_label


func _on_release_pressed(target_id: String) -> void:
	if _pid > 0 or _config == null:
		return
	var target := _config.find_target(target_id)
	if target == null:
		return

	var error := target.get_configuration_error()
	if error.is_empty():
		error = _config.identity_error(target.platform)
	if not error.is_empty():
		_status_label.text = "%s: %s" % [target.display_label(), error]
		return

	_pending_target_id = target_id
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

	_confirm_dialog.dialog_text = AppReleaseStrings.dialog_text_format % "\n".join(lines)
	_confirm_dialog.popup_centered()


func _on_release_confirmed() -> void:
	var target_id := _pending_target_id
	_pending_target_id = ""
	if target_id.is_empty() or _pid > 0 or _config == null:
		return
	var target := _config.find_target(target_id)
	if target == null:
		return

	var version := _version_edit.text.strip_edges()
	var build := int(_build_edit.value)
	if AppReleaseVersionPatcher.patch(target.export_preset, version, build) != OK:
		_status_label.text = "Could not patch %s — see the Output panel." % target.export_preset
		return

	var timestamp := Time.get_datetime_string_from_system().replace(":", "-")
	var notes_file := AppReleaseRunContext.write_notes_file(_notes_edit.text, timestamp)

	if AppReleaseRunContext.write_run_env(
		_config, target, version, build, notes_file, _groups_edit.text.strip_edges(),
		_debug_check.button_pressed
	) != OK:
		_status_label.text = AppReleaseStrings.error_start_failed
		return
	AppReleaseRunContext.write_run_config(_config)

	var logs_root := ProjectSettings.globalize_path(
		AppReleaseStrings.resource_path_prefix
	).path_join(_config.logs_dir)
	DirAccess.make_dir_recursive_absolute(logs_root)
	_log_path = logs_root.path_join(
		AppReleaseStrings.log_file_format % [target.target_id(), timestamp]
	)
	DirAccess.remove_absolute(_log_path + AppReleaseStrings.exit_code_suffix)

	var command := AppReleaseProcess.release_command([
		AppReleaseRunContext.run_env_path(), _log_path,
	])
	_pid = OS.create_process(str(command["executable"]), command["arguments"])
	if _pid <= 0:
		_status_label.text = AppReleaseStrings.error_start_failed
		push_error("App Release: could not start %s." % command["executable"])
		return

	_running_target_id = target_id
	_log_read_len = 0
	_exit_wait_ticks = 0
	_log_view.text = ""
	var build_type := "debug" if _debug_check.button_pressed else "release"
	_status_label.text = AppReleaseStrings.status_running_format % [
		target.display_label(), build_type, _pid,
	]
	_update_buttons()
	_poll_timer.start()


func _on_stop_pressed() -> void:
	if _pid <= 0:
		return
	AppReleaseProcess.kill_process_tree(_pid)
	_read_new_log_output()
	_append_log(AppReleaseStrings.log_stopped_by_user)
	_finish(AppReleaseStrings.status_stopped_format % _running_label())


func _on_poll() -> void:
	_read_new_log_output()
	if _pid <= 0 or OS.is_process_running(_pid):
		return

	var exit_code: Variant = _read_exit_code()
	if exit_code == null:
		_exit_wait_ticks += 1
		if _exit_wait_ticks < _EXIT_FILE_GRACE_TICKS:
			return

	_read_new_log_output()
	if exit_code == null:
		_finish("%s — the release script exited without a status." % _running_label())
		push_error("App Release: no exit status from the release script, see %s" % _log_path)
		return
	if int(exit_code) == 0:
		_finish(AppReleaseStrings.status_success_format % _running_label())
		return
	_finish(AppReleaseStrings.status_failed_format % [int(exit_code), _running_label()])
	push_error("App Release: release failed, see log: %s" % _log_path)


func _read_exit_code() -> Variant:
	if _log_path.is_empty():
		return null

	var path := _log_path + AppReleaseStrings.exit_code_suffix
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


func _finish(status: String) -> void:
	_poll_timer.stop()
	_pid = -1
	_running_target_id = ""
	_status_label.text = status
	_update_buttons()


func _running_label() -> String:
	if _config == null:
		return _running_target_id
	var target := _config.find_target(_running_target_id)
	return target.display_label() if target != null else _running_target_id


func _read_new_log_output() -> void:
	if _log_path.is_empty() or not FileAccess.file_exists(_log_path):
		return
	var file := FileAccess.open(_log_path, FileAccess.READ)
	if file == null:
		return
	var length := file.get_length()
	if length <= _log_read_len:
		file.close()
		return
	file.seek(_log_read_len)
	var new_text := file.get_buffer(length - _log_read_len).get_string_from_utf8()
	file.close()
	_log_read_len = length
	_append_log(new_text)


func _append_log(text: String) -> void:
	_log_view.text += text
	_log_view.scroll_vertical = _log_view.get_line_count()


func _on_debug_toggled(pressed: bool) -> void:
	_store_setting(AppReleaseStrings.setting_last_debug, pressed)
	_update_buttons()


func _update_buttons() -> void:
	var running := _pid > 0
	_stop_button.disabled = not running
	var ios_supported := AppReleaseProcess.is_macos()
	for target_id in _columns:
		var column: _TargetColumn = _columns[target_id]
		column.update_buttons(running, _debug_check.button_pressed, ios_supported)

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
