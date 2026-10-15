# Monster Business Google Play release plan

**Status date:** 15 October 2026  
**Final objective:** a publicly discoverable Google Play Production release for small businesses.
**Release policy:** private testing first. Production submission/rollout is a separate, manual decision and requires the owner's explicit approval.

## Release order

1. Freeze the first-release scope, finish essential app reliability work and fix all release-blocking defects. Defer nonessential roadmap additions (see below) rather than holding stability work hostage to new features.
2. Repair the Flutter/Dart build and test environment; get required tests green in a reproducible clean environment.
3. Complete a restore of the owner's actual backup on a disposable Android installation; separately prove the GitHub-APK-to-Play upgrade or safe backup/restore path without risking the owner's phone data.
4. Configure durable, secure release signing and produce a verified AAB for `au.monster.tracker.plus`.
5. Prepare the Play Console app, an original public brand/listing, privacy policy, Data safety answers, app-content declarations, screenshots and support contact.
6. Run private **Internal testing**, then resolve issues and complete **Closed testing** where appropriate.
7. Apply for Production access if the developer account is subject to that requirement.
8. Prepare the public Production release and listing for the owner's final approval. Do not submit or roll it out until the owner explicitly approves that specific Production action.

Do not configure or use Open testing. Do not auto-promote a track, auto-submit a release, or make the listing public as a side effect of CI.

## Current build and readiness

- Active app: Flutter project in `universal/`.
- Application ID: `au.monster.tracker.plus`.
- Latest verified Actions APK: version **2.3.0**, version code **17**, package `au.monster.tracker.plus`, SHA-256 `182bb6bb16e56c298b7691e95e52a7f19fcaa5db09b99f13bf8ab2322268bac8`. Run [#46](https://github.com/REFRESHD21/Monster-tracker/actions/runs/38730412642) passed Flutter tests/analysis and Android build plus emulator update checks. Its `apksigner` output reports signer SHA-256 `10195e6471ae52ad19633421aa4e50db9bf391fbbb15eb58016c41a6eef1c2dd` (Android Debug certificate).
- The build uses an Actions cache entry named `monster-plus-debug-signing-key-v1`, with the standard Android debug alias/password. Run #46 successfully restored and used it, and the emulator baseline signer matched. This confirms it was available at that run, **not** that it is durable or securely owner-controlled. Cache eviction or a cache miss can prevent a compatible build; the workflow can generate a new debug key that would fail the baseline fingerprint gate.
- A manual-only AAB workflow is prepared at `.github/workflows/play-aab.yml`. It requires upload-key secrets in a protected `play-release` GitHub Environment, checks the configured certificate fingerprint, and stores only a short-retention build artifact. It contains no Google Play upload action. **It has not run and no AAB has been built or verified.** The environment protections and secrets are not configured/verified in this repository session.
- **No Play App Signing certificate is configured or known.** The proposed Play app-signing fingerprint is therefore **unknown**; the upload-key fingerprint (which signs the AAB) is a separate value and is also not yet configured.
- **No Play Console upload has been made.** The account/app setup, track tester lists and owner-controlled signing decisions still need to be completed. Uploading any bundle or creating/publishing a Play release requires separate owner approval.
- The CI emulator proved an update from a populated prior release while retaining its seeded stock/history. It is not a real-device test and is not a test of the owner's actual installed data.
- The app development roadmap in `BI_IMPLEMENTATION_PLAN.md` is not release-complete: purchase/profit work still needs passing Flutter tests, stocktake changes are present in this local worktree but unverified, and retailer price tracking/alerts/deal optimization, customer history, margin alerts and robust restock/forecast features remain unfinished or dependent on external data sources. Keep those roadmap commitments visible; do not imply they are in the public app until implemented and tested.
- The owner-provided backup was validated and replayed outside Android. Its contents, checksums, product names and exact financial figures are intentionally excluded from this public repository. This was not an Android app restore; Dart/Flutter startup and the lack of a disposable emulator/device still block that gate.
- The pinned Flutter 3.35.7 SDK source sets `compileSdkVersion` and `targetSdkVersion` to 36; this is the configured template default, not yet verified in a built AAB manifest. Google Play currently requires API 36 for new mobile apps and updates submitted from 31 August 2026 ([target API policy](https://support.google.com/googleplay/android-developer/answer/11926878?hl=en-AU)).
- The app's Android label is currently `Business Tracker`; the saved business name can display as `Monster business`. The repository does not contain original release icon artwork; bootstrap generates the Flutter template launcher icon. Avoid publishing with Monster Energy's wordmark, claw logo, can artwork or a lookalike presentation unless rights/authorization are documented. Google Play prohibits misleading implication of affiliation and trademark/copyright misuse ([Impersonation policy](https://support.google.com/googleplay/android-developer/answer/9888374), [Intellectual Property policy](https://support.google.com/googleplay/android-developer/answer/9888072)).
- Recommended public title candidate: **Stock & Sales Ledger** (generic, descriptive, within the Play title length limit). This is a recommendation only; no title, launcher label, icon, package ID or in-app name has been changed. A trademark/name search and owner's approval remain necessary before adoption.
- `universal/PRIVACY_DRAFT.md` and `universal/PLAY_DATA_SAFETY_DRAFT.md` are now updated local drafts based on source inspection. They still require final third-party SDK/dependency review, operator contact details and a public HTTPS policy URL before publication.

## First public release scope

The first public release is a dependable, offline-first single-business ledger. A feature is essential when omitting or miscalculating it could lose records, misstate stock or money, break an existing user workflow, or mislead a new user about what the app does.

| Essential for release candidate | Release gate |
|---|---|
| Existing product catalogue, sales (including configured product deals), purchases/restocks, stock movements, damage/missing adjustments, refunds/returns, expenses and current reports | Preserve the shared append-only event ledger and FIFO costing; no parallel ledger or silent history rewrite; reconcile dashboard totals against source events. |
| Offline entry and durable local persistence | Verify database migrations, stale-write protection, duplicate prevention, and clean launches without network. |
| Full backup export/import and recovery | Test old and current formats, checksum rejection, append-only merge behavior, attachments/settings/archived product references and a complete restore on a disposable Android installation. No live-device restore test is satisfied by JSON parsing alone. |
| In-place Android update and iOS compatibility | Retain package `au.monster.tracker.plus`; test version migration with the correct app-signing identity and keep iOS compiling. Never test upgrades by uninstalling the current app. |
| User-visible privacy and honest integration status | Keep Sheets/Apps Script optional and one-way. If an integration is exposed in the release, test it end-to-end, explain exactly which fields it transmits and disclose it. Unconfigured OAuth must say setup is required, not imply a live connection. |
| Supportable public listing | Neutral original branding, support contact and hosted privacy policy; complete Play Data safety, app-content and financial-feature declarations from the exact release artifact. |

### Defer as later enhancements

The following do not block a reliable first release if they are not advertised as available: automatic retailer price collection and its Wednesday scheduler; price-drop alerts; retailer deal optimization; advanced flavour and margin analytics; customer profiles/history; predictive demand forecasts; and cost/lead-time-aware restock recommendations. Keep these in the roadmap, and do not remove any currently working feature. Stocktake work already present in this branch must either pass its ledger, concurrency, backup and UI regression gates before inclusion, or be explicitly kept out of the release candidate without deleting its code/history. No roadmap feature may change the append-only FIFO source of truth.

### First-release user promise

Market the first version as a local business stock-and-sales record keeper, not a retailer-price service, payment processor, multi-user cloud ledger, tax adviser or guaranteed forecast. The app does not charge payment cards. Users can move records between devices only through the tested backup/restore path unless the separately optional one-way Sheets mirror is configured and verified.

### Signing and upgrade gate

Use Google Play App Signing, with a separately registered upload key for AAB uploads. Before the first Play upload:

1. Confirm the installed app's version code and signer on the owner's device. The 2.3.0 (17) Actions artifact was independently matched to the CI `apksigner` evidence; other historical artifacts must be checked by their exact hash and signer.
2. Do not use the cached Android Debug key as the Play app-signing key or upload key. It is not owner-controlled signing material.
3. Before any Play install, obtain the actual Play app-signing certificate from Play Console after an approved signing setup. Compare it with the installed APK fingerprint above. If it differs, Android will refuse an in-place update for the same package unless a valid signing-key rotation proof applies. Treat a Google-generated new signing key as incompatible until that proof is specifically verified.
4. If direct update is unavailable, use a verified full JSON backup/restore on a disposable test installation first. Preserve the existing package ID; do not uninstall the owner's app until a backup from that exact installation has been restored and its record counts, stock and financial totals match. No such owner-data restore has been tested yet.
5. Configure the separate upload key through protected GitHub Environment secrets and required reviewers. Keep its keystore/password material out of source control and pull-request jobs. Never generate a replacement key just to unblock a build.
6. Build and verify the AAB, then test a Play-delivered build on disposable devices before any owner-data migration. Back up live data first. Do not uninstall or clear data as a workaround for a signing/update failure.

The Android package remains unchanged. Every newly built release candidate gets a version code greater than the last code used on any Play track. Promote the exact tested AAB/version code between Internal and Closed tracks; if code changes after a fix, build a new AAB with a higher version code and repeat the necessary checks. Never rebuild a different binary while presenting it as the already-tested artifact.

## AAB build and verification gate

The manual-only workflow is prepared but remains unverified until protected secrets and environment rules are configured. It must:

- Use a pinned Flutter/Android toolchain and the verified release source commit.
- Require the approved upload keystore via protected release-only secrets; fail closed if it is unavailable. Do not fall back to the cached debug key.
- Build `app-release.aab` from the Flutter app, retaining `au.monster.tracker.plus` and the selected version code.
- Validate the AAB with `bundletool validate`; verify the JAR signature and expected upload-certificate SHA-256; inspect the bundle manifest for package, version name/code, SDK levels and permissions; check bundle contents and native ABIs; and produce a SHA-256 checksum plus build provenance.
- Generate device-targeted APKs from the AAB with `bundletool`, then install/upgrade those on disposable emulator/device fixtures. Verify launch and data migration; this complements, but does not replace, Google Play delivery testing.
- Save the AAB and evidence as a restricted/short-retention workflow artifact. Never publish a Play release from CI.

Release evidence should identify commit SHA, AAB checksum, version name/code, upload-certificate fingerprint, Play app-signing-certificate fingerprint once confirmed, toolchain versions, test results, known issues and artifact retention date.

## Public app identity, privacy and Play listing

### Brand and listing review

- Current technical application ID stays `au.monster.tracker.plus`; changing the Play title or launcher label does not require changing this ID. Keep the package unchanged for signing and data-migration compatibility.
- Current source-level name is `Business Tracker`; the user can name their own ledger (the inspected real backup uses “Monster business”). Repository documentation and history also use Monster Tracker/Monster Business. Do not present the app as official, endorsed or affiliated with Monster Energy. Use an original neutral icon and screenshots with fictional, unbranded sample inventory; do not use Monster Energy logos, claw marks, distinctive can artwork or brand-like trade dress without written permission.
- Public title candidate: **Stock & Sales Ledger**. Search title/app-store availability and relevant trademark registers before use. Do not adopt it until the owner approves the public-facing identity. Developer name, title, icon and screenshots must consistently identify the independent app and its actual functions.
- An original vector icon concept is prepared at `docs/store-branding-proposal.svg`. It is a proposal only; it is not wired into Android/iOS launcher assets. Obtain name/trademark review and owner approval before applying any identity changes.
- Store asset work needed: original 512×512 PNG Play icon, feature graphic, phone screenshots from the release build, short/full description, support email/site and public privacy URL. Do not use the current Flutter template icon as final artwork. Play requires clear, accurate metadata; titles are limited to 30 characters ([metadata policy](https://support.google.com/googleplay/android-developer/answer/18258653), [icon guidance](https://developer.android.com/distribute/google-play/resources/icon-design-specifications)).

### Data handling basis for declarations

Current code inspection finds offline SQLite records for business name, products, prices, stock movements, sales/refunds, purchases, expenses, GST snapshots, notes, archive/deal settings and optional receipt/photo bytes. Camera is requested for user-selected photos/barcode scanning; file/photo selection is user-initiated; OCR is invoked locally in the app. No customer-history feature is currently present. Sales' cash/card field is bookkeeping metadata; the Flutter app does not process payment-card charges. No ads or app analytics/crash-reporting SDK were found in the inspected direct dependencies/source, but the exact release dependency manifests and third-party SDK data practices still need auditing.

Data remains local unless the user exports/shares a backup or enables a Sheets connection. Plain JSON backups include records and attachments and are unencrypted; encrypted portable backups use AES-256-GCM/PBKDF2; credentials and pairing secrets are excluded from portable backups and stored in platform secure storage. User-selected file providers may transfer backup files under their own service terms.

The optional native Sheets flow requests the narrow `drive.file` scope, records the selected Google account email/account ID in secure storage, and sends user-selected business data to a spreadsheet the user creates or selects. Sheets tabs include Products, Sales, Purchases, Expenses and legacy document rows. Receipt photo/PDF bytes are not uploaded by this flow. The advanced Apps Script path sends ledger/product/document records, notes and receipt metadata to the endpoint and token supplied by the user; its receiver and retention are outside the app operator's control. Google or the chosen endpoint may retain data until the user deletes it there. Sheets edits do not flow back into the app.

Use `universal/PRIVACY_DRAFT.md` and `universal/PLAY_DATA_SAFETY_DRAFT.md` as review drafts, not published statements. Finalize after auditing locked dependency versions, ML Kit/Google Sign-In behavior, exact upload payloads, platform backups and the exact release artifact. Play requires a public privacy policy and accurate Data safety details that match SDK behavior and the policy ([User Data policy](https://support.google.com/googleplay/android-developer/answer/10144311)).

### Play Console content and account checklist

- Verify the correct personal or organization developer account type and complete identity/contact verification. Organization accounts need business details including a D‑U‑N‑S number; public developer details vary by account type ([account details](https://support.google.com/googleplay/android-developer/answer/13628312), [contact requirements](https://support.google.com/googleplay/android-developer/answer/10840893)).
- Complete App access instructions (core records work without a login; explain optional Sheets access), Ads declaration (source currently contains no advertising SDK), target audience (business utility, not designed for children, subject to owner confirmation), IARC content rating, privacy policy, Data safety, financial-features declaration, permissions declarations if triggered, and all current policy questionnaires. Google requires the financial-features declaration even for apps declaring no such features. This app records bookkeeping; it does not offer banking, lending, investing, payment processing or financial accounts, but the owner must answer the Console questionnaire truthfully ([content rating](https://support.google.com/googleplay/android-developer/answer/9898843), [financial features declaration](https://support.google.com/googleplay/android-developer/answer/13849271), [prepare for review](https://support.google.com/googleplay/android-developer/answer/9859455)).
- Confirm `targetSdkVersion` in the release AAB manifest is at least 36 before submission; keep the build template and plugin SDK compatibility aligned. Targeting API 36 may expose edge-to-edge, permission, background-work and storage behavior changes that need Android 16/device testing.
- Review app-content declarations, content rating, target country/regions, accessibility, permission use (INTERNET and CAMERA in the app manifest), screenshots and listing claims against the actual release.
- For a personal developer account created after 13 November 2023, Google currently requires at least 12 closed-testers opted in continuously for 14 days before the Production-access application. Check the exact requirement shown in Play Console; organization accounts and older personal accounts may have different gates ([testing requirements](https://support.google.com/googleplay/android-developer/answer/14151465)).

## Internal testing: first Play priority

Only after the AAB, key compatibility and disposable upgrade gates pass, prepare an Internal testing release. Keep the tester list limited to the owner and named invitees. Play's internal track supports up to 100 testers; access requires the approved account list. Do not expose an open opt-in link or enable public testing.

Before the owner authorizes upload, prepare in Play Console:

- App record using the existing package ID; confirm app ownership and that no conflicting Play app record exists.
- Play App Signing enrollment/key choice and upload certificate registration.
- Private Internal testing track, invited tester email list, countries/device availability and feedback contact.
- Release notes clearly marked as private test software; no public production rollout.
- Tester instructions and feedback form/channel. Record tester, device model, Android version, app version, install/update path, test scenario, expected/actual result, severity, reproducibility and optional redacted screenshot/log.

### Internal real-device test checklist

Test on the owner’s supported Android device and at least one additional Android device/version where practical. Use a backup and test dataset; verify the owner’s live records only after the disposable checks succeed.

- Fresh Play installation, launch, offline launch and permitted update from the prior installed release without uninstalling or clearing app data.
- Existing history, product settings, deal/archive state, purchase history and backups remain intact after update and app restart.
- Record cash/card sales, discounts, sale retries/double taps and refunds; confirm no duplicate transaction and reconcile totals.
- Record a multipack purchase with multiple products; confirm individual-can quantities, purchase history and FIFO cost calculations.
- Add stock, record damaged/missing stock and complete a stocktake; ensure adjustments do not create sales revenue.
- Compare sales revenue, product profit, inventory and net-profit reports with the underlying records.
- Export and validate a backup; do not use restore as a substitute for an upgrade test.
- Capture crashes, ANRs, failed installs, permission issues, slow screens and any mismatch in financial totals. Triage before expanding to Closed testing.

No production business data should be sent to testers. Testers should not share backups, customer details, payment credentials or unredacted sensitive records in feedback.

## Tester invite and feedback template

> **Monster Business private Internal test**  
> Please join only if you were invited. Install/update through the Google Play opt-in link: **[owner inserts private link after approval]**. This is a private test, not a public release.  
> Test app version: **[version name] ([version code])**. Device/Android version: **[fill in]**.  
> Please test installation/update, existing-record retention, a sale, a stock purchase, stock changes, and financial reports. Use test data and back up any personal business records before updating. Do not uninstall or clear app data if an update fails; report the error instead.  
> Send feedback to **[owner-selected private email/form]** with steps to reproduce, expected and actual result, app/device versions and a redacted screenshot if useful. Do not include customer/payment secrets or full backups.

## Closed testing and production access

After Internal issues are fixed, create a separate private Closed testing track with a larger invited group and a clearly identified feedback channel. Continue testing upgrades, migration, core financial calculations, stability and device coverage. Do not invite the group until the owner has approved the tester list and release notes.

Google currently requires new personal developer accounts created after 13 November 2023 to run a Closed test with at least 12 testers opted in continuously for at least 14 days before applying for Production access. Confirm the exact requirement shown in this app's Play Console at the time; account type and policy may change. If applicable, keep dated evidence of opted-in tester count, participation period, feedback, fixes and the Production-access application. Meeting the minimum does not guarantee approval.

Production preparation may include final listing/data-safety declarations, policy review, staged rollout/monitoring and rollback notes. This is the intended final objective. These are preparation tasks only. The Production track stays untouched until the owner separately approves a specific release/version and rollout.

## Release issue and crash log

Maintain a release log alongside each test cycle. One row per issue:

| ID | Version/build | Device + Android | Track | Severity | Scenario / steps | Expected vs actual | Crash/ANR or evidence | Status / fix version |
|---|---|---|---|---|---|---|---|---|

Use Play Console testing feedback, Android vitals and available pre-launch reports after a Play build exists; supplement them with tester reports. Remove customer data, access tokens and payment details from logs before sharing. Block track promotion for data-loss risk, signing/update failure, crash on core paths, duplicate/missing financial transactions, or unreconciled reports. Retest every fix on the affected devices and rerun regression tests.

## Approval boundary

Codex may edit source, prepare build workflows, run local/CI checks and create non-Play build artifacts. It must not upload an AAB/APK to Play Console, create or publish a Play track release, invite testers, apply for Production access, or roll out Production without the owner's explicit approval for that action. Production approval must never be inferred from approval for Internal or Closed testing.

## External references

- [Google Play testing tracks and tester setup](https://support.google.com/googleplay/android-developer/answer/9845334)
- [Testing requirements for new personal developer accounts](https://support.google.com/googleplay/android-developer/answer/14151465)
- [Android app signing and Play App Signing](https://developer.android.com/studio/publish/app-signing)
- [Android App Bundle overview](https://developer.android.com/guide/app-bundle)
