# Google Sheets connection: owner setup and verification

The app offers Connect Google Sheets → choose account → create new / choose existing
spreadsheet → preview → automatic uploads. Upload now and Open spreadsheet are in
Settings. Normal setup never asks the phone user for Apps Script, URLs or tokens.
Advanced Apps Script remains available for existing connections.

## Owner-controlled Google Cloud configuration

The owner-supplied public Web OAuth client ID is in
`config/google-oauth.json`, included at build time. It is a public application
identifier, not a token or secret. The iOS client ID remains owner setup. **Do not supply or embed an OAuth client secret.**

1. Choose an owner-controlled Google Cloud project. Enable Google Sheets API,
   Google Drive API and Google Picker API.
2. Configure Google Auth Platform branding, support contact, audience and data
   access. Use only `https://www.googleapis.com/auth/drive.file` for file access;
   the sign-in SDK also uses basic identity scopes to display/retain the selected
   account. Do not request all-Drive or all-spreadsheets scopes.
3. Create an Android OAuth client with package **au.monster.tracker.plus** and the
   **SHA-1 of the actual existing signing certificate**. Obtain SHA-1 from the
   CI `apksigner --print-certs` report; do not substitute SHA-256. For the
   existing certificate it is `8A:E4:48:1C:C9:CE:18:74:44:06:80:BB:98:DA:19:C3:D9:14:65:9B`. The APK must
   retain SHA-256 certificate digest
   `10195e6471ae52ad19633421aa4e50db9bf391fbbb15eb58016c41a6eef1c2dd`.
   The existing key is the historic test certificate; this work does not replace
   it or change the package/signing identity.
4. Create a Web application OAuth client in the same project for native Google
   Sign-In's serverClientId setting. Only the public client ID is used. There is
   no backend, web OAuth redirect or client-secret exchange for this client.
5. Create an iOS OAuth client for bundle ID **au.monster.tracker.plus**. The
   bootstrap script installs its GIDClientID and reversed-client-ID URL scheme.
   The Picker uses that native iOS client with PKCE/state and the system browser,
   then checks that its selected account matches the connected account.
6. The Android Web client ID is already configured in `config/google-oauth.json`.
   For iOS, add the repository Actions variable `GOOGLE_IOS_CLIENT_ID`
   (a public ID ending `.apps.googleusercontent.com`).
   The workflow passes the JSON config and iOS variable as Dart defines. The iOS client is also passed to
   the bootstrap script as an environment variable. For manual builds:

   ```sh
   export GOOGLE_IOS_CLIENT_ID='YOUR_IOS_PUBLIC_CLIENT_ID'
   python3 scripts/flutter/bootstrap.py
   cd universal
   flutter build apk --release --dart-define-from-file=config/google-oauth.json
   flutter build ios --release --no-codesign --dart-define=GOOGLE_IOS_CLIENT_ID=YOUR_IOS_PUBLIC_CLIENT_ID --dart-define-from-file=config/google-oauth.json
   ```

7. While the consent screen is in Testing, add the actual Google accounts as test
   users. The owner must complete any branding, domain/privacy policy, publishing
   or verification requirements Google displays. `drive.file` is a non-sensitive
   scope; that does not imply all consent/branding requirements are waived.
8. Build again and test both devices with the configured project. Without IDs,
   Connect displays an explicit setup-needed error. A compiled APK is not proof
   that live Google authorization, Picker, consent or uploads work.

## Data and retry contract

- The SDK owns account tokens. Connection/account metadata uses platform secure storage. A random local
  installation ID lives separately in SQLite. Neither enters the portable backup.
  Each newly initialized installation chooses its own connection and tabs even
  when restoring the same business backup. Disconnect signs out, disables jobs
  and clears connection metadata while retaining local records and remote files.
- Products, Sales, Purchases, Expenses and OriginalDocuments are previewed before
  enabling automatic uploads. Each tab has an installation UUID suffix to prevent
  two phones overwriting one another in a shared spreadsheet. Other existing tabs
  are retained. The upload writes only these reserved tabs.
- Amounts are integer AUD cents, dates UTC epoch milliseconds, and allocations /
  original supplier lines are JSON text. Photos and receipt bytes stay in backups.
  Reversals retain target IDs; the mirror is an audit report, not a financial
  formula dashboard. User strings are typed as strings, never Sheet formulas.
- A snapshot replaces fixed rows, never appends. A lost successful response is
  safe to retry: the same rows are overwritten. The local acknowledgement advances
  only after the complete write succeeds. Tab creation is deterministic too.
  A database lease prevents simultaneous foreground/background uploads.
- Local changes are durable before upload. Pending status compares local snapshot
  hash with the last successful acknowledgement. Automatic retries run after
  saves, on resume, every two minutes while open and with network-constrained
  scheduled work. Android/iOS can defer background work; authorization requiring
  interaction must be resumed in the foreground. Upload now forces a full mirror,
  including repairing edits to reserved Sheet tabs. Sheet values never update
  local business records.
- Network errors, revoked permissions, missing files and disabled APIs leave local
  records untouched. Status records the error and last successful upload.
- Very large spreadsheets may hit Google's cell, request or quota limits. Failure
  leaves the snapshot pending. Export CSV if the report exceeds supported limits.

## Live acceptance checks still required

On Android with the existing signed upgrade and on a signed iPhone build: choose
an account, cancel account selection, create a spreadsheet, pick an existing file,
verify preview/data, enable automatic uploads, disable network and record sales,
reconnect, repeat Upload now, verify no duplicate rows, change a Sheet cell and
confirm no local changes, revoke permission, reconnect, disconnect, restore a
backup onto a second installation and verify independent connection/tabs. Confirm
background token renewal without a sign-in dialog. These require the owner's
project/account and have **not** been claimed as tested by mock retry tests.

Sources checked 15 October 2026:
- https://developers.google.com/workspace/sheets/api/scopes
- https://developers.google.com/workspace/drive/picker/guides/desktop-mobile-picker
- https://developer.android.com/identity/authorization
- https://developers.google.com/identity/sign-in/ios/start-integrating
- https://developers.google.com/identity/protocols/oauth2/native-app
- https://pub.dev/packages/google_sign_in/versions/6.3.0
