# Shipping to Google Play

Everything you need on the Google side, once. Works on macOS and Linux; Windows is
best-effort.

---

## Get started in 8 steps

1. **Create a Play Console developer account** — 25 USD, one time.
   [play.google.com/console](https://play.google.com/console/signup). Expect an identity
   verification step that can take days.

2. **Create the app** in the Play Console and choose a **package name**, e.g.
   `com.acme.mygame`. Like a bundle id, it is permanent.

3. **Set up a release keystore.** Google Play requires signed release builds.

   ```sh
   keytool -genkey -v -keystore ~/keys/mygame-release.keystore \
       -alias mygame -keyalg RSA -keysize 2048 -validity 10000
   ```

   In Godot: *Editor → Editor Settings → Export → Android* — set the release keystore, user
   (the alias) and password. Back up that file: losing it means you can never update the app
   unless you use Play App Signing (recommended, and on by default for new apps).
   [Sign your app](https://developer.android.com/studio/publish/app-signing).

4. **Install the Android build template** — *Project → Install Android Build Template* in the
   Godot editor, and tick **Use Gradle Build** in your Android export preset. Required for
   AAB output. [Gradle builds](https://docs.godotengine.org/en/stable/tutorials/export/android_gradle_build.html).

5. **Upload one AAB by hand.** The Play API cannot create the first release of an app — the
   first upload must go through the Play Console UI. Do it once, then everything after is
   automated.

6. **Create a service account** for the API:

   - Play Console → *Users and permissions → Invite new users*, or via Google Cloud:
     [Setting up API access](https://developers.google.com/android-publisher/getting_started)
   - create the service account in Google Cloud, download its **JSON key**
   - back in the Play Console, grant that service account access to your app with at least
     *Release apps to testing tracks* and *Release to production*

   Google needs a few minutes to propagate new permissions.
   [fastlane's walkthrough](https://docs.fastlane.tools/actions/supply/#setup).

7. **Fill in `fastlane/.env`** (created by *Install release scripts*, and gitignored):

   ```sh
   PLAY_JSON_KEY_PATH=/Users/you/keys/play-service-account.json
   ```

   Keep the JSON outside your repository. It is a credential for your whole developer
   account.

8. **Set `android_package_name`** in `release_config.tres` under *App identity* — usually
   already seeded from your export preset — then press *Release to Google Play*.

---

## Tracks

The `play_track` field on the target picks where the build lands:

| Track | Who sees it | Typical use |
|---|---|---|
| `internal` | up to 100 testers you list, available within minutes | Daily builds |
| `alpha` | a closed tester list | Wider internal testing |
| `beta` | open or closed testing | Public beta |
| `production` | everyone | The real release |

The default config creates two Play targets — `internal` and `production` — so the two live
side by side as separate columns.

**A production upload is created as a draft** (`release_status: "draft"`), not rolled out.
You still press the button in the Play Console. Change `release_status` in your own
`fastlane/Fastfile` if you want staged rollout instead.

---

## APK or AAB

| Format | Used for |
|---|---|
| **AAB** (`.aab`) | Google Play. Required for new apps since August 2021 |
| **APK** (`.apk`) | Firebase App Distribution, direct installs |

Set the format in the export preset (*Export Format*), not on the target. If you ship to both
Play and Firebase, keep **two Android presets** — one AAB, one APK — and point one target at
each. The plugin's default config does exactly that when it finds both.

---

## Version and build numbers

- **Version name** is the user-visible string: `1.4.0`.
- **Build number** is Android's `versionCode`: an integer that must strictly increase. Play
  rejects a code it has already accepted, and you can never reuse one, not even after
  deleting the release.

Press **Fetch** on the Play column to see the codes each track currently holds.

---

## Release notes

Your notes become the Play **changelog**. The plugin writes them to

```
fastlane/metadata/android/en-US/changelogs/<build>.txt
```

and the lane uploads that file. Listing metadata (title, description, screenshots) is
deliberately **not** uploaded — `skip_upload_metadata`, `skip_upload_images` and
`skip_upload_screenshots` are set, so a local `fastlane/metadata` folder can never overwrite
your live listing by accident. Remove those options in your own Fastfile if you want fastlane
to manage the whole listing.

To ship notes in more languages, add
`fastlane/metadata/android/<locale>/changelogs/<build>.txt` yourself.

---

## On CI

No `fastlane/.env` needed — the lane reads plain environment variables:

```yaml
env:
  PLAY_JSON_KEY_PATH: ${{ github.workspace }}/play.json   # decoded from a base64 secret
```

**Signing on a runner.** Godot normally reads the keystore from your Editor Settings, which a
runner does not have. Pass it through the environment instead:

```
GODOT_ANDROID_KEYSTORE_RELEASE_PATH      absolute path — the shell will not expand ~
GODOT_ANDROID_KEYSTORE_RELEASE_USER      key alias
GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD  key password
```

Two traps: the path must be absolute, and setting *some but not all* of the matching
`GODOT_ANDROID_KEYSTORE_DEBUG_*` variables can break a release export
([godot#109551](https://github.com/godotengine/godot/issues/109551)) — set all of a group or
none of it.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Package not found: com.acme.mygame` | No app with that package name, or the first upload was never done by hand (step 5) |
| `The caller does not have permission` | The service account has no access to this app, or the grant has not propagated yet |
| `Version code N has already been used` | Bump the build number; Fetch shows what is taken |
| `Your app cannot be released ... it is signed with the debug key` | Untick *Debug build*, and configure the release keystore |
| `APK/AAB not accepted for this track` | Play wants an AAB — check the preset's export format |
| Gradle errors during export | The Android build template is missing or stale: *Project → Install Android Build Template* |

---

## Reference

- [Play Console](https://play.google.com/console) · [Play Console Help](https://support.google.com/googleplay/android-developer)
- [Google Play Developer API — getting started](https://developers.google.com/android-publisher/getting_started)
- [About Android App Bundles](https://developer.android.com/guide/app-bundle)
- [Play App Signing](https://support.google.com/googleplay/android-developer/answer/9842756)
- fastlane: [supply / upload_to_play_store](https://docs.fastlane.tools/actions/upload_to_play_store/)
- Godot: [Exporting for Android](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_android.html) · [Gradle builds](https://docs.godotengine.org/en/stable/tutorials/export/android_gradle_build.html)
