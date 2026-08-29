@tool
class_name AppReleaseLogTabs
extends TabContainer

const _RUNNING_PREFIX := "▶ "
const _FOLLOW_SLACK_LINES := 2

var _pages: Dictionary = {}
var _views: Dictionary = {}
var _follow_buttons: Dictionary = {}

var _placeholders: Dictionary = {}
var _following: Dictionary = {}
var _syncing := false


func append(key: String, label: String, text: String) -> void:
	if key.is_empty() or text.is_empty():
		return
	var view := _view_for(key, label)
	_drop_placeholder(key, view)
	_write(key, view, text)


func set_waiting(key: String, label: String, text: String) -> void:
	if key.is_empty():
		return
	var view := _view_for(key, label)
	view.text = text
	_placeholders[key] = true


func set_running(key: String, running: bool, label: String = "") -> void:
	var view: TextEdit = _views.get(key)
	if view == null:
		if not running:
			return
		view = _view_for(key, label)

	if running:
		_drop_placeholder(key, view)

	var index := get_tab_idx_from_control(_pages[key])
	if index < 0:
		return

	var title := str(get_tab_title(index))
	var was_running := title.begins_with(_RUNNING_PREFIX)
	title = title.trim_prefix(_RUNNING_PREFIX)

	set_tab_title(index, _RUNNING_PREFIX + title if running else title)
	if running and not was_running:
		current_tab = index


func clear_all() -> void:
	for key: String in _pages:
		var page: Control = _pages[key]
		remove_child(page)
		page.free()
	_pages.clear()
	_views.clear()
	_follow_buttons.clear()
	_placeholders.clear()
	_following.clear()


func is_waiting(key: String) -> bool:
	return _placeholders.has(key)


func has_tab_for(key: String) -> bool:
	return _views.has(key)


func text_for(key: String) -> String:
	var view: TextEdit = _views.get(key)
	return view.text if view != null else ""


func is_following(key: String) -> bool:
	return bool(_following.get(key, true))


func follow(key: String) -> void:
	if not _views.has(key):
		return
	_scroll_to_end(key)
	_scroll_to_end.call_deferred(key)


func _drop_placeholder(key: String, view: TextEdit) -> void:
	if _placeholders.erase(key):
		view.text = ""


func _view_for(key: String, label: String) -> TextEdit:
	if _views.has(key):
		return _views[key]

	var page := VBoxContainer.new()
	page.name = _title_for(key, label)
	add_child(page)

	var view := TextEdit.new()
	view.editable = false
	view.size_flags_vertical = Control.SIZE_EXPAND_FILL
	view.scroll_fit_content_height = false
	page.add_child(view)

	var button := Button.new()
	button.text = AppReleaseStrings.label_follow_output
	button.tooltip_text = AppReleaseStrings.tooltip_follow_output
	button.visible = false
	button.pressed.connect(follow.bind(key))
	page.add_child(button)

	var scroll_bar := view.get_v_scroll_bar()
	if scroll_bar != null:
		scroll_bar.value_changed.connect(func(_value: float) -> void: _on_scroll_changed(key))

	_pages[key] = page
	_views[key] = view
	_follow_buttons[key] = button
	return view


func _title_for(key: String, label: String) -> String:
	return label if not label.is_empty() else key


func _write(key: String, view: TextEdit, text: String) -> void:
	var was_following := is_following(key)

	_syncing = true
	var last_line := view.get_line_count() - 1
	view.insert_text(text, last_line, view.get_line(last_line).length())
	_syncing = false

	if was_following:
		_scroll_to_end.call_deferred(key)
	else:
		_update_follow_button(key)


func _scroll_to_end(key: String) -> void:
	var view: TextEdit = _views.get(key)
	if view == null:
		return
	_syncing = true
	view.scroll_vertical = view.get_line_count()
	_syncing = false
	_following[key] = true
	_update_follow_button(key)


func _on_scroll_changed(key: String) -> void:
	if _syncing:
		return
	var view: TextEdit = _views.get(key)
	if view == null:
		return
	_following[key] = _is_at_bottom(view)
	_update_follow_button(key)


func _update_follow_button(key: String) -> void:
	var button: Button = _follow_buttons.get(key)
	if button != null:
		button.visible = not is_following(key)


func _is_at_bottom(view: TextEdit) -> bool:
	var scroll_bar := view.get_v_scroll_bar()
	if scroll_bar == null:
		return true
	return scroll_bar.value >= scroll_bar.max_value - scroll_bar.page - _FOLLOW_SLACK_LINES
