# Monster stock & sales PWA

Implemented app, not a Google Form. Node 24+, no npm dependencies. **Not deployed; live OAuth and Google Sheets writes are not yet verified.**

The source workbook's Dashboard, Log and Setup were inspected on 12 October 2026. Dashboard showed 24 bought for AUD 50 and 20 remaining. Log row 2 already records four missing with an unknown date; no sales were present in the inspected rows. No workbook cells were changed during development. App initialization rereads all three tabs and the entire supported Log range and refuses to import if that opening state has changed.

## Deploy from an Android phone

The provided `render.yaml` describes a single Node service with a persistent disk. Render's disk-backed service requires a paid plan; confirm its current price in the dashboard. Do not deploy this database on ephemeral storage or multiple instances. A host with Node 24+, persistent storage and HTTPS can also run it using `npm start` or the supplied Dockerfile.

1. Download and extract `monster-tracker.zip` with Android Files.
2. Open https://github.com in Chrome (Desktop site if needed), create a **private** empty repository, and upload the ZIP to it using **Add file → Upload files**. Create a GitHub Codespace from **Code → Codespaces → Create codespace on main**. In its browser terminal run:

   ```sh
   unzip monster-tracker.zip
   cp -a monster-tracker/. .
   rm -rf monster-tracker monster-tracker.zip
   git add .
   git commit -m "Add private Monster sales PWA"
   git push
   ```

   This ZIP contains only app source, tests and documentation, not credentials or a live database. Codespaces availability depends on your account. You can instead upload the extracted files with a Git client; preserve the `public` and `test` folders.
3. Open https://dashboard.render.com, connect that private repository, and create a **Blueprint** using `render.yaml`. Use one instance and keep the `/var/data` disk. Set the environment values below; never add them to GitHub files. The initial service can boot before OAuth is configured, but recording remains locked.
4. Use the HTTPS address assigned by Render as `APP_ORIGIN`, with no trailing slash. Set `OWNER_EMAIL` to the Google account that owns or can edit your Sheet. Do not change the Sheet's sharing to public.
5. For `TOKEN_ENCRYPTION_KEY`, generate a random 32-byte base64 key in your private Codespace terminal:

   ```sh
   node -e "process.stdout.write(require('crypto').randomBytes(32).toString('base64'))"
   ```

   Copy it only into Render's environment setting. It encrypts the refresh token in SQLite. Keep it stable and private. Do not commit it or paste it into a chat.
6. Configure Google OAuth as described below, add `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` in Render, and redeploy.
7. Open your service URL in Android Chrome. Tap **Sign in with Google**, authorize your own account, then **Connect existing Sheet**. This explicitly imports the existing opening state, extends Log with ID metadata, updates the Dashboard restock formulas and replaces the old Form setup text with app instructions. The existing opening row A:I and its blank historical date are preserved.

The Sites publishing helpers and hosted connector eligibility tool were unavailable in the authoring environment; no Sites project was created or deployment claimed. Render deployment is an alternative you must complete in your account, not a verified deployment.

## Google OAuth: exact settings

In https://console.cloud.google.com (Android Chrome's **Desktop site** may make these screens easier):

1. Create/select a project. Go to **APIs & Services → Library → Google Sheets API → Enable**.
2. In **Google Auth Platform**, configure Branding, Audience and Data Access. Choose **External**, keep publishing status **Testing**, and add only `OWNER_EMAIL` as a test user. Add scopes `openid`, `email`, and `https://www.googleapis.com/auth/spreadsheets`.
3. Under **Clients**, create an OAuth client with application type **Web application**. Add the service origin as an authorized JavaScript origin and add this exact authorized redirect URI:

   ```text
   https://YOUR-SERVICE.onrender.com/auth/callback
   ```

4. Copy its client ID and secret into Render's environment settings, not frontend code. Ensure `APP_ORIGIN` matches the same HTTPS origin exactly. Save and redeploy.
5. Sign in from the app. The server exchanges the code, checks Google's verified email against `OWNER_EMAIL`, encrypts the refresh token and creates an HttpOnly/Secure/SameSite session. Google tokens never go to browser JavaScript. Other Google accounts cannot access records.

External apps in Testing can have short-lived refresh tokens (often seven days for these scopes); use **Sign in with Google** again when authorization expires. Pending data is retained. Session state resets after server restart, so signing in again may be necessary. Moving OAuth to Production may require Google's review; it is not required to test privately with your own test account.

## Verify live sync before relying on it

This has **not** been done during development. The automated Sheets tests use a fake adapter and are not evidence of real Google access.

1. After initialization, confirm **20 available**, **4 missing**, **$0 revenue**, **−$50 cash result**. Log row 2's date must remain blank; J2 should contain `opening-missing-v1`.
2. Add a real sale if one occurred, or use a temporary test restock of 1 can costing $0 with the note `SYNC VERIFICATION — undo immediately`.
3. Tap **Sync now**. Do not consider it verified until the record says **synced**. The server writes to a stable reserved Log row and reads back all 15 stored values before marking it synced.
4. Open the Sheet and confirm the same unique event ID in column J, UTC timestamp in K, Perth time in A, quantity, amount and note. Repeated **Sync now** taps must leave one record for that ID.
5. Undo the temporary test restock, sync again, and check its new correction row references the original ID in O. Stock should return to 20 and the original record must remain.
6. With the app installed and opened at least once online, enable airplane mode, record a sale that actually occurred, close/reopen the app, and confirm the pending entry remains. Disable airplane mode and reopen/tap **Sync now**. Verify its ID appears once in the Sheet. Undo any testing-only entry.

If you have recorded additional activity directly in the Sheet before initialization, the app intentionally refuses the initial import rather than erasing it or making up dates. Reconciliation is then required. After initialization, use the app for changes. Direct row insertion/deletion/editing in Log can break row reservations; a conflicting occupied row stops sync without overwriting it. Keep the disk-backed SQLite file and its backups: event IDs and reserved rows depend on that database.

## Android installation

Once deployed and configured, open the **HTTPS app URL in Chrome**, sign in and initialize. Tap the app's **Install app** button when available, or Chrome **⋮ → Add to home screen → Install**. The green M icon opens the app in standalone mode. Open once online before going offline so the service worker can cache its shell. Reopen the app online to flush pending entries; background sync while the app is closed is not promised.

## Behavior and limits

- Prices default to $3.50 single and $6 deal. Settings affect future sales only. Enter the actual fee before the next card sale; the fee resets after recording. Card records payment only.
- Each new event stores a UUID, actual event timestamp, Perth representation, type, quantity, payment, revenue, fee, note and purchase cost. Opening purchase and missing adjustment keep null dates. Stored sale revenue is the price snapshot.
- Cash result is total revenue less actual fees and all stock purchases, matching the existing workbook's definition; it is not cash drawer balance or profit allocated only to sold cans.
- Undo appends a reference to an original event and reverses its effects without deletion. To correct payment, price, fee or quantity, undo and re-enter. Undoing restock is refused if stock would become negative.
- Stock is checked on the phone and again on the server. Offline activity from two phones cannot reserve stock globally: the first accepted request wins and an overselling request fails visibly. **Cancel rejected** retains the rejected original in the exported audit backup; then enter the valid correction.
- Offline entries and price preferences live in IndexedDB. Accepted events live in SQLite, with pending/synced/failed Sheet state. After lost replies, the original UUID is retried. The server checks content on duplicate IDs and uses deterministic Sheet rows with read-before-write and readback, so retries do not append duplicates.
- Export a phone backup before clearing storage. Back up the server disk through your host as well. This version has JSON export, not a backup-import UI. Browser storage failure is reported rather than acknowledged as a saved entry.
- The interface/shell is downloadable; business records are protected by owner-only server authorization. Offline records on the device remain visible to anyone who can unlock that phone. Protect the phone itself.

## Test results

`npm test` runs 12 automated checks: opening stock and unknown dates; sale/fee/restock arithmetic; stock limits; traceable undo and duplicate correction prevention; restock reversal limits; missing correction workbook fields; historical price/Perth time; retry after a lost Sheet reply; conflict and readback failure handling; offline restart/reconnect; durable-storage failure; and private HTTP routing/PWA asset delivery.

All 12 passed. HTTP route tests invoke the real handler in memory because this environment denied binding a listening port. No Android/browser installation test, real OAuth flow, deployed HTTPS check, or live Google write/readback has been completed. `node --check` also passed for server and frontend modules.
