# VPS bot deployment

This deployment runs the production Telegram bot as a separate service from
`0xda-market` core.

## Safety model

- the bot binds only to `127.0.0.1:10001` on the VPS;
- Telegram webhook registration is disabled during parallel smoke testing;
- the existing Render bot remains active until `app.nilx.one` HTTPS and bot
  smoke tests pass;
- the bot continues using the existing Render core until the core VPS cutover is
  separately approved.

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
container and its core API connection to be verified without changing the live
Telegram webhook.

## GitHub production environment

Secrets:

- `VPS_HOST`
- `VPS_USER=deploy`
- `VPS_SSH_PRIVATE_KEY`

Variable:

- `VPS_BOT_DEPLOY_PATH=/opt/0xda-market-bot`

The workflow uses SSH port `22022` directly.

## Parallel smoke test

After a green deployment:

```sh
curl -i http://127.0.0.1:10001/health
cd /opt/0xda-market-bot/current/deploy/vps
docker compose ps
docker compose logs --tail 200 bot
```

The service is not publicly reachable yet. The next reviewed change will route
`app.nilx.one` through the existing VPS Caddy instance to `127.0.0.1:10001`.
Only after HTTPS succeeds should `REGISTER_TELEGRAM_WEBHOOK` become `1` and the
bot be redeployed to switch the Telegram webhook.
