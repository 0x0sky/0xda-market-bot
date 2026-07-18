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

Two Telegram bots and two Render services map one-to-one onto the two market
cores. Environment variables on a bot service are static: a service never
switches environments, only code moves between branches.

| | test | production |
| --- | --- | --- |
| Git branch | `master` | `release` |
| Render service | `0xda-market-test-bot` | `0xda-market-bot` |
| Telegram bot | test client bot | production client bot |
| `MARKET_API_URL` | `https://zeroxda-market-test.onrender.com` | `https://zeroxda-market.onrender.com` |
| `MARKET_API_TOKEN` | test core `PUBLIC_API_TOKEN` | production core `PUBLIC_API_TOKEN` |
| Supabase | `0xda-market-test` through the test core | `0xda-market` through the production core |

Code reaches production only through the "Promote to production" GitHub
workflow, which fast-forwards `release` to `master`. Render deploys each
service from its branch; enable "Auto-Deploy: After CI Checks Pass" on both
services so a red build never ships.

## Environment variables

Configure these variables per service in Render:

- `TELEGRAM_BOT_TOKEN` — BotFather token for that exact Telegram bot
- `TELEGRAM_WEBHOOK_SECRET` — random webhook secret for Telegram requests
- `MARKET_API_URL` — matching core API URL for the same environment
- `MARKET_API_TOKEN` — matching core `PUBLIC_API_TOKEN`
- `PUBLIC_URL` — fallback public service URL outside Render
- `RENDER_EXTERNAL_URL` — canonical service URL supplied automatically by Render

Secrets must be configured in Render and must not be committed. Production and
test must use distinct bot tokens, webhook secrets and API tokens.
