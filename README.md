# 0xda-market Client Bot

Private Telegram client for `zeroxda-market`.

The first release implements passwordless Telegram authentication:

```text
/start
→ verified Telegram webhook
→ POST 0xda-market/v1/auth/telegram
→ stable internal user UUID
→ authorization confirmation
```

## Environment

- `TELEGRAM_BOT_TOKEN` — token for `@zeroxda_market_client_bot`
- `TELEGRAM_WEBHOOK_SECRET` — generated random webhook secret
- `MARKET_API_URL` — defaults to `https://zeroxda-market.onrender.com`
- `MARKET_API_TOKEN` — the backend `PUBLIC_API_TOKEN`
- `RENDER_EXTERNAL_URL` — canonical service URL supplied automatically by Render

Secrets must be configured in Render and must not be committed. Outside Render,
`PUBLIC_URL` remains available as a local fallback.
