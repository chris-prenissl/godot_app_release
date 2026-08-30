@tool
extends VBoxContainer

## The Setup tab: what is missing, and the buttons that fix it.
##
## Renders [method AppReleaseEnvironment.run] as a checklist under two rows of buttons: the
## [b]Required[/b] steps in the order they have to happen, and [b]Optional[/b] ones that a
## release does not depend on. Refresh sits apart, next to the intro, because it changes
## nothing. A step that is already done leaves its button disabled, and nothing here
## overwrites an existing file.

## The config resource was created or changed, so the Release tab must reload it.
signal config_changed

const _ChecklistRow := preload("checklist_row.gd")

const _COLOR_OK := Color(0.36, 0.75, 0.55)
const _COLOR_ERROR := Color(0.85, 0.40, 0.40)

const _ENV_PATH := "res://fastlane/.env"

var _checklist: VBoxContainer
var _message: Label
var _create_config_button: Button
var _scripts_button: Button
var _gitignore_button: Button
var _credentials_button: Button
var _open_config_button: Button
var _agent_skills_button: Button

var _installer: AppReleaseBundleInstaller
var _scaffold_summary := ""


func _init() -> void:
	add_theme_constant_override("separation", 8)
	_build_ui()


func _build_ui() -> void:
	var header := HBoxContainer.new()
	add_child(header)

	var intro := Label.new()
	intro.text = AppReleaseStrings.setup_intro
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(intro)

	var refresh_button := _button(
		AppReleaseStrings.label_setup_refresh, AppReleaseStrings.tooltip_setup_refresh, refresh
	)
	refresh_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(refresh_button)

	add_child(_heading(AppReleaseStrings.setup_required_heading))

	var required := HBoxContainer.new()
	add_child(required)

	_create_config_button = _button(
		AppReleaseStrings.label_setup_create_config,
		AppReleaseStrings.tooltip_setup_create_config,
		_on_create_config_pressed
	)
	required.add_child(_create_config_button)

	_scripts_button = _button(
		AppReleaseStrings.label_setup_scripts,
		AppReleaseStrings.tooltip_setup_scripts,
		_on_scaffold_pressed
	)
	required.add_child(_scripts_button)

	_credentials_button = _button(
		AppReleaseStrings.label_setup_credentials,
		AppReleaseStrings.tooltip_setup_credentials,
		_on_credentials_pressed
	)
	required.add_child(_credentials_button)

	add_child(_heading(AppReleaseStrings.setup_optional_heading))

	var optional := HBoxContainer.new()
	add_child(optional)

	_gitignore_button = _button(
		AppReleaseStrings.label_setup_gitignore,
		AppReleaseStrings.tooltip_setup_gitignore,
		_on_gitignore_pressed
	)
	optional.add_child(_gitignore_button)

	_open_config_button = _button(
		AppReleaseStrings.label_setup_edit_config,
		AppReleaseStrings.tooltip_setup_edit_config,
		_on_open_config_pressed
	)
	optional.add_child(_open_config_button)

	_agent_skills_button = _button(
		AppReleaseStrings.label_setup_agent_skills,
		AppReleaseStrings.tooltip_setup_agent_skills,
		_on_agent_skills_pressed
	)
	optional.add_child(_agent_skills_button)

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

	_installer = AppReleaseBundleInstaller.new(self)
	_installer.finished.connect(_on_install_finished)


static func _button(text: String, tooltip: String, on_pressed: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = tooltip
	button.pressed.connect(on_pressed)
	return button


static func _heading(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.modulate = Color(1, 1, 1, 0.6)
	return label


func refresh() -> void:
	refresh_with(AppReleaseConfig.load_project_config())


func refresh_with(config: AppReleaseConfig) -> void:
	for child in _checklist.get_children():
		child.queue_free()

	_create_config_button.disabled = config != null
	_open_config_button.disabled = config == null
	_scripts_button.disabled = _installer.is_running() or (
		AppReleaseScaffolder.is_fastlane_scaffolded() and AppReleaseShell.are_gems_installed()
	)
	_gitignore_button.disabled = AppReleaseScaffolder.missing_project_gitignore_entries().is_empty()
	_credentials_button.disabled = not FileAccess.file_exists(
		ProjectSettings.globalize_path(_ENV_PATH)
	)
	_agent_skills_button.disabled = AppReleaseScaffolder.are_agent_skills_scaffolded()

	for entry in AppReleaseEnvironment.run(config):
		var row := _ChecklistRow.new()
		row.setup(entry)
		_checklist.add_child(row)


func _on_create_config_pressed() -> void:
	var config := AppReleaseScaffolder.create_default_config()
	if config == null:
		_set_message(AppReleaseStrings.status_create_config_failed_format % (
			AppReleaseStrings.config_resource_path
		), true)
		return
	_set_message(AppReleaseStrings.status_created_config_format % [
		AppReleaseStrings.config_resource_path, config.all_targets().size(),
	])
	refresh()
	config_changed.emit()
	EditorInterface.get_resource_filesystem().scan()


func _on_open_config_pressed() -> void:
	var config := AppReleaseConfig.load_project_config()
	if config == null:
		return
	EditorInterface.edit_resource(config)


func _on_scaffold_pressed() -> void:
	if _installer.is_running():
		return

	var result := AppReleaseScaffolder.scaffold_fastlane()
	var created: PackedStringArray = result["created"]
	var skipped: PackedStringArray = result["skipped"]

	_scaffold_summary = ""
	if not created.is_empty():
		_scaffold_summary += AppReleaseStrings.status_scaffold_created_format % ", ".join(created)
	if not skipped.is_empty():
		_scaffold_summary += AppReleaseStrings.status_scaffold_kept_format % ", ".join(skipped)

	var config := AppReleaseConfig.load_project_config()
	var extra := config.extra_path_entries if config != null else PackedStringArray()
	if not _installer.start(extra):
		_set_message(
			_scaffold_summary + AppReleaseStrings.status_bundle_start_failed, true
		)
		refresh()
		EditorInterface.get_resource_filesystem().scan()
		return

	_scripts_button.disabled = true
	_set_message(_scaffold_summary + AppReleaseStrings.status_installing_gems)
	EditorInterface.get_resource_filesystem().scan()


func _on_install_finished(succeeded: bool) -> void:
	_scripts_button.disabled = false

	if succeeded:
		_set_message(_scaffold_summary + AppReleaseStrings.status_gems_installed)
	else:
		_set_message(
			_scaffold_summary + AppReleaseStrings.status_bundle_failed_format % _installer.log_path,
			true
		)
	refresh()


func _on_gitignore_pressed() -> void:
	var added := AppReleaseScaffolder.append_gitignore()
	if added.is_empty():
		_set_message(AppReleaseStrings.status_gitignore_complete)
	else:
		_set_message(AppReleaseStrings.status_gitignore_added_format % ", ".join(added))
	refresh()


func _on_credentials_pressed() -> void:
	var absolute := ProjectSettings.globalize_path(_ENV_PATH)
	if not FileAccess.file_exists(absolute):
		_set_message(AppReleaseStrings.status_credentials_missing, true)
		refresh()
		return
	OS.shell_open(absolute)
	_set_message(AppReleaseStrings.status_credentials_opened_format % absolute)


func _on_agent_skills_pressed() -> void:
	var result := AppReleaseScaffolder.scaffold_agent_skills()
	var created: PackedStringArray = result["created"]
	var skipped: PackedStringArray = result["skipped"]

	var message := ""
	if not created.is_empty():
		message += AppReleaseStrings.status_agent_skills_created_format % ", ".join(created)
	if not skipped.is_empty():
		if not message.is_empty():
			message += " "
		message += AppReleaseStrings.status_agent_skills_kept_format % ", ".join(skipped)
	_set_message(message)

	refresh()
	EditorInterface.get_resource_filesystem().scan()


func _set_message(text: String, is_error: bool = false) -> void:
	_message.text = text
	_message.add_theme_color_override(
		"font_color", _COLOR_ERROR if is_error else _COLOR_OK
	)
