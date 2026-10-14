# Google Sheets uploads

This feature works independently of Stripe. Cash/manual sales, stock changes and corrections upload to a dedicated Google Sheet. Receipt photos and pairing secrets are not uploaded. The phone database remains authoritative.

## One-time connection

1. Create a private Google Sheet (for example **Drinks Business**) in your Google account. Open **Extensions → Apps Script**.
2. Replace the starter script with `sheets/Code.gs` from this repository.
3. In Apps Script **Project Settings → Script Properties**, add `SPREADSHEET_ID` (the part between `/d/` and `/edit` in your Sheet URL), and `SYNC_TOKEN` (a new random secret at least 32 characters). Generate a token with a password manager. Never commit it to GitHub.
4. Deploy a **Web app**, executing as your account, access **Anyone**. Authorize access to your spreadsheet. The endpoint is reachable publicly, but it rejects requests without your private token; the spreadsheet itself stays private. If your Google account disallows this deployment, this connection method will require a permitted account or a different integration.
5. Copy the deployment URL ending in `/exec`. In the app's **Settings → Connect / configure Google Sheets**, enter this URL and your token. Choose whether automatic uploads are enabled. Saving queues an initial upload of existing records.
6. Use **Upload now** and confirm the rows in the Sheet. Do not share the deployment token. To revoke access, change `SYNC_TOKEN` in script properties and update the phone.

## Manual and automatic behavior

- **Upload now** attempts an upload immediately. If offline it reports failure without altering local records; with automatic sync enabled, background retries continue.
- Automatic mode requests a network-constrained job after local operations. Android controls when it runs and can defer it for battery/network reasons. A 15-minute periodic safety job catches saves made during an existing upload; it is not an exact schedule.
- Jobs persist across reboot. Force-stopping the app pauses scheduling until reopening. Disabling automatic mode cancels the periodic job; an already queued initial/manual upload may still finish.
- Refresh sync status in Settings to see pending records, last success and errors. Pending count reflects local records not covered by the last fully acknowledged upload, not remote manual edits.
- Uploads resend records in batches of 100. The receiver locks writes and deduplicates by transaction ID, so retries after partial uploads or lost responses do not create duplicates. Conflicting IDs are rejected rather than overwritten.
- Keep the **Transactions** tab as a receiver-managed audit log. Do not edit/delete its rows or hidden Source JSON column. Add separate tabs for your own reports. Undo/correction rows identify the original transaction in **Corrects ID**; raw column sums do not automatically reverse corrections.
- Amounts are numeric AUD values converted from integer cents. Dates are UTC ISO strings; unknown opening dates stay blank. Notes are escaped to prevent spreadsheet formulas.
- JSON backups remain necessary: Google Sheets is a transaction mirror, not a complete app/receipt backup.

No Sheet or live deployment is created by installing the APK. The steps above must be completed in your account before uploads can run. Google Apps Script quotas apply.

## Validation

Run `node sheets/receiver.test.mjs` for receiver contract tests. Build/install the APK and verify: manual upload twice without duplicate rows; automatic upload after a cash sale; offline sale followed by reconnect; correction upload; backup import; reboot retry; token rejection; and no local data changes on failure.
