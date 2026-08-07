@tool
extends VBoxContainer

signal fetch_requested(store_id: String)
signal release_requested(target_id: String)

var target: AppReleaseTarget

var _tree: Tree
var _status: Label
var _fetch_button: Button
var _release_button: Button


func setup(release_target: AppReleaseTarget) -> void:
	target = release_target
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(170, 0)
	clip_contents = true

	var header := HBoxContainer.new()
	add_child(header)

	var title := Label.new()
	title.text = target.display_label()
	title.add_theme_font_size_override("font_size", 15)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = "Preset: %s\nPlatform: %s\nBuild mode: %s\n%s" % [
		target.export_preset,
		target.platform,
		AppReleaseTarget.BuildMode.keys()[target.build_mode],
		target.release_notes_destination(),
	]

	if target.release_notes_are_not_possible():
		title.text += " *"
	header.add_child(title)

	_fetch_button = Button.new()
	_fetch_button.text = AppReleaseStrings.label_fetch
	_fetch_button.tooltip_text = AppReleaseStrings.tooltip_fetch
	_fetch_button.pressed.connect(func() -> void: fetch_requested.emit(target.store_id()))
	header.add_child(_fetch_button)

	_status = Label.new()
	_status.text = AppReleaseStrings.label_press_fetch
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
	add_child(_status)

	_tree = Tree.new()
	_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_tree.columns = AppReleaseStrings.tree_columns.size()
	_tree.column_titles_visible = true
	_tree.hide_root = true
	_tree.select_mode = Tree.SELECT_ROW
	for i in AppReleaseStrings.tree_columns.size():
		_tree.set_column_title(i, AppReleaseStrings.tree_columns[i])
	add_child(_tree)

	_release_button = Button.new()
	_release_button.text = AppReleaseStrings.label_release_to_format % target.display_label()
	_release_button.pressed.connect(func() -> void: release_requested.emit(target.target_id()))
	add_child(_release_button)


func update_buttons(release_running: bool, debug_build: bool, ios_supported: bool) -> void:
	var blocked := release_running
	var reason := ""

	if not blocked and debug_build and not target.allow_debug_build:
		blocked = true
		reason = AppReleaseStrings.tooltip_debug
	if not blocked and target.is_ios() and not ios_supported:
		blocked = true
		reason = AppReleaseStrings.tooltip_ios_needs_macos

	_release_button.disabled = blocked
	_release_button.tooltip_text = reason
	_fetch_button.disabled = release_running


func set_status(text: String) -> void:
	_status.text = text


func fill(rows: Array) -> void:
	var own_rows := rows
	# Google Play returns every track in one response; keep only this one.
	if target.store == AppReleaseTarget.Store.PLAY and not target.play_track.is_empty():
		own_rows = rows.filter(
			func(row: Variant) -> bool: return str(row.get("track", "")) == target.play_track
		)

	_tree.clear()
	var root := _tree.create_item()
	for row in own_rows:
		var item := _tree.create_item(root)
		item.set_text(0, str(row.get("date", "")).left(16).replace("T", " "))

		var version := str(row.get("version", ""))
		var build := str(row.get("build", ""))
		item.set_text(1, "%s (%s)" % [version, build] if not build.is_empty() else version)

		var status := str(row.get("status", ""))
		item.set_text(2, status)
		if status in AppReleaseStrings.status_good:
			item.set_custom_color(2, Color.SEA_GREEN)
		elif status in AppReleaseStrings.status_bad:
			item.set_custom_color(2, Color.INDIAN_RED)

	set_status(AppReleaseStrings.status_releases_format % [
		own_rows.size(), Time.get_time_string_from_system(),
	])
