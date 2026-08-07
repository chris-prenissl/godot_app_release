@tool
extends EditorPlugin

const _ReleaseDock := preload("ui/release_dock.gd")
const _ICON_CANDIDATES: PackedStringArray = ["MoveUp", "ArrowUp", "Godot", "Node"]

var _dock: _ReleaseDock


func _enter_tree() -> void:
	_dock = _ReleaseDock.new()
	_dock.name = AppReleaseStrings.plugin_screen_name
	_dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_dock.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_dock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	EditorInterface.get_editor_main_screen().add_child(_dock)
	_make_visible(false)


func _exit_tree() -> void:
	if _dock != null:
		_dock.queue_free()
		_dock = null


func _has_main_screen() -> bool:
	return true


func _make_visible(visible: bool) -> void:
	if _dock == null:
		return
	_dock.visible = visible
	if visible:
		_dock.fetch_all_stores_once()


func _get_plugin_name() -> String:
	return AppReleaseStrings.plugin_screen_name


func _get_plugin_icon() -> Texture2D:
	var theme := EditorInterface.get_editor_theme()
	for icon_name in _ICON_CANDIDATES:
		if theme.has_icon(icon_name, "EditorIcons"):
			return theme.get_icon(icon_name, "EditorIcons")
	return null
