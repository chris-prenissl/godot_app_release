@tool
extends VBoxContainer

## The Setup tab: what is missing, and the buttons that fix it.
##
## Renders [method AppReleaseEnvironment.run] as a checklist and offers the three setup
## actions — create [code]release_config.tres[/code], install the fastlane files and run
## [code]bundle install[/code], update [code].gitignore[/code]. Nothing here overwrites an
## existing file.

## The config resource was created or changed, so the Release tab must reload it.
signal config_changed

const _ChecklistRow := preload("checklist_row.gd")

const _COLOR_OK := Color(0.36, 0.75, 0.55)
const _COLOR_ERROR := Color(0.85, 0.40, 0.40)

var _checklist: VBoxContainer
var _message: Label
var _create_config_button: Button
var _open_config_button: Button
var _scripts_button: Button

var _installer: AppReleaseBundleInstaller
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

	_installer = AppReleaseBundleInstaller.new(self)
	_installer.finished.connect(_on_install_finished)


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

	for entry in AppReleaseEnvironment.run(config):
		var row := _ChecklistRow.new()
		row.setup(entry)
		_checklist.add_child(row)


func _on_create_config_pressed() -> void:
	var config := AppReleaseScaffolder.create_default_config()
	if config == null:
		_set_message("Could not write %s — see the Output panel." % (
			AppReleaseStrings.config_resource_path
		), true)
		return
	_set_message("Created %s with %d target(s). Open it and check each target's export preset." % [
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
		_scaffold_summary += "Created %s. " % ", ".join(created)
	if not skipped.is_empty():
		_scaffold_summary += "Kept existing %s. " % ", ".join(skipped)

	var config := AppReleaseConfig.load_project_config()
	var extra := config.extra_path_entries if config != null else PackedStringArray()
	if not _installer.start(extra):
		_set_message(
			_scaffold_summary + "Could not start bundle install — is Ruby installed?", true
		)
		refresh()
		EditorInterface.get_resource_filesystem().scan()
		return

	_scripts_button.disabled = true
	_set_message(
		_scaffold_summary + "Installing Ruby gems (bundle install), this can take a few minutes..."
	)
	EditorInterface.get_resource_filesystem().scan()


func _on_install_finished(succeeded: bool) -> void:
	_scripts_button.disabled = false

	if succeeded:
		_set_message(
			_scaffold_summary
			+ "Ruby gems installed. Next: fill in your store credentials in fastlane/.env."
		)
	else:
		_set_message(
			_scaffold_summary + "bundle install failed — see %s" % _installer.log_path, true
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
