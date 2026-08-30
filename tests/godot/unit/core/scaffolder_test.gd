@tool
extends GutTest


class TestMissingGitignoreEntries:
	extends GutTest

	func test_lists_every_entry_for_an_empty_gitignore() -> void:
		var missing := AppReleaseScaffolder.missing_gitignore_entries("")
		assert_eq(missing, AppReleaseScaffolder.GITIGNORE_ENTRIES)

	func test_lists_nothing_when_every_entry_is_present() -> void:
		var text := "\n".join(AppReleaseScaffolder.GITIGNORE_ENTRIES)
		assert_true(AppReleaseScaffolder.missing_gitignore_entries(text).is_empty())

	func test_ignores_surrounding_whitespace_and_unrelated_lines() -> void:
		var lines: PackedStringArray = ["# comment", "*.tmp"]
		for entry in AppReleaseScaffolder.GITIGNORE_ENTRIES:
			lines.append("  %s  " % entry)
		assert_true(AppReleaseScaffolder.missing_gitignore_entries("\n".join(lines)).is_empty())

	func test_reports_only_what_is_absent() -> void:
		var present: PackedStringArray = AppReleaseScaffolder.GITIGNORE_ENTRIES.slice(1)
		var missing := AppReleaseScaffolder.missing_gitignore_entries("\n".join(present))
		assert_eq(missing, PackedStringArray([AppReleaseScaffolder.GITIGNORE_ENTRIES[0]]))

	func test_does_not_match_an_entry_that_is_only_a_substring_of_a_line() -> void:
		var missing := AppReleaseScaffolder.missing_gitignore_entries("not-logs/")
		assert_true("logs/" in missing)


class TestAgentSkillTemplates:
	extends GutTest

	func test_every_template_ships_with_the_addon() -> void:
		for template_name: String in AppReleaseScaffolder.AGENT_SKILL_TEMPLATES:
			var path := "%s/%s/%s" % [
				AppReleaseStrings.addon_dir(), AppReleaseStrings.templates_dir, template_name,
			]
			assert_true(FileAccess.file_exists(path), "missing template %s" % path)

	func test_every_destination_lands_in_the_agents_directory() -> void:
		for destination: String in AppReleaseScaffolder.AGENT_SKILL_TEMPLATES.values():
			assert_true(
				destination.begins_with(".agents/"),
				"%s does not belong to .agents/" % destination
			)

	func test_destinations_are_unique() -> void:
		var destinations: Array = AppReleaseScaffolder.AGENT_SKILL_TEMPLATES.values()
		var seen: PackedStringArray = []
		for destination: String in destinations:
			assert_false(destination in seen, "duplicate destination %s" % destination)
			seen.append(destination)

	func test_does_not_collide_with_the_fastlane_scaffold() -> void:
		var fastlane: Array = (
			AppReleaseScaffolder.FASTLANE_TEMPLATES.values()
			+ AppReleaseScaffolder.ENV_TEMPLATES.values()
			+ AppReleaseScaffolder.BUNDLER_TEMPLATES.values()
		)
		for destination: String in AppReleaseScaffolder.AGENT_SKILL_TEMPLATES.values():
			assert_false(destination in fastlane, "%s is scaffolded twice" % destination)
