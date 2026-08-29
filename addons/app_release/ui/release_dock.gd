@tool
extends TabContainer

const _TargetColumn := preload("target_column.gd")
const _GroupBox := preload("group_box.gd")
const _SetupPanel := preload("setup_panel.gd")

const _TAB_FONT_SIZE_INCREASE := 6

var _config: AppReleaseConfig

var _version_edit: LineEdit
var _build_edit: SpinBox
var _notes_edit: TextEdit
var _status_label: Label
var _open_setup_button: Button
var _edit_config_button: Button
var _stop_button: Button
var _log_tabs: AppReleaseLogTabs
var _columns_box: HBoxContainer
var _release_tab: PanelContainer
var _setup_panel: _SetupPanel

var _columns: Dictionary = {}
var _group_boxes: Dictionary = {}

var _confirm_dialog: ConfirmationDialog
var _runner: AppReleaseBatchRunner
var _fetcher: AppReleaseStoreFetcher
var _store_rows: Dictionary = {}

var _pending_target_ids: PackedStringArray = []

var _fetched_once := false
var _config_modified_time := 0
var _setup_tab_index := 0
var _content_reload_pending := false


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

	_edit_config_button = Button.new()
	_edit_config_button.text = "Edit config"
	_edit_config_button.tooltip_text = "Open release_config.tres in the Inspector."
	_edit_config_button.visible = false
	_edit_config_button.pressed.connect(_on_edit_config_pressed)
	status_row.add_child(_edit_config_button)

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
	_log_tabs = AppReleaseLogTabs.new()
	_log_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.add_child(_log_tabs)

	_confirm_dialog = ConfirmationDialog.new()
	_confirm_dialog.title = AppReleaseStrings.dialog_title
	_confirm_dialog.ok_button_text = AppReleaseStrings.dialog_ok
	_confirm_dialog.confirmed.connect(_on_release_confirmed)
	add_child(_confirm_dialog, false, Node.INTERNAL_MODE_BACK)

	_runner = AppReleaseBatchRunner.new(self)
	_runner.log_appended.connect(_append_log)
	_runner.log_cleared.connect(func() -> void: _log_tabs.clear_all())
	_runner.batch_queued.connect(_on_batch_queued)
	_runner.status_changed.connect(func(text: String) -> void: _status_label.text = text)
	_runner.runs_changed.connect(_update_buttons)

	_fetcher = AppReleaseStoreFetcher.new(self)
	_fetcher.store_status_changed.connect(_set_store_status)
	_fetcher.store_fetched.connect(_on_store_fetched)
	_fetcher.fetch_failed.connect(_on_fetch_failed)


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

	var notes_box := VBoxContainer.new()
	notes_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(notes_box)
	notes_box.add_child(_label(AppReleaseStrings.label_release_notes))
	_notes_edit = TextEdit.new()
	_notes_edit.custom_minimum_size = Vector2(0, 240)
	_notes_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_notes_edit.placeholder_text = AppReleaseStrings.placeholder_notes
	_notes_edit.text_changed.connect(
		func() -> void: _store_setting(AppReleaseStrings.setting_last_notes, _notes_edit.text)
	)
	notes_box.add_child(_notes_edit)

	var side_box := VBoxContainer.new()
	side_box.custom_minimum_size = Vector2(220, 0)
	top.add_child(side_box)

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
	_config = AppReleaseConfig.load_project_config()
	_rebuild_columns()
	_restore_form_state()
	_setup_panel.refresh_with(_config)
	_update_status_for_config()


func _apply_config_content_changed() -> void:
	_content_reload_pending = false
	_rebuild_columns()
	_restore_form_state()
	_setup_panel.refresh_with(_config)
	_update_status_for_config()


func _update_status_for_config() -> void:
	_edit_config_button.visible = _config != null

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


func _on_edit_config_pressed() -> void:
	if _config == null:
		return
	EditorInterface.edit_resource(_config)

func _rebuild_columns() -> void:
	for child in _columns_box.get_children():
		_columns_box.remove_child(child)
		child.queue_free()
	_columns.clear()
	_group_boxes.clear()

	if _config == null:
		return

	var boxes: Array[Control] = []
	for group in _config.release_groups:
		if group == null:
			continue
		var targets := group.enabled_targets()
		if targets.is_empty():
			continue

		var box := _GroupBox.new()
		box.setup(group, targets)
		box.fetch_requested.connect(_on_fetch_store_requested)
		box.release_requested.connect(_on_release_pressed)
		box.stop_requested.connect(_on_stop_target_pressed)
		box.release_group_requested.connect(_on_release_group_pressed.bind(group))
		box.ci_command_copied.connect(_on_ci_command_copied)
		box.pid_copied.connect(_on_pid_copied)
		box.settings_changed.connect(_update_ci_commands)
		for target_id: String in box.columns:
			_columns[target_id] = box.columns[target_id]
		_group_boxes[group] = box
		boxes.append(box)

	if boxes.is_empty():
		return
	_columns_box.add_child(AppReleaseUiLayout.chain(boxes))

	for store_id: String in _store_rows:
		_fill_store_columns(store_id, _store_rows[store_id])

	_update_buttons()


func _restore_form_state() -> void:
	_notes_edit.text = str(_load_setting(AppReleaseStrings.setting_last_notes, ""))

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
	if not target.test_groups.is_empty() and target.supports_tester_groups:
		arguments.append("--groups \"%s\"" % target.test_groups)
	if target.debug_build:
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


func _on_pid_copied(target_label: String) -> void:
	_status_label.text = AppReleaseStrings.status_pid_copied_format % target_label


func _on_ci_command_copied(target_label: String) -> void:
	_status_label.text = AppReleaseStrings.status_ci_copied_format % target_label


func _on_release_pressed(target_id: String) -> void:
	_request_release(PackedStringArray([target_id]))


func _on_release_group_pressed(group: AppReleaseGroup) -> void:
	_request_release(PackedStringArray(
		group.enabled_targets().map(func(target: AppReleaseTarget) -> String: return target.target_id())
	))


func _update_group_release_buttons() -> void:
	for group: AppReleaseGroup in _group_boxes:
		var box: _GroupBox = _group_boxes[group]
		box.set_release_button_disabled(group.runnable_targets().is_empty() or _runner.is_running())


func _request_release(target_ids: PackedStringArray) -> void:
	if target_ids.is_empty() or _runner.is_running() or _config == null:
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
	var build_type := "debug" if target.debug_build else "release"
	var lines: PackedStringArray = [
		"Target:     %s" % target.display_label(),
		"Preset:     %s [%s]" % [target.export_preset, target.platform],
		"Build mode: %s" % AppReleaseTarget.BuildMode.keys()[target.build_mode],
		"Build type: %s" % build_type,
		"Version:    %s (build %d)" % [_version_edit.text.strip_edges(), int(_build_edit.value)],
	]
	if not target.test_groups.is_empty() and target.supports_tester_groups:
		lines.append("Groups:     %s" % target.test_groups)

	if not _notes_edit.text.strip_edges().is_empty():
		lines.append("")
		lines.append(target.release_notes_destination())
	return lines


func _on_release_confirmed() -> void:
	var target_ids := _pending_target_ids
	_pending_target_ids = PackedStringArray()
	if target_ids.is_empty() or _runner.is_running() or _config == null:
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

	if not _runner.start(_config, targets, version, build, notes_file):
		return

	if targets.size() == 1:
		var build_type := "debug" if targets[0].debug_build else "release"
		_status_label.text = AppReleaseStrings.status_running_format % [
			targets[0].display_label(), build_type, _runner.pid_for(targets[0].target_id()),
		]
	else:
		var debug_count := targets.filter(func(t: AppReleaseTarget) -> bool: return t.debug_build).size()
		var build_type := (
			"debug" if debug_count == targets.size()
			else ("release" if debug_count == 0 else "mixed")
		)
		_status_label.text = AppReleaseStrings.status_running_batch_format % [
			targets.size(), build_type,
		]
	_update_buttons()


func quit_warning() -> String:
	return _runner.running_warning() if _runner != null else ""


func abandon_running_work() -> void:
	if _runner != null:
		_runner.kill_all_processes()
	if _fetcher != null:
		_fetcher.stop()


func _on_stop_pressed() -> void:
	_runner.stop()


func _on_stop_target_pressed(target_id: String) -> void:
	_runner.stop_target(target_id)


func _append_log(text: String, target_id: String = "", label: String = "") -> void:
	_log_tabs.append(target_id, label, text)


func _on_batch_queued(target_ids: PackedStringArray) -> void:
	if _config == null:
		return
	for target_id in target_ids:
		var target := _config.find_target(target_id)
		if target != null:
			_log_tabs.set_waiting(
				target_id, target.display_label(), AppReleaseStrings.log_waiting_for_turn
			)


func _update_buttons() -> void:
	var running := _runner.is_running()
	_stop_button.disabled = not running
	var ios_supported := AppReleaseProcess.is_macos()
	for target_id in _columns:
		var column: _TargetColumn = _columns[target_id]
		var this_running: bool = _runner.is_target_running(target_id)
		column.update_buttons(running, this_running, ios_supported)
		column.set_pid(_runner.pid_for(target_id))
		if _log_tabs.has_tab_for(target_id) or this_running:
			_log_tabs.set_running(target_id, this_running, column.target.display_label())

	_update_group_release_buttons()
	_update_ci_commands()


func fetch_all_stores() -> void:
	if _config == null:
		return
	_fetcher.fetch_all(_config.active_store_ids(), _config)


func _on_fetch_store_requested(store_id: String) -> void:
	_fetcher.fetch_one(store_id, _config)


func _on_store_fetched(store_id: String, rows: Array) -> void:
	_store_rows[store_id] = rows
	_fill_store_columns(store_id, rows)


func _on_fetch_failed(store_id: String, error: String) -> void:
	push_error("App Release: release list (%s): %s" % [store_id, error])


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
