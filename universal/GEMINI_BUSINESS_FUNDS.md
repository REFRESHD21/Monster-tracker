# Gemini tool contract: Business Tracker funds

The Supabase Edge Function `business-funds` exposes the narrow balance-adjustment
operation a Gemini-enabled server can call. It changes **only the Business Tracker
funds ledger**. It does not edit sales, stock, products, receipts, customer records,
bank accounts or cash-on-hand records.

## Authentication boundary

Send the current Supabase **access token for the signed-in JTC Drinks admin** as
`Authorization: Bearer <access-token>`, plus the project's public Supabase
`apikey` header. The Edge Function verifies the session, and the database RPC
checks that the user is an authorised admin and owns the registered
`business_id`.

A Gemini tool must call this endpoint from trusted server-side code using the
active admin session. Do not put an access token, refresh token, service-role key,
or other credential in a Gemini prompt, model context, browser bundle, or
`NEXT_PUBLIC_*` variable. The publishable/anon key is public and is not an
authorisation credential.

## Function declaration

A Gemini function-calling client can expose this function:

```json
{
  "name": "adjust_business_tracker_balance",
  "description": "Adjust only the Business Tracker funds balance. Use add for money received, remove for money taken out, and recount when the user has physically counted the funds. Never infer an amount or use this for bank-account balances.",
  "parameters": {
    "type": "OBJECT",
    "properties": {
      "business_id": {
        "type": "STRING",
        "description": "The registered Business Tracker businessId for this admin."
      },
      "action": {
        "type": "STRING",
        "enum": ["add", "remove", "recount"]
      },
      "amount_cents": {
        "type": "INTEGER",
        "description": "AUD cents. For recount, the full counted balance, not the difference."
      },
      "note": {
        "type": "STRING",
        "description": "Short reason supplied by the user."
      },
      "id": {
        "type": "STRING",
        "description": "A stable unique idempotency ID reused for retries of the same adjustment."
      }
    },
    "required": ["business_id", "action", "amount_cents", "id"]
  }
}
```

## HTTP call

`POST https://jmuxmgsbmnyqmetakhua.supabase.co/functions/v1/business-funds`

Headers:

- `apikey: <Supabase publishable/anon key>`
- `Authorization: Bearer <signed-in admin access token>`
- `Content-Type: application/json`

Example body:

```json
{
  "business_id": "00000000-0000-0000-0000-000000000000",
  "action": "add",
  "amount_cents": 500,
  "note": "Cash added to the business funds",
  "id": "gemini-adjustment-unique-id"
}
```

Use the real `business_id` from the connected Business Tracker installation;
the UUID above is only a format example. The response contains the inserted
entry result and the new balance snapshot.

- `add`: adds the positive amount to the current balance.
- `remove`: subtracts the positive amount from the current balance.
- `recount`: sets the balance to the entered counted amount by appending the
  difference as a ledger entry; previous entries are never edited or deleted.

Amounts are integer AUD cents. Do not convert to dollars in the request. Ask the
user to clarify any ambiguous action or amount before calling the function.
Reuse the same `id` if a network retry is needed; do not generate a new ID for a
retry of the same action.

## Integration status

The endpoint and database-side admin/ownership checks are deployed. The Flutter
app can upload local funds history and pull these adjustments back into its local
ledger on sync. This document is the function-calling contract; a Gemini client
still needs to register the declaration and implement the authenticated server
call. The endpoint alone does not make the standalone Gemini app able to access
the account.
