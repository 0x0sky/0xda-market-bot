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

## Environments

Two Telegram bots and two Render services map one-to-one onto the two
market cores. Environment variables on a bot service are static: a service
never switches environments, only code moves between branches.

| | test | production |
| --- | --- | --- |
| Git branch | `master` | `release` |
| Telegram bot | test bot (separate BotFather token) | `@zeroxda_market_client_bot` |
| `MARKET_API_URL` | `market_test` service URL | `market` service URL |
| `MARKET_API_TOKEN` | `PUBLIC_API_TOKEN` of `market_test` | `PUBLIC_API_TOKEN` of `market` |
| Supabase | `0xda-market-test` (via core) | `0xda-market` (via core) |

Code reaches production only through the "Promote to production" GitHub
workflow, which fast-forwards `release` to `master`. Render deploys each
service from its branch; enable "Auto-Deploy: After CI Checks Pass" on both
services so a red build never ships.

## Environment variables

- `TELEGRAM_BOT_TOKEN` — token of this environment's Telegram bot
- `TELEGRAM_WEBHOOK_SECRET` — generated random webhook secret
- `MARKET_API_URL` — this environment's market core URL; defaults to
  `https://zeroxda-market.onrender.com` (production core) when unset, so the
  test service must set it explicitly
- `MARKET_API_TOKEN` — the `PUBLIC_API_TOKEN` of the same market core that
  `MARKET_API_URL` points to
- `RENDER_EXTERNAL_URL` — canonical service URL supplied automatically by Render

Secrets must be configured in Render and must not be committed. Outside Render,
`PUBLIC_URL` remains available as a local fallback.
