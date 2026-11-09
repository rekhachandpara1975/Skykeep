# Google Play build — what stays off and why

Google Play forbids steering users to outside payment methods (like UPI intents) unless you are enrolled in **User Choice Billing**. So the Play build (`com.skykeep.play`):

- never shows UPI, prices, the plans WebView or the crown;
- gives 15 GB free cloud after a **Play Integrity** check (`play_integrity_challenge` → app gets a token → `play-verify` edge function → `enable_play_free_cloud`);
- has User Choice Billing code ready but switched off.

## Database switches (Admin can't flip these by accident)
`play_settings.play_billing_enabled = false` and `google_approval_confirmed = false`. The database refuses `play_billing_enabled = true` unless `google_approval_confirmed` is already true.

## Before turning billing on
1. Apply for User Choice Billing in Play Console (India) and get approval.
2. Create subscription products in Play Console; map them in `play_products (product_id, plan_id)`.
3. Create a Google Cloud service account with **Android Publisher** and **Play Integrity** access, link it in Play Console › API access, and store its JSON as the Supabase secret `GOOGLE_SERVICE_ACCOUNT_JSON`. Set `PLAY_PACKAGE = com.skykeep.play`.
4. Schedule `play-report` daily (reports alternative-billing transactions to Google, required by the program).
5. In SQL: `update play_settings set google_approval_confirmed = true;` then `update play_settings set play_billing_enabled = true;`
6. Release a new Play build — the app reads `play_billing_enabled` from `my_status` and shows Google's choice screen.

Until then, Play Integrity only needs step 3 (service account) to grant 15 GB.
