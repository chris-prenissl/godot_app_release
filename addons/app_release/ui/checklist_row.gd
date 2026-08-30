@tool
extends VBoxContainer

## One row of the Setup checklist: status dot, name, detail, hint and a
## [code]Docs ↗[/code] link.
##
## Renders a single entry as produced by [AppReleaseEnvironment].

const _COLOR_OK := Color(0.36, 0.75, 0.55)
const _COLOR_WARNING := Color(0.90, 0.72, 0.32)
const _COLOR_ERROR := Color(0.85, 0.40, 0.40)

const _COLOR_DOCS_LINK := Color(0.44, 0.68, 0.94)
const _DOCS_COLUMN_WIDTH := 62


func setup(entry: Dictionary) -> void:
	add_theme_constant_override("separation", 0)

	var line := HBoxContainer.new()
	add_child(line)

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
		add_child(hint_label)


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
