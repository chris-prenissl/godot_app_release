# Skill: working in a Godot project

The things that surprise agents in a Godot 4 repository.

## Running Godot without a window

```sh
godot --headless --path .            # open the project, run nothing
godot --headless --path . --import   # (re)import assets — needed after adding files or in CI
godot --headless --path . --script res://path/to/script.gd -- <args>
godot --headless --path . --export-release "<preset name>" <output path>
```

`--path` is the project directory. Everything after a bare `--` reaches the script as user
arguments (`OS.get_cmdline_user_args()`).

The binary is often not called `godot` — on macOS it is
`/Applications/Godot.app/Contents/MacOS/Godot`. Check before scripting it.

## The import step

`.godot/` holds generated import data and is not committed. A fresh checkout, or a newly
added asset, needs `--import` before scripts can resolve `class_name` types and `preload`
paths. A run that fails with *"Nonexistent function … in base 'Nil'"* almost always means the
import pass has not happened.

## Paths

| Prefix | Means |
|---|---|
| `res://` | project root, read-only in an exported game |
| `user://` | per-user writable directory, platform-specific |

Convert with `ProjectSettings.globalize_path("res://x")` before handing a path to a shell
command — bash cannot resolve `res://`.

## Files that matter

| File | Committed | Notes |
|---|---|---|
| `project.godot` | yes | Project settings, enabled plugins |
| `export_presets.cfg` | yes | Export presets, including version and build number. Godot rewrites this file itself — patch it line-wise, never with a naive `ConfigFile` round-trip that reorders it |
| `*.import` | yes | One per asset; they belong in git |
| `.godot/` | no | Generated |
| `addons/` | yes | Plugins, including this one |

## Editor plugins

- Any script that runs in the editor starts with `@tool`, including everything a plugin
  preloads. Missing it makes the class silently unavailable.
- A plugin is enabled through `project.godot`'s `[editor_plugins]` section, not by being
  present on disk.
- `class_name` registers a global type — after adding one, an import pass is needed before
  other scripts can use it.

## GDScript conventions

- `##` is a documentation comment: it appears in the editor's Help panel (F1) and as the
  property description in the Inspector. `#` is an ordinary comment nobody but a reader of
  the source sees.
- Documentation goes **above** annotations: `## text`, then `@export var x`.
- Tabs, not spaces, is the engine's own style; match the surrounding file either way.
- Typed GDScript (`var x: int`, `func f() -> void`) is the norm in this project.

## Testing

If the project uses [GUT](https://github.com/bitwes/Gut):

```sh
godot --headless --path . --import
godot --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json
```

The import pass first, always.
