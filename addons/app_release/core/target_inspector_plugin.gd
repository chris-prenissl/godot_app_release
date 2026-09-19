@tool
class_name AppReleaseTargetInspectorPlugin
extends EditorInspectorPlugin

## Adds an [b]Open Export...[/b] button above [member AppReleaseTarget.export_preset] in the
## Inspector, so a missing preset can be added without leaving the target.

func _can_handle(object: Object) -> bool:
	return object is AppReleaseTarget


func _parse_property(
	_object: Object, _type: Variant.Type, name: String, _hint_type: PropertyHint,
	_hint_string: String, _usage_flags: int, _wide: bool
) -> bool:
	if name != "export_preset":
		return false

	var button := Button.new()
	button.text = AppReleaseStrings.label_open_export
	button.tooltip_text = AppReleaseStrings.tooltip_open_export
	button.pressed.connect(_on_open_export_pressed)
	add_custom_control(button)
	return false


func _on_open_export_pressed() -> void:
	if not AppReleaseExportDialog.open():
		push_warning("App Release: %s" % AppReleaseStrings.status_export_menu_missing)
