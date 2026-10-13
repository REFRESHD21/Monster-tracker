# Get the APK from your Android phone

**Status:** the GitHub Actions builder is configured, but has not been executed in your account. No successful APK build or APK download is being claimed. This environment cannot reach its network proxy to download Gradle or the Android SDK. All 36 existing host checks passed again.

You do not need Android Studio on your phone. GitHub builds the app on its Android-capable runner. The installed app still works fully offline and does not use GitHub at runtime.

## Phone-friendly option: upload two files

1. Download the updated **monster-tracker-android-source.zip** and **monster-apk-workflow.yml**. Keep the source ZIP zipped.
2. In Android Chrome, open https://github.com/new and create a **private** repository. Enable **Add a README file** so the `main` branch exists. Switch Chrome to **Desktop site** if GitHub's file controls are hidden.
3. In the repository, choose **Add file → Upload files**, upload `monster-tracker-android-source.zip` to the repository root, then **Commit changes**.
4. Choose **Add file → Create new file**. Enter this exact filename:

   ```text
   .github/workflows/android-apk.yml
   ```

   Open the downloaded `monster-apk-workflow.yml` in a plain-text editor, copy all its text into the GitHub editor, and commit it. The workflow understands the uploaded ZIP and extracts the existing project automatically. You do not need to upload each source file separately.
5. Open the repository's **Actions** tab → **Build Monster Tracker APK**. The commit should trigger it automatically. You can also choose **Run workflow**; leave **Run the SQLite tests on an Android emulator in airplane mode** enabled for the fuller check. First runs may take 15–30 minutes; the configured timeout is 60 minutes.
6. Open the run. Wait for a **green successful result**, then scroll to **Artifacts**. Download **monster-tracker-debug-apk**. GitHub requires you to be signed in to download artifacts.
7. Extract the downloaded artifact ZIP using Android Files. It contains:

   - `Monster-Tracker-debug.apk` — the app to install
   - `SHA256SUMS.txt`
   - `apk-verification.txt`
   - `INSTALL.txt`

8. Open `Monster-Tracker-debug.apk` in Files. Allow **Install unknown apps** for Files when prompted, and tap **Install**. Requires Android 8.0 or later. Launch **Monster Tracker** from the M icon. No account, server or internet setup is required inside the app.

If the workflow is red, open the failed step and download **monster-tracker-build-reports** when available. A failed build/test/verification does not upload an APK. Share that log to diagnose the specific error; do not treat source upload as build success.

Artifacts are retained for 30 days. Download and keep the APK; you can run the workflow again later.

## If your source is already in a repository

Commit the updated project's files with `.github/workflows/android-apk.yml` at the repository root. The workflow also supports an extracted project under `monster-tracker-android/`. Push to `main` or `master`, or start it from Actions → Run workflow. Do not use an older source ZIP with the new workflow: this updated ZIP includes the JUnit bridge and verification changes.

## What the workflow actually does

- Checks out or extracts this same project; it does not generate another app.
- Sets up Temurin JDK 17, Gradle 8.9, Android SDK Platform 35 and Build Tools 35.0.0.
- Runs the original 36 host checks, including comparison with the old tracker across 100 scenarios.
- Runs `:app:testDebugUnitTest` (the JUnit bridge executes the existing 26 native ledger/backup checks), `:app:assembleDebug`, and `:app:assembleDebugAndroidTest`.
- By default, starts an Android API 35 emulator, enables airplane mode, disables Wi-Fi/mobile data, and runs all nine production SQLite instrumentation tests. An explicit manual-run option can skip only these emulator tests; compilation, host/unit tests and APK verification remain mandatory.
- Checks the APK is nonempty, has a valid ZIP structure, Android binary manifest, DEX bytecode, expected package and launcher, a valid signing certificate, and **zero runtime permissions**.
- Uploads the installable APK only after all enabled checks succeed. Test/build reports are also uploaded on failure.

The workflow YAML and every embedded shell script were parsed locally, and the host checks passed. GitHub execution, Android compilation, emulator tests, signature verification and APK creation are still unverified until an actual successful run occurs.

## Keep your records when updating

The workflow caches its generated **debug** signing key so successive test builds usually accept an update over the earlier APK. A cache can expire or be evicted; it is not a permanent release key.

Always export your current records through **Settings → Export full JSON backup** before uninstalling or changing APK signing keys. Keep that JSON outside the phone too. If Android says the new APK conflicts with an existing package, do not uninstall until you have exported the backup. After installing, use **Settings → Import / restore JSON backup** to merge it back. The app never silently overwrites or deletes existing transactions.

For long-term updates, use the signed-release instructions in README.md and keep your own release keystore. The opening 24-can purchase and four unknown-date missing cans still initialize only once, giving 20 available cans.
