# Skill: update the documentation

## The four documents

| File | Audience | Ships to the Asset Store |
|---|---|---|
| `README.md` | someone deciding whether to use the plugin, then setting it up | no |
| `docs/*.md` | someone setting up one store | via the copy below |
| `addons/app_release/README.md` | the same, but inside the installed addon | yes |
| `addons/app_release/docs/*.md` | copy of `docs/` | yes |
| `ARCHITECTURE.md` | contributors | no |
| `.agents/**` | coding agents and contributors | no |

## The sync rule

`docs/` is the source of truth. `addons/app_release/docs/` is a **byte-identical copy**:

```sh
cp docs/*.md addons/app_release/docs/
diff -r docs addons/app_release/docs   # must print nothing
```

Because the guides are copied verbatim, they may only contain external URLs and paths
relative to the *host project* (`fastlane/.env`, `release_config.tres`). Never link from a
guide to `ARCHITECTURE.md`, `tests/`, `media/` or `.agents/` — those do not exist in the
installed addon.

## The two READMEs

`addons/app_release/README.md` is the root README minus what makes no sense inside an
installed addon:

- the `media/` screenshot table and the Asset Store link
- "Running the test suite" and anything about `tests/`
- links to `ARCHITECTURE.md` and `.agents/`
- links to the store guides are rewritten from `docs/…` to the addon-local `docs/…`

Everything else — requirements, install, setup, daily use, CI, troubleshooting — stays the
same in both. When you change one, walk the other.

## In-editor documentation

The `##` doc comments feed Godot's Help panel and the Inspector, so a property added without
one is undocumented for users, not just for readers of the source. `@tutorial(...)` tags on
`AppReleaseConfig`, `AppReleaseTarget`, `AppReleaseGroup`, `app_release.gd` and
`ci_release.gd` link to the guides on GitHub — update them if a guide is renamed, and update
`docs_guide_*` in `constants/release_strings.gd`, which the Setup checklist links to.

## Checklist

- [ ] `docs/` edited
- [ ] `cp docs/*.md addons/app_release/docs/`, `diff -r` clean
- [ ] both READMEs walked
- [ ] `docs_guide_*` and `@tutorial` links still resolve
- [ ] `tests/run_all.sh` still green (docs changes can still break a fixture)
