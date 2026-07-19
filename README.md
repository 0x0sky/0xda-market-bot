# 0xda-market Bot

Private Telegram interface for `0xda-market` clients.

The bot is a thin Telegram interface over the market core. It authenticates users
through the core API, renders the active catalog, exposes admin-only operations,
and never connects to PostgreSQL directly. The core remains the source of truth
for users, roles, products, prices and permissions.

## Runtime

- Ruby `3.3.11`
- Rack + Puma web service
- Render web services for test and production
- Render cron service for the production admin price digest

HTTP surface:

- `GET /health` — bot health, UTC server time and deployed Git revision
- `POST /telegram/webhook` — Telegram webhook, authorized with
  `X-Telegram-Bot-Api-Secret-Token`

Webhook requests are accepted quickly and dispatched in the background, so
Telegram does not have to wait for slow core wake-ups. For supported commands the
bot sends `0xda-market запускається…` if the core is still waking up.

Market API calls retry temporary `502`, `503`, `504`, transport errors and
transient non-JSON responses with exponential backoff.

## Telegram Commands

Default public command scope contains only `/start`. After authentication the bot
syncs a private command scope for the current chat.

Client commands:

- `/start` — passwordless Telegram authentication
- `/status` — current persisted role and account status; the response is removed
  after three seconds
- `/buy` — open the active product catalog

Admin commands:

- `/servers` — health and UTC server time for market core and bot
- `/users` — active Telegram users; shows Telegram ID, internal UUID and role
- `/setadmin @username` or `/setadmin TELEGRAM_ID` — promote a registered user
- `/apply_prices` — open the current price application form
- `/apply_price <sku|position|short name> <amount>` — apply one product price in
  USDT

Clients do not see or execute admin commands. The bot hides admin commands from
non-admin chats, and the core still verifies the persisted admin role for every
admin operation.

## Catalog

`/buy` loads active products from `GET /v1/products?locale=...` and renders the
first nine products as a 3x3 inline keyboard. Product callbacks use the stable
`buy_<sku>` contract.

Catalog rules:

- product rows are never hardcoded in the bot
- button text comes from `attributes.button_label` or `attributes.name`
- callback SKU is the product `id`
- full names, button labels, ordering and short names come from the core database
- Telegram `language_code=uk` resolves to `uk_UA`; unsupported or absent
  language codes fall back to `en_US`
- the bot stays provider-agnostic and database-agnostic

## Price Application

Admins can apply product prices through Telegram without touching the database.

`/apply_prices` requests localized `GET /v1/admin/prices/proposal` data and sends
a form with database-defined product positions, SKUs, full names, yesterday and
current prices, the internal editor UUID and application time. Product rows are
never duplicated in a bot template. Only interface copy belongs to the bot's
`en_US` / `uk_UA` message catalog.

`/apply_price` accepts a product reference and amount in USDT:

```text
/apply_price premium_6m 7.45
/apply_price 2 7.45
/apply_price prem 6 7.45
```

The product reference can be a SKU, catalog position or unambiguous short name.
Amounts support up to six decimal places. Until a new price is submitted, the
last applied price remains in effect.

## Daily Price Digest

`bin/send_price_digest` sends the price application form to every active admin.
Render runs it as `0xda-market-price-digest` at `05:00` and `06:00` UTC. The
script delivers only when that run matches `07:00` Central European Time, so CET
and CEST are handled without editing the cron schedule.

Manual run:

```sh
FORCE_PRICE_DIGEST=1 bundle exec ruby bin/send_price_digest
```

The cron service uses the production Telegram bot token and production market
core by default.

## Environments

Two Telegram bots and two Render web services map one-to-one onto the two market
cores. Environment variables on a bot service are static: a service never
switches environments, only code moves between branches.

| | test | production |
| --- | --- | --- |
| Git branch | `master` | `release` |
| Render service | `0xda-market-test-bot` | `0xda-market-bot` |
| Telegram bot | test bot | production bot |
| `MARKET_API_URL` | `https://zeroxda-market-test.onrender.com` | `https://zeroxda-market.onrender.com` |
| `MARKET_API_TOKEN` | test core `PUBLIC_API_TOKEN` | production core `PUBLIC_API_TOKEN` |
| Supabase | `0xda-market-test` through the test core | `0xda-market` through the production core |

Code reaches production through a pull request from `master` to the protected
`release` branch. Render deploys each service from the branch declared in
`render.yaml` after the `test` CI check passes.

The post-CI deployment gate polls `/health` until its `revision` matches the
exact tested commit. Render supplies this value through `RENDER_GIT_COMMIT`, so
the release tag cannot be created from an unverified production revision.

## Environment Variables

Configure these variables per Render web service:

- `TELEGRAM_BOT_TOKEN` — BotFather token for that exact Telegram bot
- `TELEGRAM_WEBHOOK_SECRET` — random webhook secret for Telegram requests
- `MARKET_API_URL` — matching core API URL for the same environment
- `MARKET_API_TOKEN` — matching core `PUBLIC_API_TOKEN`
- `PUBLIC_URL` — fallback public service URL outside Render
- `RENDER_EXTERNAL_URL` — canonical service URL supplied automatically by Render

Configure these variables on the price digest cron service:

- `TELEGRAM_BOT_TOKEN` — production bot token
- `MARKET_API_URL` — production core URL
- `MARKET_API_TOKEN` — production core `PUBLIC_API_TOKEN`
- `FORCE_PRICE_DIGEST` — optional manual override; set to `1` only for manual
  runs

Secrets must be configured in Render and must not be committed. Production and
test must use distinct bot tokens, webhook secrets and API tokens.

## Versioning and releases

Stable releases use Semantic Versioning tags such as `v0.1.0`. Notable changes
are curated in [CHANGELOG.md](CHANGELOG.md); the promotion, tag, draft-release
and rollback procedure is documented in [RELEASING.md](RELEASING.md).

## Local Development

Install dependencies:

```sh
bundle install
```

Run tests:

```sh
bundle exec rake
```

Run the Rack app locally:

```sh
TELEGRAM_BOT_TOKEN=... \
TELEGRAM_WEBHOOK_SECRET=... \
MARKET_API_URL=https://zeroxda-market-test.onrender.com \
MARKET_API_TOKEN=... \
bundle exec rackup
```

Check health:

```sh
curl http://localhost:9292/health
```
