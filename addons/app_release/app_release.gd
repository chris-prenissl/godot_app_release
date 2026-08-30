@tool
extends EditorPlugin

## Entry point of the App Release plugin.
##
## Adds the [b]Release[/b] main screen next to 2D/3D/Script, polls
## [code]export_presets.cfg[/code] so the panel and the Inspector notice preset changes, and
## warns before the editor quits while a release is running.
##
## @tutorial(Architecture overview): https://github.com/chris-prenissl/godot_app_release/blob/main/ARCHITECTURE.md
## @tutorial(Ship to TestFlight and the App Store): https://github.com/chris-prenissl/godot_app_release/blob/main/docs/ios-app-store.md
## @tutorial(Ship to Google Play): https://github.com/chris-prenissl/godot_app_release/blob/main/docs/google-play.md
## @tutorial(Ship to Firebase App Distribution): https://github.com/chris-prenissl/godot_app_release/blob/main/docs/firebase-app-distribution.md

const _ReleaseDock := preload("ui/release_dock.gd")
## Editor icons tried in order for the main-screen tab; themes differ between versions.
const _ICON_CANDIDATES: PackedStringArray = ["MoveUp", "ArrowUp", "Godot", "Node"]

## How often [code]export_presets.cfg[/code] is checked for changes, in seconds. Godot
## emits no signal for it.
const _PRESETS_POLL_INTERVAL := 1.0

var _dock: _ReleaseDock
var _presets_timer: Timer
var _presets_modified_time := 0


func _enter_tree() -> void:
	_dock = _ReleaseDock.new()
	_dock.name = AppReleaseStrings.plugin_screen_name
	_dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(_dock)
	_make_visible(false)

	_presets_modified_time = AppReleasePresets.presets_modified_time()
	_presets_timer = Timer.new()
	_presets_timer.wait_time = _PRESETS_POLL_INTERVAL
	_presets_timer.timeout.connect(_on_presets_poll)
	add_child(_presets_timer)
	_presets_timer.start()


func _exit_tree() -> void:
	if _presets_timer != null:
		_presets_timer.queue_free()
		_presets_timer = null
	if _dock != null:
		_dock.abandon_running_work()
		_dock.queue_free()
		_dock = null


func _get_unsaved_status(for_scene: String) -> String:
	if not for_scene.is_empty() or _dock == null:
		return ""
	return _dock.quit_warning()


func _on_presets_poll() -> void:
	var current := AppReleasePresets.presets_modified_time()
	if current == _presets_modified_time:
		return
	_presets_modified_time = current

	_refresh_inspected_presets()
	if _dock != null:
		_dock.on_export_presets_changed()


func _refresh_inspected_presets() -> void:
	var inspector := EditorInterface.get_inspector()
	if inspector == null:
		return

	var edited := inspector.get_edited_object()
	if edited is AppReleaseTarget:
		edited.notify_property_list_changed()
	elif edited is AppReleaseConfig:
		edited.notify_property_list_changed()
		for target in (edited as AppReleaseConfig).all_targets():
			if target != null:
				target.notify_property_list_changed()


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _dock == null:
		return
	_dock.visible = visible
	if visible:
		_dock.on_main_screen_shown()


func _get_plugin_name() -> String:
	return AppReleaseStrings.plugin_screen_name


func _get_plugin_icon() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	for icon_name in _ICON_CANDIDATES:
		if theme.has_icon(icon_name, "EditorIcons"):
			return theme.get_icon(icon_name, "EditorIcons")
	return null
