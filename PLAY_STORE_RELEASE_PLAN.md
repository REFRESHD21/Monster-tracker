# Monster Business Google Play release plan

**Status date:** 15 October 2026  
**Release policy:** private testing first. Production is a separate, manual decision and requires the owner's explicit approval.

## Release order

1. Build and verify a stable Android App Bundle (AAB) for the existing Android app identity.
2. Publish that AAB to **Internal testing** for the owner and invited testers only.
3. Test Play installation and upgrades on real Android devices, including retention of existing business records and the core sales, purchases, stock and financial-report flows.
4. Log crashes, failed scenarios and feedback; fix release blockers and publish a higher-version-code internal build for retest.
5. Promote a verified build to **Closed testing** for a larger invited group. Keep the track private and use email lists or a restricted Google Group.
6. Complete any Google Play testing period and apply for production access if the developer account requires it.
7. Prepare a Production release only after testing passes. Do not submit or roll it out until the owner explicitly approves that production action.

Do not configure or use Open testing. Do not auto-promote a track, auto-submit a release, or make the listing public as a side effect of CI.

## Current build and readiness

- Active app: Flutter project in `universal/`.
- Application ID: `au.monster.tracker.plus`.
- Latest verified APK: version **2.3.0**, version code **17**. CI run [#45](https://github.com/REFRESHD21/Monster-tracker/actions/runs/38723780124) passed 56 Flutter tests, analysis, Java/SQLite and Sheets regressions, Android release/debug builds, signing checks and an emulator in-place upgrade fixture.
- **No AAB has been built or verified yet.** The current workflow builds APKs only. The existing GitHub Actions signer is a cached Android Debug certificate used for compatibility testing; it is not a durable owner-controlled Play upload credential.
- **No Play Console upload has been made.** The account/app setup, track tester lists and owner-controlled signing decisions still need to be completed. Uploading any bundle or creating/publishing a Play release requires separate owner approval.
- The CI emulator proved an update from a populated prior release while retaining its seeded stock/history. It is not a real-device test and is not a test of the owner's actual installed data.

### Signing and upgrade gate

Use Google Play App Signing, with a separately registered upload key for AAB uploads. Before the first Play upload:

1. Identify the SHA-256 signing certificate on the existing install(s) that must be upgradeable and record it in the release evidence. Do not infer the production certificate from a package ID or from the CI result alone.
2. In Play Console, choose/confirm an app-signing key compatible with those installs. The Play app-signing certificate used for delivered APKs must match the existing installed app's signer for a direct in-place update to work.
3. If the only available matching private key is the cached CI test key, stop: it is not a reliable owner-controlled release key. Do not let Play generate or enroll a different app-signing identity until the owner understands that existing direct installs may not accept that update and approves a safe migration plan.
4. Configure a separate upload key through a trusted owner-controlled process. Keep keystore/password material out of source control and pull-request jobs; use restricted release secrets or another approved secure signing service. Never generate a replacement key just to unblock a build.
5. Build and verify the AAB, then install Play-delivered builds on disposable test devices before asking anyone to update a phone with live records. Back up live data first. Do not uninstall or clear data to work around a signature/update failure.

The Android package remains unchanged. Every newly built release candidate gets a version code greater than the last code used on any Play track. Promote the exact tested AAB/version code between Internal and Closed tracks; if code changes after a fix, build a new AAB with a higher version code and repeat the necessary checks. Never rebuild a different binary while presenting it as the already-tested artifact.

## AAB build and verification gate

Add a release-only CI workflow that is manually dispatched and never uploads to Play. It must:

- Use a pinned Flutter/Android toolchain and the verified release source commit.
- Require the approved upload keystore via protected release-only secrets; fail closed if it is unavailable. Do not fall back to the cached debug key.
- Build `app-release.aab` from the Flutter app, retaining `au.monster.tracker.plus` and the selected version code.
- Validate the AAB with `bundletool validate`; verify the JAR signature and expected upload-certificate SHA-256; inspect the bundle manifest for package, version name/code, SDK levels and permissions; check bundle contents and native ABIs; and produce a SHA-256 checksum plus build provenance.
- Generate device-targeted APKs from the AAB with `bundletool`, then install/upgrade those on disposable emulator/device fixtures. Verify launch and data migration; this complements, but does not replace, Google Play delivery testing.
- Save the AAB and evidence as a restricted/short-retention workflow artifact. Never publish a Play release from CI.

Release evidence should identify commit SHA, AAB checksum, version name/code, upload-certificate fingerprint, Play app-signing-certificate fingerprint once confirmed, toolchain versions, test results, known issues and artifact retention date.

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

Google currently requires accounts that meet its new personal-account testing criteria (personal developer accounts created after 13 November 2023) to run a Closed test with at least 12 testers opted in continuously for at least 14 days before applying for Production access. Confirm the exact requirement shown in this app's Play Console at the time; account type and Play policy may change. If applicable, keep dated evidence of opted-in tester count, participation period, feedback, fixes and the Production-access application. Meeting the minimum does not guarantee approval.

Production preparation may include final listing/data-safety declarations, policy review, staged rollout/monitoring and rollback notes. These are planning tasks only. The Production track stays untouched until the owner separately approves a specific release/version and rollout.

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
