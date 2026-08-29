@tool
class_name AppReleaseLogTabs
extends TabContainer

const _RUNNING_PREFIX := "▶ "
const _GENERAL_KEY := ""
const _FOLLOW_SLACK_LINES := 2

var _views: Dictionary = {}

func append(key: String, label: String, text: String) -> void:
	if text.is_empty():
		return
	_write(_view_for(key, label), text)

func set_running(key: String, running: bool, label: String = "") -> void:
	var view: TextEdit = _views.get(key)
	if view == null:
		if not running:
			return
		view = _view_for(key, label)

	var index := get_tab_idx_from_control(view)
	if index < 0:
		return

	var title := str(get_tab_title(index))
	var was_running := title.begins_with(_RUNNING_PREFIX)
	title = title.trim_prefix(_RUNNING_PREFIX)

	set_tab_title(index, _RUNNING_PREFIX + title if running else title)
	if running and not was_running:
		current_tab = index


func clear_all() -> void:
	for key: String in _views:
		var view: TextEdit = _views[key]
		remove_child(view)
		view.free()
	_views.clear()


func has_tab_for(key: String) -> bool:
	return _views.has(key)


func text_for(key: String) -> String:
	var view: TextEdit = _views.get(key)
	return view.text if view != null else ""


func _view_for(key: String, label: String) -> TextEdit:
	if _views.has(key):
		return _views[key]

	var view := TextEdit.new()
	view.name = _title_for(key, label)
	view.editable = false
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.scroll_fit_content_height = false
	add_child(view)
	_views[key] = view
	return view


func _title_for(key: String, label: String) -> String:
	if key == _GENERAL_KEY:
		return str(AppReleaseStrings.tab_general_log)
	return label if not label.is_empty() else key


func _write(view: TextEdit, text: String) -> void:
	var was_following := _is_at_bottom(view)

	var last_line := view.get_line_count() - 1
	view.insert_text(text, last_line, view.get_line(last_line).length())

	if was_following:
		view.scroll_vertical = view.get_line_count()

func _is_at_bottom(view: TextEdit) -> bool:
	var scroll_bar := view.get_v_scroll_bar()
	if scroll_bar == null:
		return true
	return scroll_bar.value >= scroll_bar.max_value - scroll_bar.page - _FOLLOW_SLACK_LINES
