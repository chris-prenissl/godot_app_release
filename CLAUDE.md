# App Release

Godot 4 editor plugin that exports a mobile project and ships it to TestFlight, the App
Store, Firebase App Distribution and Google Play via fastlane. The shipped artifact is
`addons/app_release/`; the repository root is a host project for developing and testing it.

**Read [.agents/README.md](.agents/README.md) before changing anything** — it is the project
map, the layer rules and the traps (the `run.env` contract duplicated across GDScript, bash
and PowerShell; the vendored `addons/gut/`; `##` doc comments instead of `#`).

- Diagrams: [ARCHITECTURE.md](ARCHITECTURE.md)
- Task guides: [.agents/skills/](.agents/skills/)
- User documentation: [README.md](README.md), [docs/](docs/)

Before opening a PR: `tests/run_all.sh` (GUT + RSpec + bats).
