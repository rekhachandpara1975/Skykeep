# Google Play billing (Play build) — step by step

Google Play doesn't allow a Play-installed app to sell digital content through your own UPI or a web page.
So the Play build (`com.skykeep.play`) **never** shows your UPI page or plans WebView.

## What happens while billing is OFF (default)
- Logged-in Play users pass a **Play Integrity** check, then get the free tier (15 GB cloud).
- Plans are hidden. Premium videos say "Premium members only".
- Both switches in Admin › **Google Play** are off: `play_billing_enabled = false`, `google_approval_confirmed = false`.
  The database refuses to turn billing on before approval is confirmed.

## What happens when billing is ON
When someone taps **Subscribe**, Google shows its own sheet with the price and the choice
**"Pay with Google Play"** or **"Pay with UPI"** (User Choice Billing, India).

- **Google Play path**
  1. Google charges the user.
  2. The app sends the purchase token to the `play-purchase` edge function.
  3. The server verifies the token with Google (`purchases.subscriptionsv2`) and checks it belongs to this user. The app
     passes `obfuscatedAccountId = sha256(user id)`, never the raw id.
  4. The server acknowledges the purchase and grants the plan until Google's expiry date.
  5. Renewals, cancellations and refunds are picked up whenever the app reopens. The app sends every owned token
     again ("recover purchases").
- **UPI path (user's choice)**
  1. The app asks for the buyer's state, which Google needs for tax.
  2. It creates a normal order with Google's `externalTransactionToken` and runs your usual UPI intent flow. All UPI
     rules apply.
  3. Once the order is paid, the hourly `play-report` job reports it to Google, which is required within 24 hours.
     The report includes the pre-tax and GST amounts and is retried until Google accepts it.

## Play Console steps (do these in order)
1. **Enrol in User Choice Billing (India)**: Play Console › Monetisation setup › Alternative billing. Wait for
   Google's approval email.
2. **Create subscriptions**: Play Console › Monetise › Subscriptions. For each plan, create a product (e.g.
   `skykeep_monthly`) with a base plan (e.g. `monthly`) and set the price there.
3. **Link a Google Cloud project**: Play Console › Setup › API access.
4. **Create a service account** in that Cloud project. Invite it in Play Console › Users and permissions with
   *View financial data* and *Manage orders and subscriptions*. Enable the **Google Play Android Developer API**
   and the **Play Integrity API**, then download the JSON key.
5. **Supabase › Edge Functions › Secrets** (never paste these anywhere else):
   | Secret | Value |
   |---|---|
   | `GOOGLE_SERVICE_ACCOUNT_JSON` | the whole JSON key file |
   | `PLAY_PACKAGE` | `com.skykeep.play` |
   | `PLAY_GST_RATE` | `0.18` (your prices include 18% GST; change if your accountant says otherwise) |
6. **Supabase › Integrations › Cron › New job › HTTP request**:
   - Schedule: every hour.
   - Method and URL: POST `https://vzeehoissxdutmxdezjf.supabase.co/functions/v1/play-report`.
   - Header: `Authorization: Bearer <service role key>`.
7. **Admin › Google Play**: map each Play product and base plan to your plan.
8. Tick **"I confirm Google approved…"** and Save, then tick **"Turn on purchases"** and Save. Open Play builds
   switch over live.

Steps 3–5 alone (without 1, 2, 6–8) are enough for the Play Integrity free tier.

## Checks
- Admin › Google Play shows reports waiting or overdue (more than 20 hours) and the last error.
- Tests: `supabase/tests/004_play_billing.sql` (server rules) and `mobile/test/play_billing_test.dart` (app flow).
