@tool
class_name AppReleaseExportDialog
extends RefCounted

## Opens Godot's own Export dialog.
##
## The editor has no API for it, so [method open] finds the [b]Project[/b] menu and triggers
## its [b]Export...[/b] item, exactly as if the user had clicked it. Matching is by item
## text, so it also works with a translated editor.

## [code]true[/code] when the menu item was found and triggered.
static func open() -> bool:
	var menu := _find_project_menu()
	if menu == null:
		return false
	var index := find_export_item(menu)
	if index < 0:
		return false
	menu.id_pressed.emit(menu.get_item_id(index))
	return true


## Index of the Export item in [param menu], or [code]-1[/code].
static func find_export_item(menu: PopupMenu) -> int:
	var labels: PackedStringArray = [AppReleaseStrings.editor_export_menu_item]
	var editor_domain := TranslationServer.get_or_add_domain(&"godot.editor")
	if editor_domain != null:
		labels.append(str(editor_domain.translate(AppReleaseStrings.editor_export_menu_item)))
	for index in menu.item_count:
		if menu.get_item_text(index) in labels:
			return index
	return -1


static func _find_project_menu() -> PopupMenu:
	var base := EditorInterface.get_base_control()
	if base == null:
		return null
	for node in base.find_children(AppReleaseStrings.editor_project_menu_name, "PopupMenu", true, false):
		return node as PopupMenu
	return null
