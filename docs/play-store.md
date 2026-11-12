> **Owner's decision (Nov 2026):** the Play build (`SkyKeep-play.aab`) now also sells plans through the owner's UPI
> (`--dart-define=PLAY_SELLS_UPI=true`). Google Play's Payments policy requires Google Play Billing for digital
> goods (India allows other billing only *alongside* Play Billing after enrolment). Expect review rejection or
> warnings; to go back to the policy-safe build, remove `PLAY_SELLS_UPI=true` from `.github/workflows/mobile.yml`.

# Play Store build (`com.skykeep.play`)

Premium is sold **only** through your own UPI intent checkout, in the website APK and the ads APK.
Google Play doesn't allow a Play-installed app to sell digital content through your own UPI or a web page, so the
Play Store build **never sells anything**:

- No plans, prices, crown, "Go Premium" or plans page.
- Logged-in users pass a **Play Integrity** check (`play-verify`) and get the free **15 GB** tier.
- Premium videos and downloads say "Premium members only". People who bought Premium through the website APK and log
  in with the same account still get Premium in the Play build, because entitlement lives on the server.
- There is no Google Play Billing code or library in the app. The database refuses to turn billing on
  (`play_billing_never` check).

## What you need for the Play build
- Supabase secrets: `GOOGLE_SERVICE_ACCOUNT_JSON` (a service account with access to the Play Integrity API) and
  `PLAY_PACKAGE=com.skykeep.play`.
- Play Console › App content › **In-app purchases: No**.
- Don't link to your UPI page or website plans from the Play listing or inside the Play app.

Tests: `supabase/tests/004_play_store_build.sql` and `mobile/test/play_build_test.dart`.
