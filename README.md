# 0xda-market Client Bot

Private Telegram client for `0xda-market`.

Commands:

- `/start` — passwordless Telegram authentication;
- `/status` — current persisted role and account status; the response is removed
  after three seconds;
- `/buy` — open the nine-product catalog (authenticated client context only);
- `/servers` — health and UTC server time for market core and client bot (admin only);
- `/users` — active Telegram users for administrators;
- `/setadmin @username` or `/setadmin TELEGRAM_ID` — promote a registered user.

`/users` shows only Telegram ID, internal UUID and role. The default Telegram
command scope contains only `/start`. After authentication, clients receive
`/buy` and `/status`; an admin
receives a private chat scope that also contains `/servers`, `/users` and
`/setadmin`; clients do not see or execute these admin commands. The core still
verifies the persisted admin role for every assignment.

`/buy` loads the active catalog from `GET /v1/products` and renders the first
nine products as a 3×3 inline keyboard. Product callbacks use the stable
`buy_<sku>` contract. The bot never hardcodes catalog rows and never connects to
PostgreSQL directly.

## Environment

- `TELEGRAM_BOT_TOKEN` — token for `@zeroxda_market_client_bot`
- `TELEGRAM_WEBHOOK_SECRET` — generated random webhook secret
- `MARKET_API_URL` — defaults to `https://zeroxda-market.onrender.com`
- `MARKET_API_TOKEN` — the backend `PUBLIC_API_TOKEN`
- `RENDER_EXTERNAL_URL` — canonical service URL supplied automatically by Render

Secrets must be configured in Render and must not be committed. Outside Render,
`PUBLIC_URL` remains available as a local fallback.
