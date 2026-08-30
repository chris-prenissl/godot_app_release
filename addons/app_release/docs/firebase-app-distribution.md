# Shipping to Firebase App Distribution

Firebase App Distribution hands an Android build to testers in minutes, without the Play
Console's review and track machinery. It is the fastest path from "I built something" to
"someone else is playing it". Works on macOS and Linux; Windows is best-effort.

Firebase distributes **APKs** here, not AABs — see [Preset format](#preset-format).

---

## Get started in 6 steps

1. **Create a Firebase project** at [console.firebase.google.com](https://console.firebase.google.com/).
   Free; Google Analytics is optional and not needed for distribution.

2. **Register your Android app** in that project — *Project settings → Your apps → Add app →
   Android* — using the same package name as your export preset, e.g. `com.acme.mygame`.

3. **Copy the App ID.** *Project settings → Your apps*, it looks like

   ```
   1:123456789012:android:abcdef1234567890
   ```

   This is not the package name and not the project id. Downloading
   `google-services.json` is optional — the id is in it as `mobilesdk_app_id`.

4. **Enable App Distribution** — open *Release & Monitor → App Distribution* in the console
   once and accept the terms. Uploads fail until this is done.

5. **Create credentials.** Two ways; the first is strongly preferred:

   **Service account (recommended, and required on CI).** In the Google Cloud console for the
   same project, create a service account, grant it the **Firebase App Distribution Admin**
   role, and download its JSON key. Then in `fastlane/.env`:

   ```sh
   FIREBASE_APP_ID_ANDROID=1:123456789012:android:abcdef1234567890
   FIREBASE_SERVICE_CREDENTIALS=/Users/you/keys/firebase-service-account.json
   ```

   **CLI session (convenient locally).** Install the
   [firebase CLI](https://firebase.google.com/docs/cli) and run `firebase login`. Leave
   `FIREBASE_SERVICE_CREDENTIALS` empty and the plugin falls back to that cached session:

   ```sh
   FIREBASE_APP_ID_ANDROID=1:123456789012:android:abcdef1234567890
   FIREBASE_SERVICE_CREDENTIALS=
   ```

6. **Add tester groups** — *App Distribution → Testers & Groups*. Create a group, note its
   **alias** (not its display name), and put the alias in the target's *Test groups* field in
   the Release panel. Comma-separated for several. Leave it empty to upload without
   distributing to anyone yet.

Then press *Release to Firebase App Distribution*.

---

## Preset format

The lane uploads with `android_artifact_type: "APK"`, so the target's export preset must
produce an `.apk`, not an `.aab`.

If you also ship to Google Play, keep **two Android presets** — one APK for Firebase, one AAB
for Play — and point one target at each. The plugin's default config does that automatically
when it finds both.

---

## Release notes and testers

- Your release notes become the App Distribution **release note** shown to testers.
- The *Test groups* field on the column maps to group **aliases**; a wrong alias is a silent
  no-op — the build uploads but nobody is notified.
- Testers get an email; on first install they have to accept the invitation and install the
  App Tester app. That step is per tester, not per build.

---

## Version and build numbers

Firebase does not enforce uniqueness — it will happily take the same version and build twice
and list both. That is convenient for iterating, and a reason to look at the release list
(press **Fetch**) before assuming which build a tester has.

The build number is still Android's `versionCode`, and if the same build later goes to Google
Play, Play's strictly-increasing rule applies there.

---

## On CI

Use a service account; there is no `firebase login` session on a runner.

```yaml
env:
  FIREBASE_APP_ID_ANDROID: ${{ secrets.FIREBASE_APP_ID_ANDROID }}
  FIREBASE_SERVICE_CREDENTIALS: ${{ github.workspace }}/firebase.json   # decoded from a base64 secret
```

Android signing on a runner works the same as for Play — see
[Shipping to Google Play → On CI](google-play.md#on-ci).

---

## How the Fetch button authenticates

Worth knowing, because it surprises people reading network logs:

- With `FIREBASE_SERVICE_CREDENTIALS` set, the release list is fetched with that service
  account. Nothing else is touched.
- With it empty, the plugin refreshes the session left by `firebase login`, using the OAuth
  **client id and secret of the open-source `firebase-tools` CLI**. Those values are
  published in that project's source — they are not secrets of yours. Override them with
  `FIREBASE_CLI_CLIENT_ID` and `FIREBASE_CLI_CLIENT_SECRET` if you prefer your own OAuth
  client.

Either way the credentials stay on your machine; the plugin never stores or transmits them
anywhere else.

---

## Troubleshooting

| Symptom | Cause |
|---|---|
| `Firebase denied access to app 1:…` (403) | The service account lacks the *Firebase App Distribution Admin* role, App Distribution is not enabled, or the app id belongs to another project |
| `no Firebase credentials` | Neither `FIREBASE_SERVICE_CREDENTIALS` nor a `firebase login` session exists |
| `the firebase CLI session has no refresh token` | Run `firebase login` again |
| `Invalid app id` | You used the package name or the project id instead of the App ID from step 3 |
| Upload succeeds, no tester notified | The group alias is wrong, or the group is empty |
| `android_artifact_path` not an APK | The preset exports an AAB — point the Firebase target at an APK preset |

---

## Reference

- [Firebase console](https://console.firebase.google.com/) 
- [App Distribution docs](https://firebase.google.com/docs/app-distribution)
- [Distribute Android apps with fastlane](https://firebase.google.com/docs/app-distribution/android/distribute-fastlane)
- [Manage testers](https://firebase.google.com/docs/app-distribution/manage-testers)
- [Firebase CLI](https://firebase.google.com/docs/cli)
- fastlane plugin: [firebase_app_distribution](https://github.com/fastlane/fastlane-plugin-firebase_app_distribution)
