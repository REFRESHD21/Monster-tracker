# Privacy policy draft — Stock & Sales Ledger

**Not ready to publish.** Before distribution, the app owner must choose the
public app/operator name, provide a working support contact, set the effective
date, host this policy at a public HTTPS URL, and verify every statement against
the exact release build and its third-party SDKs. The title is only a proposal;
the app's current display name and application ID have not been changed.

## Information the app stores

The app is designed to keep its business ledger on the device. Depending on the
features used, local SQLite storage can contain a business name; products,
prices, barcodes and stock; purchases, sales, refunds, expenses, tax entries and
inventory adjustments; notes and timestamps; and receipt or product image/file
attachments. Existing imported history is retained. Receipt text recognition is
started by the user and is presented as an on-device suggestion for manual
review; it does not itself create a transaction.

The local database is stored in the app's private storage but is not encrypted
by an application-level database encryption layer. Protect the phone with its
screen lock and use encrypted portable backups for copies outside the app.
Camera access is used only when the user chooses a photo or barcode scan.
Photos/documents are accessed through user-initiated system pickers where
available. The app does not request location or contacts permissions.

The app does not require a Monster Business account. The Flutter app records
cash/card transaction labels for bookkeeping; it does not charge or refund
payment cards. The current app does not include customer profiles, advertising,
or an app analytics/crash-reporting service in its direct dependency list.
Third-party SDK behavior must still be checked for the release build.

## Optional Google Sheets connection

If the user connects Google Sheets, Google Sign-In is used to select an account.
The app keeps the selected account ID and email, selected spreadsheet ID,
connection status and upload checkpoint in platform secure storage; Google
Sign-In manages authorization tokens through its SDK/platform integration. The
app requests the Google `drive.file` scope and works with files created or
selected for this app. The user must choose or create a spreadsheet and enable
uploads; records otherwise remain local.

When enabled, the app sends business information to the selected Google
spreadsheet over HTTPS. Uploaded tabs can include product names, categories,
variants, prices, deal/archive settings and barcodes; transaction IDs, dates,
quantities, sales, refunds, purchase costs, fees, payment labels, stock
adjustments, notes and tax amounts; and legacy supplier document fields and
lines. The Google Sheets path does not upload receipt image/PDF bytes. Google
processes and stores the spreadsheet under its own terms and privacy policy.
The spreadsheet owner controls access, retention and deletion. Disconnecting
removes the app's local connection credentials and stops future uploads; it
does not delete spreadsheet data.

An advanced Apps Script option is also present for users with an existing
connection. It sends ledger, product, purchase/document, refund/audit and receipt
metadata records, plus the configured token, to the HTTPS endpoint supplied by
the user. The app does not control that script, its owner, its Google account,
or its retention/sharing settings. Do not connect an endpoint unless you trust
its operator. Disconnecting does not delete previously received data.

## Backups and exports

Full JSON exports contain the business state and attached receipt/photo bytes;
plain JSON is not encrypted. Portable encrypted backups use AES-256-GCM with a
key derived from the user's password. The app also supports scheduled encrypted
recovery files and a user-selected document-provider destination. A chosen
provider such as a cloud drive may transfer or store a copy under its own terms.
Backup files must be deleted separately from the app. Backup passwords, Google
pairing credentials and Apps Script tokens are excluded from portable backups.

## Retention and deletion

Records remain in local storage until the user corrects them through the app's append-only history or clears/uninstalls the app. The app does not provide a
clear-all ledger control; product deletion is limited to unused products.
Uninstalling or clearing app data deletes the local ledger and app-private
recovery files; export a verified backup first.
Exported files and provider copies must be deleted at their destination. The
user can delete their spreadsheet or Apps Script receiver data in the relevant
Google account. Disconnecting Google Sheets is not a remote deletion request.

The app operator does not receive the local database through an app-owned
business backend. For help with the app or a privacy request, contact:
**[operator support email to be supplied]**. This address must be monitored
before the policy is published.

## Security and changes

Network connections for sign-in and uploads use HTTPS. App connection secrets
are stored with Android Keystore-backed or iOS Keychain-backed secure storage
provided by the platform plugin. No method of storage or transmission is
guaranteed to be risk-free. Users should share only the records needed for their
own reports and restrict spreadsheet access.

This policy must be updated when data flows, SDKs, backup behavior or supported
features change. The app is a general business record-keeping tool and is not
directed to children.

**Operator:** [legal or trading name]

**Support contact:** [email or support URL]

**Effective date:** [date]

**Public policy URL:** [HTTPS URL]
