# Business Tracker privacy policy draft

**Draft — complete the operator name, support contact, policy URL and effective
date before distribution through an app store.**

Business Tracker stores business names, product information, inventory history,
sales, expenses, refunds, notes and selected photos/receipts in the app's local
storage. No tracker account is required. Independent installations do not share
records automatically. The application does not process payment-card charges or
refunds, and does not contain advertising or commission features.

Camera permission is used when the user chooses to take a product/receipt photo or
scan a barcode. Selected photo/document access is used for imports and exports.
Receipt text recognition runs on the device through native ML Kit. Recognition
suggestions require manual review. Check the final bundled SDK versions and their
privacy manifests/disclosures before making a no-data-collection store declaration.

If the user configures Google Sheets, uploads send business records, product data,
notes and receipt metadata to the user's configured Google Apps Script/Sheet.
Receipt photos and PDF bytes are not sent by this feature. Google operates that
service under its own policies. The operator of the selected Sheet controls its
retention, sharing and deletion. Changing a local setting does not delete existing
remote rows. Pairing tokens are stored in platform secure storage.

Full backups contain records and photo/receipt bytes. JSON backups are unencrypted;
portable encrypted backups require the user's password. System file providers
selected for export may transfer files using their own services and privacy terms.
Scheduled local recovery copies remain in app-private storage. Backup passwords
are stored securely only when the user enables scheduling.

Records remain until the user removes app data or uninstalls the application.
Exported backups, selected provider files and Sheets rows must be deleted separately.
Clearing local data is destructive and should be preceded by a verified backup.
Platform keychain behaviour can retain credentials independently of the app on
some systems; final release settings must account for reinstall/reset behaviour.

TestFlight, app stores and operating systems may collect diagnostics under their
own policies. This app's final store disclosures must reflect the actual release
and its dependencies. Contact: **[operator support contact to be supplied]**.
