# VPS bot deployment

This deployment runs the development Telegram bot as a separate service from the
`0xda-market` core on the same VPS.

## Current development model

- `master` is the active development branch;
- no separate bot release branch is required at this stage;
- Render is not treated as the production baseline;
- the VPS is the environment where the bot is built, started and tested;
- the bot binds only to `127.0.0.1:10001`;
- Telegram webhook registration remains disabled until local and HTTPS smoke tests pass.

## Public URL contract

The project uses one market hostname:

- `https://0xda-market.nilx.one` — core / market entry point;
- `https://0xda-market.nilx.one/bot` — bot service and Telegram webhook boundary;
- `https://0xda-market.nilx.one/webapp` — Telegram WebApp.

`app.nilx.one` is unrelated to `0xda-market` and must not be used by this service.

## VPS layout

```text
/opt/0xda-market-bot/
  current -> releases/<sha>
  releases/
  shared/.env
```

Create the runtime environment before the first deployment:

```sh
mkdir -p /opt/0xda-market-bot/{releases,shared}
cp deploy/vps/.env.example /opt/0xda-market-bot/shared/.env
chown -R deploy:deploy /opt/0xda-market-bot
chmod 0600 /opt/0xda-market-bot/shared/.env
```

Keep `REGISTER_TELEGRAM_WEBHOOK=0` for the first deployment. This allows the
container and its core API connection to be verified without changing Telegram.

## GitHub development environment

Secrets:

- `VPS_HOST`
- `VPS_USER=deploy`
- `VPS_SSH_PRIVATE_KEY`

Variable:

- `VPS_BOT_DEPLOY_PATH=/opt/0xda-market-bot`

The workflow uses SSH port `22022` and deploys green `master` builds.

## Smoke test

After a green deployment:

```sh
curl -i http://127.0.0.1:10001/health
cd /opt/0xda-market-bot/current/deploy/vps
docker compose ps
docker compose logs --tail 200 bot
```

The service remains private until Caddy routing for
`https://0xda-market.nilx.one/bot` is added and verified. The WebApp is routed
separately at `https://0xda-market.nilx.one/webapp`. Only after HTTPS and bot
smoke tests pass should `REGISTER_TELEGRAM_WEBHOOK` become `1`.
