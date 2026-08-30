# Prompt: write GDScript documentation for this repository

House style for `##` doc comments in `addons/app_release/`. These are not ordinary comments:
Godot renders them in the editor Help panel (F1) and as property descriptions in the
Inspector, so they are user-facing.

## Rules

- **`##`, never `#`.** A `#` comment is invisible to everyone but the next reader of the
  source. If something needs saying, say it where users see it.
- **Brief first, detail after a blank `##` line.** The first paragraph is what class lists
  show:

  ```gdscript
  ## One destination: an export preset plus the store it is uploaded to.
  ##
  ## Longer explanation, the trade-offs, the trap someone will hit.
  ```

- **Documentation goes above annotations**, not between the annotation and the `var`:

  ```gdscript
  ## Google Play track. Only meaningful when [member store] is [constant Store.PLAY].
  @export var play_track: String = ""
  ```

- **Use BBCode, not backticks.** `[code]run.env[/code]`, `[b]Pick this first[/b]`,
  `[br]` for a line break, `[codeblock lang=text]…[/codeblock]` for a command.
- **Link instead of repeating**: `[AppReleaseTarget]`, `[member store]`,
  `[method get_configuration_error]`, `[constant Store.PLAY]`, `[signal runs_changed]`,
  `[param target_id]`.
- **`@tutorial(Title): URL`** at the end of a class block adds an "Online Tutorials" link in
  the Help panel. Use it on the config resources and the entry points to point at
  `docs/`.
- **Private members** (`_leading_underscore`) are hidden from the docs. Document them only
  when the logic is genuinely surprising, and keep it to one line.
- **Say why, not what.** `## Returns the store id.` above `store_id()` is noise. `## Store id
  written into run.env and used to key store release lists.` is not.

## What to document

| Thing | Always |
|---|---|
| Class | Yes — brief + detail |
| `@export` | Yes — it becomes the Inspector description |
| Signal | Yes — when it fires, and what the payload means |
| Enum and its values | Yes |
| Public constant | When the name does not fully explain it |
| Public method | When the behaviour is not obvious from the signature. Flag destructive ones (`next_export()` pops) and test seams (`spawn_hook`) |

## Do not

- Restate the type: `## A String holding the lane.`
- Document a getter that returns exactly its field.
- Change any statement while documenting. A doc pass is a doc pass; behaviour changes go in
  their own commit.
