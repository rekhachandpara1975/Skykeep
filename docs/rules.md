# SkyKeep — access rules (plain words)

This page is the single source of truth. Every rule is enforced in the database (RLS + security-definer
functions), never only in the app. Tests: `supabase/tests/003_content_matrix.sql` checks every cell below.

## Who is "ads" and who is "organic"
- Decided **once**, on the first app open, and never changes, not even by an admin.
- **Ads**: the install referrer / APK referrer has `utm_source` = meta, facebook, instagram or ig (any case).
  The ads APK (`SkyKeep-ads.apk`) has this referrer built in.
- **Organic**: everything else (website APK, Google Play installs, no referrer).
- A guest who logs in or signs up keeps the same account and the same source.

## Who can see what
Channels, posts and items each have an **audience** (`all`, `organic`, `ads`). Items can be **premium**.

| Content | Guest | Organic member | Ads member |
|---|---|---|---|
| audience = all, free | ✅ | ✅ | ✅ |
| audience = organic, free | ✅ if the guest is organic | ✅ | ❌ hidden |
| audience = ads, free | ❌ hidden | only with **full access** (you approved them) | ✅ |
| premium item | trailer / preview | **paid mode:** full with an active plan · **free mode:** full only with full access | **paid mode:** full with an active plan · **free mode:** always full |
| downloads | ❌ | same as premium | same as premium |

**Full access** = ads members always; organic members only when you **approved** them *and* (free mode is on *or*
they have an active plan).

- Admins see everything.
- Hidden content is never sent to the phone at all; it isn't just hidden in the app.
- Videos and files are only served through short-lived signed links, and only when the rule above allows it.

## Modes (Admin › Plans; apps update live)
- **Free mode ON**: no prices or payments anywhere. Logged-in users get 15 GB cloud. Ads members get full access.
  Organic members can tap **Request full access**; you approve or reject in Admin › Approvals.
- **Free mode OFF (paid mode)**: plans and payments, following the rules below.
- **Show plans to** everyone / ads only / organic only / nobody. Hidden users see no prices, no Premium button and
  no "buy" prompts, and the server refuses their orders. People who already bought still see their active plan.
  Admins always see plans.
- **Free plans for** none / organic / ads / everyone, on plans marked "free eligible". A free plan can be claimed
  once per user, per plan, per promotion. It needs a login and no active plan, and it creates no payment record.
  Organic claimers still need your approval for full access.

## Payments
- Prices and durations come only from the server when the order is created. A price change only affects new orders.
- An organic user buys a plan → the plan is active and full access becomes **pending** until you approve.
  An ads user gets full access straight away.
- One subscription per order (paying twice for the same order never grants twice). Renewals extend from the
  current end date.
- Every subscription records where it came from: `upi_app`, `admin`, `free_promo` or `provider_api`.

## Builds
| Build | Package | How people pay |
|---|---|---|
| Website APK | `com.skykeep.app` | Your UPI (plans page inside the app) |
| Ads APK | `com.skykeep.app` + ads referrer | Your UPI |
| Google Play | `com.skykeep.play` | **Never sells anything** (Google doesn't allow your own UPI checkout in Play apps). Free tier only: 15 GB after the Play Integrity check; Premium screens say "Premium members only". See `play-store.md`. |
