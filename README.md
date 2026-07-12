# 0xda-market Client Bot

Private Telegram client for `zeroxda-market`.

Commands:

- `/start` — passwordless Telegram authentication;
- `/status` — health and UTC server time for market core and client bot;
- `/users` — active Telegram users for allowlisted administrators.

`/users` shows only Telegram ID, internal UUID and role. It is protected by
`ADMIN_TELEGRAM_IDS`, a comma-separated list of numeric Telegram user IDs.

## Environment

- `TELEGRAM_BOT_TOKEN` — token for `@zeroxda_market_client_bot`
- `TELEGRAM_WEBHOOK_SECRET` — generated random webhook secret
- `MARKET_API_URL` — defaults to `https://zeroxda-market.onrender.com`
- `MARKET_API_TOKEN` — the backend `PUBLIC_API_TOKEN`
- `ADMIN_TELEGRAM_IDS` — administrators allowed to run `/users`
- `RENDER_EXTERNAL_URL` — canonical service URL supplied automatically by Render

Secrets must be configured in Render and must not be committed. Outside Render,
`PUBLIC_URL` remains available as a local fallback.
