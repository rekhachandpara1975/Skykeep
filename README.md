# SkyKeep

Cloud storage + creator channels. Android app, admin panel and website on Supabase.

| Folder | What |
|---|---|
| `supabase/` | migrations (all rules enforced with RLS + security-definer functions), pgTAP tests, edge functions, seed |
| `admin/` | Next.js admin panel (`/admin`) and public website (`/`, `/subscribe`, `/d`, policies) — deployed on Vercel |
| `mobile/` | Flutter Android app (direct APK, ads APK, Play AAB) |
| `docs/` | [setup](docs/setup.md) · [payments](docs/payments.md) · [rules](docs/rules.md) · [Play Store build](docs/play-store.md) · [admin](docs/admin.md) |

Payments: only your own UPI intent flow, in the website and ads APKs. No gateway, no Google Play Billing; the Play Store build never sells anything.

## Local checks
```bash
cd supabase/local-check && npm i && node run.mjs   # migrations + pgTAP on PGlite (no Docker)
cd admin && npm ci && npm run lint && npm run typecheck && npm run build
cd mobile && flutter pub get && flutter analyze && flutter test
```
