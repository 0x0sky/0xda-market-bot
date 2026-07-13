# 0xda-market Client Bot

Private Telegram client for `0xda-market`.

Commands:

- `/start` — passwordless Telegram authentication;
- `/status` — health and UTC server time for market core and client bot (admin only);
- `/users` — active Telegram users for administrators;
- `/setadmin @username` or `/setadmin TELEGRAM_ID` — promote a registered user.

`/users` shows only Telegram ID, internal UUID and role. The default Telegram
command scope contains only `/start`. After authentication, an admin receives
a private chat scope that also contains `/status`, `/users` and `/setadmin`;
clients do not see or execute these admin commands. The core still verifies the
persisted admin role for every assignment.

## Environment

- `TELEGRAM_BOT_TOKEN` — token for `@zeroxda_market_client_bot`
- `TELEGRAM_WEBHOOK_SECRET` — generated random webhook secret
- `MARKET_API_URL` — defaults to `https://zeroxda-market.onrender.com`
- `MARKET_API_TOKEN` — the backend `PUBLIC_API_TOKEN`
- `RENDER_EXTERNAL_URL` — canonical service URL supplied automatically by Render

Secrets must be configured in Render and must not be committed. Outside Render,
`PUBLIC_URL` remains available as a local fallback.
