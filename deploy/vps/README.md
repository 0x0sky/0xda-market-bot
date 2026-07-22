# VPS bot deployment

This directory runs the client Telegram bot on the same VPS as the
provider-agnostic `0xda-market` core.

The VPS uses an **active/passive** model. Development and production releases
and secrets are stored separately, but only one bot and one matching core stack
run at a time.

## Environment contract

| GitHub environment | Source branch | Telegram bot | Core / database |
| --- | --- | --- | --- |
| `development` | `master` | `@zeroxda_market_test_bot` | development core + test Supabase |
| `production` | `release*` | `@zeroxda_market_bot` | production core + production Supabase |

Both use `RACK_ENV=production` as a managed server runtime. `DEPLOY_ENV`
identifies the selected deployment environment.

## VPS layout

```text
/opt/0xda-market-bot/
  environments/
    development/
      current -> releases/<sha>
      releases/
      shared/.env
    production/
      current -> releases/<sha>
      releases/
      shared/.env
```

The shared switch state is stored at:

```text
/opt/0xda-market-runtime/active-environment
```

The core repository owns the manual `Switch VPS Environment` workflow and the
switch controller. A bot deployment never activates a different environment by
itself.

## GitHub environments

Create `development` and `production` in `0xda-market/0xda-market-bot`.

Each environment requires these secrets:

- `VPS_HOST`
- `VPS_USER=deploy`
- `VPS_SSH_PRIVATE_KEY`

Each environment requires this variable:

- `VPS_BOT_DEPLOY_PATH=/opt/0xda-market-bot`

The workflow uses SSH port `22022` directly. Do not add `VPS_PORT`.

## Runtime files

Create both files on the VPS:

```text
/opt/0xda-market-bot/environments/development/shared/.env
/opt/0xda-market-bot/environments/production/shared/.env
```

Development example:

```env
DEPLOY_ENV=development
PORT=10000
RACK_ENV=production
TELEGRAM_BOT_TOKEN=<@zeroxda_market_test_bot token>
TELEGRAM_WEBHOOK_SECRET=<development webhook secret>
MARKET_API_URL=https://0xda-market.nilx.one
MARKET_API_TOKEN=<development core API token>
REGISTER_TELEGRAM_WEBHOOK=0
PUBLIC_URL=https://0xda-market.nilx.one/bot
```

Production uses:

```env
DEPLOY_ENV=production
TELEGRAM_BOT_TOKEN=<@zeroxda_market_bot token>
TELEGRAM_WEBHOOK_SECRET=<production webhook secret>
MARKET_API_TOKEN=<production core API token>
```

The two webhook secrets, Telegram tokens and API tokens must be distinct. Do not
store these runtime values in GitHub Environment secrets; they live only in the
VPS `.env` files.

Protect them:

```sh
chown deploy:deploy /opt/0xda-market-bot/environments/*/shared/.env
chmod 0600 /opt/0xda-market-bot/environments/*/shared/.env
```

Keep `REGISTER_TELEGRAM_WEBHOOK=0` until the selected core and bot have passed
local and HTTPS smoke tests. Set it to `1` only for the environment being
activated.

## Deployment behavior

After green `CI`:

- `master` stages or refreshes `development`;
- `release*` stages or refreshes `production`;
- an inactive environment is built but not started;
- the active environment is refreshed immediately and health-gated;
- a failed active refresh attempts to restart the previous release.

Both environments intentionally bind the bot to `127.0.0.1:10001`, which is why
only one may run at a time.

## Switching

Run the manual `Switch VPS Environment` workflow in
`0xda-market/0xda-market`. It validates and starts the target core first, then
the matching bot. The previous environment is restarted automatically if the
target bot fails its health check.

Production switching requires explicit confirmation and should also be protected
by GitHub Environment reviewers.

## Smoke checks

After development is active:

```sh
cat /opt/0xda-market-runtime/active-environment
curl -i http://127.0.0.1:10001/health
cd /opt/0xda-market-bot/environments/development/current/deploy/vps
docker compose ps
docker compose logs --tail 200 bot
```

The public contract remains:

- `https://0xda-market.nilx.one` — core entry point;
- `https://0xda-market.nilx.one/bot` — Telegram bot boundary;
- `https://0xda-market.nilx.one/webapp` — Telegram WebApp.

Caddy routing and webhook activation remain separate reviewed gates.
