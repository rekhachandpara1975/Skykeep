# How UPI payments work

No gateway, no card form, no Google Play Billing. The app opens a UPI app with your UPI ID; money goes straight to your bank.

## Flow
1. The app shows `/subscribe` in a WebView. Tapping **Pay ₹X with UPI** sends `{type:"buy", plan_id}` to the app.
2. App calls `create_order(plan_id)`. The database copies the **current** price, duration, UPI ID and payee name into the order and makes a reference like `SK20261109A1B2C3D4`. If the price changed since the page loaded, the app shows "Price updated to ₹X" first.
3. App opens `upi://pay?pa=<upi>&pn=<payee>&tr=<reference>&am=<amount>&cu=INR&tn=SkyKeep <reference>`.
4. The UPI app returns a string (`Status=SUCCESS&txnId=…&txnRef=…`). The app saves it locally first, then calls `report_result`.
5. The server saves the raw string first, then decides:
   - `FAILURE` → **failed**
   - `SUCCESS` is accepted only if `txnRef` equals the reference, the transaction id is 6–40 letters/digits and never seen before, and the order is less than 2 hours old.
   - Accepted + **Instant** mode → **paid**, plan active right away (unless that user already had 3 automatic activations in 24 h → **review**).
   - Accepted + **Manual** mode → **review**; you approve after checking your bank.
   - Anything else → stays **pending** (shown to you as `submitted` if it claimed SUCCESS).
6. Pending orders older than 24 h are cancelled automatically (orders that reported SUCCESS are kept for you to check).

UPI result strings can be faked on a rooted phone. That is why the bank check below matters.

## Daily bank check (5 minutes)
1. Admin › Payments › filter **Activated today — verify against bank**.
2. Open your bank app/statement. For each row, find a credit with the same amount and the UTR / transaction id shown.
3. Found → **Bank verified**. Not found by the next day → **Revoke** (plan ends immediately).
4. **Needs review**: find the payment in the bank → **Approve** (or type the 12-digit UTR and **Mark paid**). Not there → **Reject**.

## Changing your UPI ID
Saving a new UPI ID applies to new orders only. Unpaid pending orders for the old ID are cancelled the next time that user taps Buy. **Clear UPI ID** turns payments off everywhere instantly.

## Organic buyers
Users who did not come from an ad get the plan at once: 2 TB storage plus full premium videos in the content they can already see. Only **ads-audience** channels and posts wait for your approval in Admin › Approvals. See `rules.md`.

## Refunds
Refund by UPI from your bank app to the payer, then **Revoke** the order.
