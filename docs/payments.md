# How UPI payments work

UPI only: no gateway, no cards, no wallets. The app opens a UPI app with your UPI ID and the money goes straight to your bank.
**The server decides, never the phone.** No plan is ever activated because a phone said "SUCCESS". You approve every payment
after you see it in your bank.

## Flow
1. **Plans page:** the app shows `/subscribe` in a WebView. Each plan says "You will pay ₹X to <payee>". Tapping
   **Pay ₹X with UPI** sends `{type:"buy", plan_id}` to the app.
2. **Order:** the app calls `create_order(plan_id)`.
   - The database copies the **current** price, duration, UPI ID and payee name into the order.
   - It makes a reference like `SK20261112A1B2C3D4` and an expiry time of **30 minutes**.
   - One open order per user per plan: a double tap reuses it. There's a limit of 10 new orders per hour per user.
   - If the price changed since the page loaded, the app shows "Price updated to ₹X" first.
   - A Meta `InitiateCheckout` event is queued.
3. **UPI app:** the app opens `upi://pay?pa=<upi>&pn=<payee>&am=<amount>&cu=INR&tn=SkyKeep <reference>&tr=<reference>`
   (every value URL-encoded) through Android's "Pay with" chooser.
   - If no UPI app can open it, the app shows a **QR code** of the same link plus **Copy** buttons for the UPI ID, amount
     and reference.
   - The status screen always offers "Pay with QR code" too, because some UPI apps refuse intent payments to personal UPI IDs.
4. **Answer from the UPI app** (`Status=…&txnId=…&txnRef=…&ApprovalRefNo=…`): the app saves it on the phone first, then
   calls `report_result`. If the app is killed meanwhile, it is retried on the next launch, and the Premium banner shows the
   open order again. The server saves the raw text first, then:
   - `FAILURE` → **failed**.
   - `SUCCESS` with the right reference, a new transaction id and an order under 24 hours old → **review** (shown as
     "Verifying").
   - `SUBMITTED` / `PENDING` / cancelled / no data / garbage → stays **waiting**. The app shows **I have paid**.
5. **I have paid:** the buyer types the **12-digit UTR** from their UPI app's history, with an optional screenshot (private
   storage, only the buyer and you can see it). `submit_payment_proof` checks:
   - the format,
   - that the UTR was never used on another order (a database rule),
   - that the order is under 24 hours old (late proof for an expired order is accepted),
   - a limit of 10 attempts per hour.
   The order then goes to **review**.
6. **You verify** in Admin › Payments › **To verify**:
   - **Approve** runs in one transaction: it checks the order and UTR, marks it paid, grants the plan (2 TB + Premium until
     the end date) and logs who did it. Approving twice does nothing extra.
   - **Reject** asks for a reason, which is logged.
   - **Mark paid** is for when you find the payment in your bank before the buyer sends a UTR.
7. **Expiry:** unpaid orders expire after **30 minutes** (a job runs every 5 minutes). The app says "This order expired —
   start again" and still offers **I have paid** for 24 hours.
8. **History:** every status change is stored in `payment_order_events` (who, when, old → new). It's shown under
   **Details** in Admin › Payments and as the payment history in the app (reference, UTR, date, amount).

Status names: **pending** = waiting for payment, **review** (or `submitted`) = verifying, **paid**, **expired**,
**failed**, **rejected**, **cancelled**, **revoked**.

Google Play: the Play Store build never shows this checkout and has no Google Play Billing; it is free tier only (`play-store.md`).

## Automatic verification (bank SMS)
Plans activate **automatically within seconds** when your bank's own credit SMS confirms the payment. The phone's
"SUCCESS" is never trusted on its own.

How it matches (server side, `bank_credit_received` → `match_credit`):
1. **UTR match:** the bank SMS's UTR equals the order's UTR (sent by the buyer's UPI app, or typed by the buyer under
   "I have paid") and the amount is exactly the order amount → **paid**.
2. **Amount match:** no order has that UTR, and **exactly one** open order (created in the 2 hours before the credit)
   has that exact amount → **paid**. If two or more do, it waits for the buyer's UTR or for you.
3. **Wrong amount** → the order goes to **To verify** with a note. Never automatic.
4. **SMS arrives first** (the buyer hasn't typed the UTR yet) → it is stored, and the plan activates the moment the
   buyer's UTR arrives.

The same SMS twice does nothing, and a UTR can be used for only one order. Admin › Payments › **Bank SMS auto-verify**
shows every credit received and what it matched.

### Set it up (once)
1. **Choose a secret key**: any long random text, e.g. 30+ letters and numbers. Add it in Supabase › Edge Functions ›
   Secrets as `BANK_SMS_KEY`. Optionally also add `BANK_SMS_SENDERS`, part of your bank's SMS sender name, e.g.
   `BANDHN`, so other senders are ignored.
2. On the Android phone that has the **SIM registered with your bank account**, install an **SMS-forwarder** app
   that can send SMS to a webhook URL (several free ones are on the Play Store; look for "SMS to URL" or
   "SMS forwarder webhook").
3. In that app, add a rule:
   - **Sender contains:** your bank's sender ID (e.g. `BANDHN`).
   - **Webhook URL:** `https://vzeehoissxdutmxdezjf.supabase.co/functions/v1/bank-sms?key=YOUR_BANK_SMS_KEY`
   - **Method:** POST. **Body:** the SMS text (JSON `{"text":"%text%","from":"%from%"}` or the app's default).
4. Turn off battery optimisation for that app, so Android doesn't stop it.
5. Test: pay ₹1 to your own UPI ID from another app. Admin › Payments › Bank SMS auto-verify should show the credit
   within seconds.

If the phone is off or the app is stopped, nothing breaks: orders simply wait under **To verify** as before.

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

## Phone test checklist (do this once with a real phone and ₹1–₹10)
1. Install `SkyKeep.apk`, sign up, open Premium → the plan says "You will pay ₹X to <your payee name>".
2. Pay with GPay. The status screen shows **Verifying**, and no Premium yet.
3. Admin › Payments › To verify → find the credit in your bank → **Approve**. Within seconds the app shows
   "Payment successful! Your plan is now active", Premium badge and 2 TB.
4. Start another order and cancel in the UPI app → **Waiting for payment** with **I have paid** / **Pay with QR code**.
5. Tap **I have paid**, type a wrong 5-digit UTR (button stays off), then the real UTR → **Verifying**.
6. Type a UTR that was already used → "This UTR was already used for another payment".
7. Start an order, kill the app while the UPI app is open, pay, reopen the app → the banner shows the open payment;
   Payment history lists it.
8. Wait 30 minutes on an unpaid order → "This order expired" + **Try again**.
9. Uninstall all UPI apps (or use an emulator) → QR code + Copy buttons appear.
