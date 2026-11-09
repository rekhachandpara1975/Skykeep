# SkyKeep Android app (Flutter)

| Build | Command (CI does this) | Notes |
|---|---|---|
| `SkyKeep.apk` | `flutter build apk --flavor direct` | website download, `com.skykeep.app` |
| `SkyKeep-ads.apk` | same + `--dart-define=APK_REFERRER=utm_source=meta&utm_medium=paid_social&utm_campaign=apk_download` | marks installs as ads (server decides) |
| `SkyKeep-play.aab` | `flutter build appbundle --flavor play --dart-define=PLAY_STORE=true --dart-define=ANDROID_APP_ID=com.skykeep.play` | never shows UPI, prices or the plans page |

Every build also needs `--dart-define=SUPABASE_URL=… --dart-define=SUPABASE_PUBLISHABLE_KEY=…` (public values; CI reads them from GitHub secrets).

## Release key (once)
```bash
keytool -genkeypair -v -keystore skykeep-release.jks -alias skykeep -keyalg RSA -keysize 4096 -validity 10000
base64 -w0 skykeep-release.jks
```
Add to GitHub › Settings › Secrets › Actions: `ANDROID_KEYSTORE_BASE64` (the base64 output), `ANDROID_KEYSTORE_PASSWORD`, `ANDROID_KEY_ALIAS` (`skykeep`), `ANDROID_KEY_PASSWORD`. Keep the `.jks` file and passwords safe offline — losing them means you can never update the app. Never commit it.

The CI log prints `ANDROID_SIGNING_SHA256` — put it in Vercel so `/.well-known/assetlinks.json` is correct.

## How the app decides things
It doesn't. `my_status`, `plan_offers` and RLS decide access, prices and payment results. The app shows:
- **Free mode** (or Play build): free account card, 15 GB, "Request full access" for organic users.
- **Plans hidden**: no crown, no prices; buyers still see "<plan> active until <date>".
- **Plans visible** (direct/ads): `/subscribe` in a WebView → `{type:"buy"}` → `create_order` → UPI intent (`app/upi` MethodChannel) → result saved locally first → `report_result` (retried with backoff).

## Tests
```bash
flutter analyze --fatal-infos
flutter test
flutter test --dart-define=PLAY_STORE=true test/play_build_test.dart
flutter test --tags golden --update-goldens   # after an intended UI change
```

## Phone test plan
1. Install `SkyKeep.apk` from the CI artifact; open it (guest).
2. Profile › Log in or create account › sign up; confirm the email link (it opens the app).
3. Admin: set your UPI ID, add a ₹1 test plan.
4. Profile › Go Premium › tap the cheapest plan › pay with GPay → "Payment successful! Your plan is now active.", Premium badge, 2 TB in Cloud.
5. Buy again and press back in GPay → "Payment failed or cancelled" › Try again.
6. Buy again, and while GPay is open, force-stop SkyKeep. Finish paying, reopen SkyKeep → the saved result is sent on launch; Payment history shows the order.
7. Admin › Payments › "Activated today" → compare with your bank → Bank verified.
