# Vendored GUT version

This directory is a plain copy of the `addons/gut/` folder from
[bitwes/Gut](https://github.com/bitwes/Gut), pinned at tag **v9.7.1**.

It is **not** a git submodule: GUT hardcodes `res://addons/gut/...` paths
internally (`load("res://addons/gut/...")`) throughout its own source, so it
must live at exactly `res://addons/gut/` to work at all — but the upstream
repository is itself a Godot project with the addon nested one level down
(`<repo>/addons/gut/`), so a straight submodule of the whole repo would land
at `addons/gut/addons/gut/`, which GUT's internal loads can't see. Vendoring
the inner folder directly avoids that mismatch and any symlink portability
issues, matching GUT's own README ("Put the `addons/gut` directory into your
project").

Dev-only: this addon is never enabled in `project.godot`'s `[editor_plugins]`
list and is not part of the distributable plugin (`addons/app_release/`) —
plugin consumers who copy `addons/app_release/` alone never get it.

## Upgrading

1. `git clone --depth 1 --branch <new-tag> https://github.com/bitwes/Gut /tmp/gut-vendor`
2. `rm -rf addons/gut && mkdir addons/gut`
3. `cp -R /tmp/gut-vendor/addons/gut/. addons/gut/`
4. Update the tag noted above and re-run the test suite (`tests/run_all.sh`).
