# 0xda-market Bot

Private Telegram client interface for the provider-agnostic `0xda-market` core.

The bot authenticates Telegram identities through the generic core API, renders
the database-backed catalog and exposes role-gated administrator operations. It
does not connect to PostgreSQL directly and does not own users, roles, products,
prices or permissions.

## Runtime

- Ruby `3.3.11`
- Rack + Puma
- Docker Compose on the project VPS
- Caddy routing from `https://0xda-market.nilx.one/bot/*`
- private shared Docker network `zero-x-da-market-edge`

HTTP surface:

- `GET /health` — bot health and server time
- `POST /telegram/webhook` — Telegram webhook authorized with
  `X-Telegram-Bot-Api-Secret-Token`

The public Caddy route strips `/bot`, so
`https://0xda-market.nilx.one/bot/telegram/webhook` reaches the internal
`/telegram/webhook` route.

Market API calls retry temporary `502`, `503`, `504`, transport failures and
transient non-JSON responses with exponential backoff. Slow commands may send a
localized server-starting notice while the core becomes available.

## Architecture boundary

```text
Telegram update
  -> MarketClientBot
  -> MarketAPI anti-corruption layer
  -> generic external-identity/core contract
  -> internal market user UUID
```

Telegram IDs, usernames, chat IDs and profile copy remain in this adapter. The
core receives provider-neutral identity payloads and internal UUIDs for privileged
actions.

## Telegram commands

The default public scope contains `/start`. After authentication the bot syncs a
private command scope for the current chat.

Client commands:

- `/start` — authenticate the Telegram identity
- `/buy` — open the active product catalog
- `/status` — show the persisted role and account status

Administrator commands:

- `/apply_prices` — review the database-defined price proposal
- `/apply_price <sku|position|name> <amount>` — apply one USDT price
- `/rates` — show currency products and rates
- `/set_rate <currency> <amount>` — update a currency product price
- `/servers` — show core and bot health
- `/users` — show active users as Telegram profile links
- `/set_admin @username|TELEGRAM_ID` — assign the persisted admin role

Non-admin chats do not receive administrator commands, and the core independently
checks the internal admin role for every privileged operation.

## Catalog and pricing

`/buy` loads active products from `GET /v1/products?locale=...`. Product rows,
ordering, button labels, full names, short names and prices come from the core
database. Callback data uses the stable `buy_<sku>` contract.

The initial marketable catalog contains Telegram Premium 3/6/12 months, Telegram
Stars 500/1000/3000, TON, BTC and ETH. Currency rows are exposed separately by the
core and use the same unified pricing flow.

Supported interface locales are English, Ukrainian, Russian, French, Spanish and
German. Unknown languages fall back to `en_US`.

`/apply_prices` uses localized core proposal data and renders current/previous
prices, application timestamps and clickable editor identities without exposing
internal UUIDs in Telegram messages.

## VPS deployment

The VPS is the canonical runtime. The old Render Blueprint is not part of the
supported deployment path.

Current automation is development-only:

- `master` deploys to the GitHub `development` environment after green CI;
- the runtime file is
  `/opt/0xda-market-bot/environments/development/shared/.env`;
- the bot binds to `127.0.0.1:10001` and joins the private edge network as
  `market-bot`;
- an inactive environment is staged without switching the active marker;
- an active refresh is health-gated and attempts to restart the previous release
  on failure.

Production directories remain reserved, but production deployment is not enabled
by the current workflow. Enabling it requires a separate reviewed change paired
with the core release path.

See [`deploy/vps/README.md`](deploy/vps/README.md) and the core
[`deploy/vps/OPERATIONS.md`](https://github.com/0xda-market/0xda-market/blob/master/deploy/vps/OPERATIONS.md).

## Environment variables

The active bot runtime file contains:

- `DEPLOY_ENV` — `development` or `production`, matching its directory
- `PORT` — internal Puma port, normally `10000`
- `TELEGRAM_BOT_TOKEN` — token for the exact environment bot
- `TELEGRAM_WEBHOOK_SECRET` — webhook request secret
- `MARKET_API_URL` — matching core URL, normally
  `https://0xda-market.nilx.one`
- `MARKET_API_TOKEN` — matching core `PUBLIC_API_TOKEN`
- `PUBLIC_URL` — `https://0xda-market.nilx.one/bot`
- `REGISTER_TELEGRAM_WEBHOOK` — explicit webhook registration gate

Runtime values live only in protected VPS `.env` files. Production and
development must use distinct Telegram, webhook and core API tokens.

## Scheduled price digest

`bin/send_price_digest` sends the price proposal to active administrators at
07:00 Central European time. The script itself chooses the correct 05:00 or 06:00
UTC candidate run for CET/CEST.

The VPS systemd timer runs both candidate hours. It executes only when
`production` is the active environment and the production bot container is
healthy. Development runs are skipped without sending anything.

Install or refresh the timer on the VPS:

```sh
cd /opt/0xda-market-bot/environments/development/current/deploy/vps
sudo ./install-systemd.sh
systemctl list-timers 0xda-market-price-digest.timer
```

Inspect a run:

```sh
journalctl -u 0xda-market-price-digest.service --since today
```

Manual application-level run:

```sh
FORCE_PRICE_DIGEST=1 bundle exec ruby bin/send_price_digest
```

## Local development

```sh
bundle install
bundle exec rake

DEPLOY_ENV=development \
TELEGRAM_BOT_TOKEN=... \
TELEGRAM_WEBHOOK_SECRET=... \
MARKET_API_URL=https://0xda-market.nilx.one \
MARKET_API_TOKEN=... \
PUBLIC_URL=http://localhost:9292 \
REGISTER_TELEGRAM_WEBHOOK=0 \
bundle exec rackup
```

Check health:

```sh
curl http://localhost:9292/health
```

## Versioning and releases

Stable releases use Semantic Versioning tags such as `v0.1.0`. Notable changes
are curated in [CHANGELOG.md](CHANGELOG.md); promotion and rollback are documented
in [RELEASING.md](RELEASING.md).
