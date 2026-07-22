# VPS bot deployment

The client bot runs on the same VPS as the provider-agnostic `0xda-market` core.
The VPS is active/passive: both environments may be staged, but only one matching
core + bot pair may run at a time.

## Environment contract

| GitHub environment | Branch | Telegram bot | Database |
| --- | --- | --- | --- |
| `development` | `master` | `@zeroxda_market_test_bot` | test Supabase |
| `production` | `release*` | `@zeroxda_market_bot` | production Supabase |

`DEPLOY_ENV` is the only runtime environment marker. It must match the GitHub
Environment and the VPS directory containing the runtime file.

## VPS layout

```text
/opt/0xda-market-bot/environments/
  development/
    current -> releases/<sha>
    releases/
    shared/.env
  production/
    current -> releases/<sha>
    releases/
    shared/.env

/opt/0xda-market-runtime/active-environment
```

The core repository owns the manual `Switch VPS Environment` workflow. A bot
deployment never changes the active environment by itself.

## GitHub environments

Create `development` and `production` in `0xda-market/0xda-market-bot`.
Each requires:

- secret `VPS_HOST`;
- secret `VPS_USER=deploy`;
- secret `VPS_SSH_PRIVATE_KEY`;
- variable `VPS_BOT_DEPLOY_PATH=/opt/0xda-market-bot`.

The workflow uses fixed SSH port `22022`. Do not add `VPS_PORT`.

## Runtime files

```text
/opt/0xda-market-bot/environments/development/shared/.env
/opt/0xda-market-bot/environments/production/shared/.env
```

Development example:

```env
DEPLOY_ENV=development
PORT=10000
TELEGRAM_BOT_TOKEN=<@zeroxda_market_test_bot value>
TELEGRAM_WEBHOOK_SECRET=<development value>
MARKET_API_URL=https://0xda-market.nilx.one
MARKET_API_TOKEN=<development core API value>
REGISTER_TELEGRAM_WEBHOOK=0
PUBLIC_URL=https://0xda-market.nilx.one/bot
```

Production uses `DEPLOY_ENV=production`, `@zeroxda_market_bot`, and separate
webhook and core API values. Runtime values live only in the VPS `.env` files,
not in GitHub Environment secrets.

Protect both files:

```sh
chown deploy:deploy /opt/0xda-market-bot/environments/*/shared/.env
chmod 0600 /opt/0xda-market-bot/environments/*/shared/.env
```

Keep `REGISTER_TELEGRAM_WEBHOOK=0` until local and HTTPS smoke checks pass.

## Deployment behavior

After green CI:

- `master` stages or refreshes `development`;
- `release*` stages or refreshes `production`;
- an inactive environment is built but not started;
- the active environment is refreshed and health-gated;
- a failed active refresh attempts to restart the previous release.

Both environments bind the bot to `127.0.0.1:10001`, so they cannot run
simultaneously.

## Switching and smoke checks

Use `Switch VPS Environment` in `0xda-market/0xda-market`. The controller starts
the selected core first, then its matching bot, and rolls back if activation
fails. Production requires explicit confirmation and GitHub Environment review.

After development is active:

```sh
cat /opt/0xda-market-runtime/active-environment
curl -i http://127.0.0.1:10001/health
cd /opt/0xda-market-bot/environments/development/current/deploy/vps
docker compose ps
docker compose logs --tail 200 bot
```

Public boundaries remain:

- `https://0xda-market.nilx.one` — core;
- `https://0xda-market.nilx.one/bot` — Telegram bot;
- `https://0xda-market.nilx.one/webapp` — Telegram WebApp.

Caddy routing and webhook activation remain separate reviewed gates.
