#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

godot_bin="${GODOT_BIN:-godot}"

echo "=== Godot (GUT) ==="
"$godot_bin" --headless --path . --import
"$godot_bin" --headless --path . -s addons/gut/gut_cmdln.gd -gconfig=.gutconfig.json

echo
echo "=== Ruby (RSpec) ==="
(cd tests/ruby && bundle check >/dev/null 2>&1 || bundle install)
(cd tests/fixtures/ruby_project && bundle check >/dev/null 2>&1 || bundle install)
(cd tests/ruby && bundle exec rspec spec)

echo
echo "=== Shell (bats-core) ==="
bats tests/shell
