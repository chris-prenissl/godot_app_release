# Shipping to TestFlight and the App Store

Everything you need on the Apple side, once. After this, releasing is one button in the
Release tab.

**Requires macOS with Xcode.** Apple's toolchain does not run anywhere else, so iOS targets
are macOS-only — Android targets are not affected.

---

## Get started in 8 steps

1. **Join the Apple Developer Program** — 99 USD/year.
   [developer.apple.com/programs](https://developer.apple.com/programs/). A free account can
   build to your own device but cannot upload to TestFlight or the App Store.

2. **Pick a bundle identifier** and register it. Reverse-DNS, e.g. `com.acme.mygame`. It is
   permanent: an app's bundle id can never be changed after the first upload.
   [Register an App ID](https://developer.apple.com/account/resources/identifiers/list).

3. **Create the app record** in App Store Connect — *My Apps → + → New App*. Pick the bundle
   id from step 2. Without this record an upload is rejected with "no suitable application
   record was found". [App Store Connect](https://appstoreconnect.apple.com/).

4. **Create an App Store Connect API key** — *Users and Access → Integrations → App Store
   Connect API → +*. Give it the **App Manager** role.

   You get three things, and the `.p8` file **can only be downloaded once**:

   | Value | Where it is shown |
   |---|---|
   | Key ID | in the key list, e.g. `ABC123DEFG` |
   | Issuer ID | above the key list, a UUID |
   | `AuthKey_ABC123DEFG.p8` | the one-time download |

   Store the `.p8` outside your repository — `~/keys/` is fine. It is a credential for your
   whole team.
   [Creating API keys](https://developer.apple.com/documentation/appstoreconnectapi/creating-api-keys-for-app-store-connect-api).

5. **Fill in `fastlane/.env`** (created for you by *Install release scripts* in the Setup
   tab, and gitignored):

   ```sh
   ASC_KEY_ID=ABC123DEFG
   ASC_ISSUER_ID=00000000-0000-0000-0000-000000000000
   ASC_KEY_PATH=/Users/you/keys/AuthKey_ABC123DEFG.p8
   ```

   The same key powers the **Fetch** button on the TestFlight and App Store columns.

6. **Set your identity in `release_config.tres`** — *App identity*:
   `ios_bundle_id` and `apple_team_id` (the 10-character team id from
   [Membership details](https://developer.apple.com/account)). Both are usually seeded from
   your export preset already.

7. **Set up signing in Xcode.** The plugin does not sign anything — `xcodebuild` does, using
   the certificates in your keychain and the provisioning profile the export options name.
   Open the generated Xcode project once, select your team under *Signing & Capabilities*,
   and let Xcode create what is missing.

8. **Release.** Set version and build number, write your notes, press *Release to
   TestFlight*.

---

## Build modes for iOS

A Godot iOS export never produces an `.ipa` — it produces an Xcode project, a `.pck` and an
`Info.plist`. Something has to run `xcodebuild` afterwards, so iOS targets have two modes:

| Mode | What happens | Use when |
|---|---|---|
| **Regenerate native project** | Godot regenerates the Xcode project, then `xcodebuild archive` + `exportArchive` | You do not maintain the Xcode project by hand, or you just upgraded Godot |
| **PCK only** | Only the `.pck` is exported; your existing `.xcodeproj` is rebuilt around it | You have edited the Xcode project — capabilities, entitlements, extra frameworks, Swift code. A full export would overwrite it |

Both modes need these fields on the target:

| Field | Example |
|---|---|
| `native_project_path` | `ios/MyGame.xcodeproj` |
| `xcode_scheme` | `MyGame` |
| `export_options_plist` | `ios/ExportOptions.plist` |
| `pck_path` | `ios/MyGame.pck` |

They are filled in automatically from the preset's export path when you pick the preset.

### ExportOptions.plist

`xcodebuild exportArchive` needs it. A minimal App Store one:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store-connect</string>
    <key>teamID</key>
    <string>YOURTEAMID</string>
    <key>uploadSymbols</key>
    <true/>
    <key>signingStyle</key>
    <string>automatic</string>
</dict>
</plist>
```

[Distributing your app with xcodebuild](https://developer.apple.com/documentation/xcode/distributing-your-app-for-beta-testing-and-releases).

---

## The two lanes

Both live in your project's `fastlane/Fastfile` and are yours to edit.

### `ios beta` — TestFlight

Runs [`upload_to_testflight`](https://docs.fastlane.tools/actions/upload_to_testflight/).
Your release notes become the TestFlight **changelog**. If the target has tester groups, the
build is distributed to them externally; with no groups it is uploaded for internal testers
only.

**Skip build processing wait** (a target option) returns as soon as the upload is done
instead of waiting for App Store Connect to finish processing — minutes saved, at the cost
of not learning about a processing failure in the log.

### `ios release` — App Store

Runs [`upload_to_app_store`](https://docs.fastlane.tools/actions/upload_to_app_store/) with
`submit_for_review: false` and `automatic_release: false`: it creates a new version with your
build attached, and stops there. You submit from App Store Connect.

**Release notes are deliberately not uploaded.** The lane sets `skip_metadata: true`, because
pushing metadata would overwrite your entire listing — description, keywords, screenshots —
with whatever happens to be in the local `fastlane/metadata` folder. "What's New" stays
something you write in App Store Connect. If you *do* keep your listing in
`fastlane/metadata`, remove `skip_metadata` from the lane in your own Fastfile.

---

## Version and build numbers

- **Version name** (`CFBundleShortVersionString`) is what users see: `1.4.0`.
- **Build number** (`CFBundleVersion`) must be unique and increasing *within* a version.
  Apple rejects a duplicate.

Both are patched into `export_presets.cfg` before the export, so a later manual export from
*Project → Export* produces the same build. Press **Fetch** on the TestFlight column to see
which build numbers are already taken.

---

## On CI

You need a macOS runner with Xcode, plus the signing identity in the keychain — either
[`fastlane match`](https://docs.fastlane.tools/actions/match/) or importing a `.p12` before
the release step.

No `fastlane/.env` is needed: the lanes read plain environment variables and dotenv ignores a
missing file.

```yaml
env:
  ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
  ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
  ASC_KEY_PATH: ${{ github.workspace }}/AuthKey.p8   # decoded from a base64 secret at run time
```

Decode `.p8` and `.p12` files from secrets into the workspace before the release step, and
delete them afterwards.

**PCK only** mode requires the `.xcodeproj` to be committed, which many projects deliberately
do not do. **Regenerate native project** avoids that.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `No suitable application record was found` | The app record (step 3) does not exist, or the bundle id does not match |
| `The provided entity includes an attribute with a value that has already been used` | Duplicate build number — press Fetch, then bump |
| `Authentication credentials are missing or invalid` | Wrong `ASC_ISSUER_ID`, or the `.p8` does not match `ASC_KEY_ID` |
| `No signing certificate "iOS Distribution" found` | Signing is not set up in the keychain; open the Xcode project once |
| `BUILD_MODE=GODOT_EXPORT cannot work for iOS` | Pick *Regenerate native project* or *PCK only* |
| Upload succeeds, build never appears | Processing failed — check the email from Apple, usually a missing usage-description key or an invalid icon |

---

## Reference

- [App Store Connect](https://appstoreconnect.apple.com/) · [Apple Developer account](https://developer.apple.com/account)
- [App Store Connect API](https://developer.apple.com/documentation/appstoreconnectapi)
- [TestFlight overview](https://developer.apple.com/testflight/)
- [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/)
- fastlane: [upload_to_testflight](https://docs.fastlane.tools/actions/upload_to_testflight/) · [upload_to_app_store](https://docs.fastlane.tools/actions/upload_to_app_store/) · [app_store_connect_api_key](https://docs.fastlane.tools/actions/app_store_connect_api_key/) · [match](https://docs.fastlane.tools/actions/match/)
- Godot: [Exporting for iOS](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_ios.html)
