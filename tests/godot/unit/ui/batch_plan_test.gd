extends GutTest


class TestExportOrder:
	extends GutTest

	func test_pops_targets_in_declared_order() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios", "android", "steam"]))
		assert_eq(plan.next_export("b"), "ios")
		assert_eq(plan.next_export("b"), "android")
		assert_eq(plan.next_export("b"), "steam")

	func test_returns_empty_string_once_drained() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios"]))
		plan.next_export("b")
		assert_eq(plan.next_export("b"), "")

	func test_pending_exports_shrinks_as_targets_are_popped() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios", "android"]))
		plan.next_export("b")
		assert_eq(Array(plan.pending_exports("b")), ["android"])

	func test_open_does_not_alias_the_caller_array() -> void:
		var plan := AppReleaseBatchPlan.new()
		var ids := PackedStringArray(["ios", "android"])
		plan.open("b", ids)
		plan.next_export("b")
		assert_eq(Array(ids), ["ios", "android"], "the caller's array must be left untouched")


class TestUploadTargets:
	extends GutTest

	func test_uploads_every_target_when_nothing_was_dropped() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios", "android"]))
		plan.next_export("b")
		plan.next_export("b")
		assert_eq(Array(plan.upload_targets("b")), ["ios", "android"])

	func test_upload_targets_closes_the_batch() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios"]))
		plan.upload_targets("b")
		assert_false(plan.has_batch("b"))


class TestDropTarget:
	extends GutTest

	func test_dropped_target_neither_exports_nor_uploads() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios", "android", "steam"]))
		plan.drop_target("b", "android")
		assert_eq(Array(plan.pending_exports("b")), ["ios", "steam"])
		assert_eq(Array(plan.upload_targets("b")), ["ios", "steam"])

	func test_target_dropped_after_its_export_started_is_still_excluded_from_uploads() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios", "android"]))
		var exporting := plan.next_export("b")
		plan.drop_target("b", exporting)
		assert_eq(Array(plan.upload_targets("b")), ["android"])

	func test_dropping_the_last_target_leaves_nothing_to_upload() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios"]))
		plan.drop_target("b", "ios")
		assert_eq(Array(plan.upload_targets("b")), [])

	func test_dropping_an_unknown_target_changes_nothing() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios"]))
		plan.drop_target("b", "nope")
		assert_eq(Array(plan.pending_exports("b")), ["ios"])


class TestAbort:
	extends GutTest

	func test_returns_only_the_targets_that_never_started() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios", "android", "steam"]))
		plan.next_export("b")
		assert_eq(Array(plan.abort("b")), ["android", "steam"])

	func test_returns_empty_when_every_export_already_started() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios"]))
		plan.next_export("b")
		assert_eq(Array(plan.abort("b")), [])

	func test_closes_the_batch() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("b", PackedStringArray(["ios"]))
		plan.abort("b")
		assert_false(plan.has_batch("b"))


class TestUnknownBatch:
	extends GutTest

	func test_every_method_is_safe_on_an_unknown_batch_id() -> void:
		var plan := AppReleaseBatchPlan.new()
		assert_false(plan.has_batch("ghost"))
		assert_eq(plan.next_export("ghost"), "")
		assert_eq(Array(plan.pending_exports("ghost")), [])
		assert_eq(Array(plan.upload_targets("ghost")), [])
		assert_eq(Array(plan.abort("ghost")), [])
		plan.drop_target("ghost", "ios")

	func test_batches_do_not_interfere_with_each_other() -> void:
		var plan := AppReleaseBatchPlan.new()
		plan.open("a", PackedStringArray(["ios"]))
		plan.open("b", PackedStringArray(["android"]))
		plan.drop_target("a", "ios")
		assert_eq(Array(plan.pending_exports("b")), ["android"])
