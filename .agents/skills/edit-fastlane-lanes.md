# Skill: edit the fastlane lanes

## Which Fastfile is real

There are two, and they are not the same file:

| Path | Role |
|---|---|
| `addons/app_release/templates/Fastfile` | **Seed.** Copied once into a project that presses "Install release scripts". |
| `<host project>/fastlane/Fastfile` | **Live.** What actually runs. Owned by the project, never overwritten by a plugin update. |

So: fixing a bug for existing users means editing *their* copy — a plugin release can only
change what new projects get. Say so in the release notes when a lane changes.

`AppReleaseScaffolder.scaffold_fastlane()` skips every destination that already exists and
reports it as *skipped*; there is no overwrite path, deliberately.

## How a lane is invoked

`scripts/release.sh` runs:

```sh
bundle exec fastlane "$PLATFORM" "$LANE"
```

`PLATFORM` is `ios` or `android`, `LANE` is `AppReleaseTarget.fastlane_lane`. So a lane must
live in the matching `platform :ios do` / `platform :android do` block and be named exactly
as the target's lane.

## What a lane gets

Not arguments — environment variables, exported by `release.sh` and read by the helpers at
the top of the Fastfile:

| Helper | Reads | Notes |
|---|---|---|
| `artifact` | `IPA_PATH` / `APK_PATH` / `AAB_PATH`, `ARTIFACT_PATH_ABS` | absolute path of the built file |
| `release_notes` | `RELEASE_NOTES_FILE` | already staged by `stage_release_notes()` |
| `tester_groups` | `RELEASE_GROUPS` | comma-separated aliases, may be empty |
| `skip_build_processing_wait?` | `IOS_SKIP_BUILD_PROCESSING_WAIT` | `"1"` / `"0"` |
| `connect_api_key` | `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_PATH` | App Store Connect API key |

Store identity (`APP_IDENTIFIER`, `ANDROID_PACKAGE_NAME`, `APPLE_TEAM_ID`, `PLAY_TRACK`) is
in the environment too. Credentials come from `fastlane/.env` locally, or from plain
environment variables on CI — dotenv ignores a missing file.

## Deliberate design decisions — do not "fix" these

- The **App Store** lane uploads with `skip_metadata: true`. Pushing metadata would
  overwrite the whole listing (description, keywords, screenshots) with whatever is in the
  local `fastlane/metadata`. "What's New" stays something you write in App Store Connect.
- A **Google Play production** upload is created as a draft, not rolled out.

## Testing lanes

`tests/ruby/spec/fastfile_helpers_spec.rb` covers the helper functions without contacting a
store. Anything beyond that needs a real upload, so keep the lanes thin and put logic in
helpers.
