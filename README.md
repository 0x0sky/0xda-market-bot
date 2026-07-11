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
- `PUBLIC_URL` — deployed client bot URL, without a trailing slash

Secrets must be configured in Render and must not be committed.
