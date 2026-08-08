@tool
extends VBoxContainer

signal config_changed

const _COLOR_OK := Color(0.36, 0.75, 0.55)
const _COLOR_WARNING := Color(0.90, 0.72, 0.32)
const _COLOR_ERROR := Color(0.85, 0.40, 0.40)

const _DOCS_COLUMN_WIDTH := 62
const _COLOR_DOCS_LINK := Color(0.44, 0.68, 0.94)

const _INSTALL_LOG_NAME := "bundle_install.log"
const _POLL_INTERVAL := 0.5

var _checklist: VBoxContainer
var _message: Label
var _create_config_button: Button
var _open_config_button: Button
var _scripts_button: Button

var _install_timer: Timer
var _install_pid := -1
var _install_log_path := ""
var _scaffold_summary := ""


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_build_ui()


func _build_ui() -> void:
	var intro := Label.new()
	intro.text = (
		"Everything the plugin needs, and what is still missing. "
		+ "Nothing here overwrites a file that already exists."
	)
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(intro)

	var actions := HBoxContainer.new()
	add_child(actions)

	_scripts_button = Button.new()
	_scripts_button.text = "Install release scripts"
	_scripts_button.tooltip_text = (
		"Copy Gemfile and fastlane/{Fastfile,Appfile,Pluginfile} into the project, "
		+ "create fastlane/.env with placeholder credentials, then run bundle install."
	)
	_scripts_button.pressed.connect(_on_scaffold_pressed)
	actions.add_child(_scripts_button)

	var gitignore_button := Button.new()
	gitignore_button.text = "Update .gitignore"
	gitignore_button.tooltip_text = "Keep credentials, logs and build artifacts out of git."
	gitignore_button.pressed.connect(_on_gitignore_pressed)
	actions.add_child(gitignore_button)

	_create_config_button = Button.new()
	_create_config_button.text = "Create config"
	_create_config_button.tooltip_text = (
		"Write release_config.tres with one target per store your export presets support."
	)
	_create_config_button.pressed.connect(_on_create_config_pressed)
	actions.add_child(_create_config_button)

	_open_config_button = Button.new()
	_open_config_button.text = "Edit config"
	_open_config_button.tooltip_text = "Open release_config.tres in the Inspector."
	_open_config_button.pressed.connect(_on_open_config_pressed)
	actions.add_child(_open_config_button)

	var refresh_button := Button.new()
	refresh_button.text = "Refresh"
	refresh_button.pressed.connect(refresh)
	actions.add_child(refresh_button)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(scroll)

	_checklist = VBoxContainer.new()
	_checklist.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_checklist)

	_install_timer = Timer.new()
	_install_timer.wait_time = _POLL_INTERVAL
	_install_timer.timeout.connect(_on_install_poll)
	add_child(_install_timer, false, Node.INTERNAL_MODE_BACK)


func refresh() -> void:
	for child in _checklist.get_children():
		child.queue_free()

	var config := AppReleaseConfig.load_project_config()
	_create_config_button.disabled = config != null
	_open_config_button.disabled = config == null
	_scripts_button.disabled = _install_pid > 0 or (
		AppReleaseScaffolder.is_fastlane_scaffolded() and AppReleaseProcess.are_gems_installed()
	)

	for entry in AppReleaseEnvironment.run(config):
		_checklist.add_child(_build_row(entry))


func _build_row(entry: Dictionary) -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 0)

	var line := HBoxContainer.new()
	row.add_child(line)

	var level: int = entry["level"]
	var marker := Label.new()
	var failed_marker := "!" if level == AppReleaseEnvironment.Level.WARNING else "X"
	marker.text = "OK" if entry["ok"] else failed_marker
	marker.custom_minimum_size = Vector2(28, 0)
	marker.add_theme_color_override("font_color", _level_color(level))
	line.add_child(marker)

	var name_label := Label.new()
	name_label.text = str(entry["name"])
	name_label.custom_minimum_size = Vector2(180, 0)
	line.add_child(name_label)

	var detail := Label.new()
	detail.text = str(entry["detail"])
	line.add_child(detail)

	var docs: String = str(entry.get("docs", ""))
	if not docs.is_empty():
		line.add_child(_build_docs_link(docs))

	var hint: String = str(entry["hint"])
	if not hint.is_empty():
		var hint_label := Label.new()
		hint_label.text = "        %s" % hint
		hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		row.add_child(hint_label)

	return row


func _build_docs_link(url: String) -> LinkButton:
	var link := LinkButton.new()
	link.text = AppReleaseStrings.label_docs
	link.tooltip_text = AppReleaseStrings.tooltip_docs_format % url
	link.uri = url
	link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
	link.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	link.custom_minimum_size = Vector2(_DOCS_COLUMN_WIDTH, 0)

	var accent := _COLOR_DOCS_LINK
	var editor_theme := EditorInterface.get_editor_theme()
	if editor_theme != null and editor_theme.has_color("accent_color", "Editor"):
		accent = editor_theme.get_color("accent_color", "Editor")
	link.add_theme_color_override("font_color", accent)
	link.add_theme_color_override("font_focus_color", accent)
	link.add_theme_color_override("font_hover_color", accent.lightened(0.3))
	link.add_theme_color_override("font_pressed_color", accent.darkened(0.2))
	return link


static func _level_color(level: int) -> Color:
	match level:
		AppReleaseEnvironment.Level.OK:
			return _COLOR_OK
		AppReleaseEnvironment.Level.WARNING:
			return _COLOR_WARNING
		_:
			return _COLOR_ERROR


func _on_create_config_pressed() -> void:
	var config := AppReleaseScaffolder.create_default_config()
	if config == null:
		_set_message("Could not write %s — see the Output panel." % (
			AppReleaseStrings.config_resource_path
		), true)
		return
	EditorInterface.get_resource_filesystem().scan()
	_set_message("Created %s with %d target(s). Open it and check each target's export preset." % [
		AppReleaseStrings.config_resource_path, config.targets.size(),
	])
	refresh()
	config_changed.emit()


func _on_open_config_pressed() -> void:
	var config := AppReleaseConfig.load_project_config()
	if config == null:
		return
	EditorInterface.edit_resource(config)


func _on_scaffold_pressed() -> void:
	if _install_pid > 0:
		return

	var result := AppReleaseScaffolder.scaffold_fastlane()
	var created: PackedStringArray = result["created"]
	var skipped: PackedStringArray = result["skipped"]
	EditorInterface.get_resource_filesystem().scan()

	_scaffold_summary = ""
	if not created.is_empty():
		_scaffold_summary += "Created %s. " % ", ".join(created)
	if not skipped.is_empty():
		_scaffold_summary += "Kept existing %s. " % ", ".join(skipped)

	_start_bundle_install()


func _start_bundle_install() -> void:
	var config := AppReleaseConfig.load_project_config()
	var extra := config.extra_path_entries if config != null else PackedStringArray()

	_install_log_path = AppReleaseRunContext.work_dir().path_join(_INSTALL_LOG_NAME)
	var command := AppReleaseProcess.bundle_install_command(_install_log_path, extra)
	_install_pid = OS.create_process(str(command["executable"]), command["arguments"])
	if _install_pid <= 0:
		_set_message(
			_scaffold_summary + "Could not start bundle install — is Ruby installed?", true
		)
		refresh()
		return

	_scripts_button.disabled = true
	_set_message(
		_scaffold_summary + "Installing Ruby gems (bundle install), this can take a few minutes..."
	)
	_install_timer.start()


func _on_install_poll() -> void:
	if _install_pid > 0 and OS.is_process_running(_install_pid):
		return
	_install_timer.stop()
	_install_pid = -1
	_scripts_button.disabled = false

	if AppReleaseProcess.are_gems_installed():
		_set_message(
			_scaffold_summary
			+ "Ruby gems installed. Next: fill in your store credentials in fastlane/.env."
		)
	else:
		_set_message(
			_scaffold_summary + "bundle install failed — see %s" % _install_log_path, true
		)
	refresh()


func _on_gitignore_pressed() -> void:
	var added := AppReleaseScaffolder.append_gitignore()
	if added.is_empty():
		_set_message(".gitignore already covers everything the plugin writes.")
	else:
		_set_message("Added to .gitignore: %s" % ", ".join(added))
	refresh()


func _set_message(text: String, is_error: bool = false) -> void:
	_message.text = text
	_message.add_theme_color_override(
		"font_color", _COLOR_ERROR if is_error else _COLOR_OK
	)
