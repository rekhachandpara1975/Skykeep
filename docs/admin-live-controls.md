# Admin action → what the app does

Changes reach open apps in seconds (Realtime on `app_mode`, `plans`, `plan_catalog`; apps also poll `my_status`).

| Admin action | Effect in the app |
|---|---|
| Plans › Free mode ON | No prices anywhere. Premium tab becomes a free account card. Members get 15 GB. Ads users get full videos. Organic users see **Request full access**. `create_order` refuses. |
| Plans › Free mode OFF | Paid mode: crown + Premium web page return for users who may see plans. |
| Plans › Free plans: Organic / Ads / Everyone | Matching users see **FREE** on eligible plans; tapping activates without payment (once per promotion). Off → normal prices. Turning it on again starts a new promotion. |
| Plans › Show plans in app: Ads only / Organic only / Nobody | Hidden users: no crown, no Premium tile, no prices; premium content says "for Premium members". Existing subscribers still see their plan and payment history. |
| Plans › edit price/duration | New orders only. If the page showed an old price, the app shows "Price updated to ₹X". |
| Plans › untick Show in app | Plan disappears; tapping a stale button shows "This plan is no longer available". |
| Payments › Save UPI ID | New orders pay to the new ID. |
| Payments › Clear UPI ID / untick Payments enabled | Premium page shows "Payments are paused" (`paused=1`); buy buttons disabled. |
| Payments › Manual mode | Every payment shows "Payment received, being verified" until you approve. |
| Payments › Mark paid / Approve | User's status flips to "Payment successful! Your plan is now active." on next refresh. |
| Payments › Revoke | Plan ends now; Premium badge and 2 TB quota disappear. |
| Approvals › Approve | Organic user gets full videos and ads-audience channels. |
| Channels › Approve (+ audience) | Creator's channel goes live for that audience; creator can upload. |
| Channels › Hide / Requests › Hide content | Disappears from the app for everyone except admins. |
| Users › Grant | Adds a plan for N days (stacks on the current end date). |
| Requests › Delete account | Account and files removed; payment records kept (no name) for tax. |
| Meta Pixel › Send events | Queued Lead / CompleteRegistration / Purchase events go to Meta every 5 min. |
| Meta Pixel › Upload ads APK | `/d` download button serves the new APK. |
