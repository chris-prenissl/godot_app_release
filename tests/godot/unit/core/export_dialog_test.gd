extends GutTest


class TestFindExportItem:
	extends GutTest

	func test_finds_the_export_item_by_its_text() -> void:
		var menu := PopupMenu.new()
		add_child_autofree(menu)
		menu.add_item("Project Settings...", 1)
		menu.add_item("Export...", 2)
		assert_eq(AppReleaseExportDialog.find_export_item(menu), 1)

	func test_returns_minus_one_when_there_is_no_export_item() -> void:
		var menu := PopupMenu.new()
		add_child_autofree(menu)
		menu.add_item("Quit", 1)
		assert_eq(AppReleaseExportDialog.find_export_item(menu), -1)

