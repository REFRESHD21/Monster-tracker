# Google Play Data safety worksheet — draft for owner review

This is a source-based preparation worksheet, not a submitted Play declaration.
The final answers must be checked against the exact locked Android dependency
graph, merged manifest, AAB, SDK disclosures and actual network behavior. Google
requires the Play Data safety section and privacy policy to agree.

## App behavior found in the repository

- Core business records are kept in local SQLite. No app account or operator
  business backend is present in the Flutter client.
- Google Sheets is optional. When configured, the app obtains a Google account
  and uses Drive/Sheets APIs to upload a one-way mirror to a spreadsheet chosen
  by the user. The native scope is `drive.file`.
- An advanced, user-configured Apps Script endpoint can receive product,
  transaction, document, audit/refund and receipt metadata records. The user
  supplies its URL and token.
- Backups can be plain JSON or password-encrypted. A user-selected document
  provider may store/export them. Receipt/photo bytes are included in full
  backups but are not sent by the native Sheets upload implementation.
- Camera/photo/document selection, barcode scan, and local receipt OCR are
  user-initiated. No direct ads, analytics or crash reporting dependency was
  identified in the inspected pubspec; transitive native SDK behavior remains
  to be checked.

## Candidate Play data types to assess

| Play data type / candidate | When present | Purpose | Sent to | Declaration notes |
|---|---|---|---|---|
| Personal info — email address | User connects Google Sheets | App functionality, account selection and reconnecting the chosen sheet account | Google Sign-In / Google APIs; stored in platform secure storage | Optional; do not claim this is never collected if the Google flow remains in the release. Confirm exact SDK behavior. |
| Financial info — other financial information | User enters business transactions; uploaded only if user enables Sheets | App functionality and user-requested reporting | Local by default; chosen Google Sheet or user Apps Script endpoint when enabled | Includes the user's own sales, purchase costs, expenses, tax entries and inventory values; not payment card numbers or financial account data. Confirm Play taxonomy and collection/sharing answers in Console. |
| Files and docs / user-generated content | User attaches receipts/photos/documents or writes notes | App functionality and user-directed backup/export | Local by default; backup destination if user exports; optional endpoint receives metadata only | Full backup contains attachment bytes. Native Sheets and Apps Script record mirrors omit receipt/photo bytes. Recheck `syncRecords`/`sheetSnapshot` for the release. |
| App activity / diagnostics | Unknown pending SDK audit | Unknown | Possible native SDK/platform diagnostics | Do not declare “none” until reviewing Google Sign-In, ML Kit, scanner, WorkManager, file-picker and transitive SDK disclosures/network behavior. |

### Provisional form logic

- Collection is **optional** for cloud transfer; core ledger use is offline. If
  the Data safety form treats user-authorized upload as collection, declare the
  applicable data types and purposes. Do not claim “no data collected” based
  only on local-first behavior.
- For Sheets/Apps Script transfers, data leaves the device over HTTPS. Verify
  the current Play questions for encryption in transit and deletion mechanisms
  against implementation and the public policy. Do not mark local SQLite as
  app-encrypted; it is private app storage without a database encryption layer.
- No ads, payment processing, sale of personal data or app-owned cloud account
  system is present in inspected Flutter source. Reconfirm dependency and
  release artifact contents before answering.
- Users must delete remote spreadsheet/receiver data and exported backups
  separately. Disconnect only removes the local link; it is not remote deletion.
- Target audience is expected to be business users, not children, subject to
  the owner's final audience declaration. Complete the IARC rating and
  financial-features form truthfully; bookkeeping summaries do not themselves
  mean the app offers banking/payment services.

## Required completion before Console submission

1. Resolve and archive the exact release dependency tree; inspect Android merged
   manifest, SDK privacy disclosures, network endpoints and SDK data practices.
2. Confirm the Google and Apps Script upload payloads, persisted OAuth fields,
   backup/export flows and any provider behavior on a release build.
3. Decide whether any customer/contact fields are present in the actual release;
   this inspected source has no customer-history module.
4. Complete the Play form using current Console categories, including data
   collection, sharing, purpose, optionality, deletion, encryption in transit,
   ads, target audience, app access, content rating and financial features.
5. Publish the matching privacy policy at a stable HTTPS URL and link it in the
   app and Play Console. Replace all operator/contact/date placeholders first.

## Owner-provided items

- Public operator/developer name and support email or site.
- Final public app name and original branding approval.
- Public privacy-policy URL after hosting.
- Target countries, intended age groups, whether the app is free/paid, and
  accurate Play Console questionnaire answers.
