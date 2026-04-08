# AGENTS.md — Billing Context

Stripe integration for subscriptions, usage tracking, and enforcement gates.

Facade: `Blackboex.Billing` (`billing.ex`).

## Flow

```
1. User selects plan → Billing.create_checkout_session/4 → Stripe Checkout
2. Stripe webhook → WebhookController → Billing.WebhookHandler → create_or_update_subscription/1
3. Usage gates → Billing.Enforcement.check/2 → :ok | {:error, :limit_exceeded, details}
4. Daily aggregation → UsageAggregationWorker (Oban cron)
```

## Key Modules

| Module | Purpose |
|--------|---------|
| `Billing` | Facade: `get_subscription/1`, `create_checkout_session/4`, `record_usage_event/1` |
| `BillingQueries` | Query builders for subscriptions, usage events, daily usage |
| `Subscription` | Schema: stripe IDs, plan, status, period dates |
| `Enforcement` | `check/2` — gates create_api and llm_generation by plan |
| `UsageEvent` | Raw events: `api_invocation`, `llm_generation` with token metadata |
| `DailyUsage` | Aggregated: org_id, date, api_invocations, tokens, cost |
| `UsageAggregationWorker` | Oban daily cron, queue: billing |
| `WebhookHandler` | Stripe event processing |
| `ProcessedEvent` | Idempotency tracking for webhooks |

**Rule:** All query composition goes through `BillingQueries`. Sub-modules call `BillingQueries`, not inline `from` expressions.

## Webhook Idempotency — Critical Order

```
1. Check if event_id already in ProcessedEvent
2. Process the event
3. Mark as processed ONLY on success
```

Never mark before processing.

## Plans & Limits

| Feature | Free | Pro | Enterprise |
|---------|------|-----|------------|
| APIs | Limited | Higher | Unlimited |
| LLM generations | Limited | Higher | Unlimited |

## Gotchas

1. **Atom safety** — Use Map lookup for plan names: `%{"free" => :free, "pro" => :pro}`. Never `String.to_existing_atom/1`.
2. **Webhook controller** — Return 500 on real failures (Stripe retries). Return 200 only for success or already_processed.
3. **Decimal vs Float** — PostgreSQL `avg()` returns Decimal. Convert with `Decimal.to_float/1`.
4. **`DateTime.from_unix!`** — Guard `is_integer/1` before calling on webhook payload data.

## Testing

- Mock: `Blackboex.Billing.StripeClientMock` via Mox — use `setup :stub_stripe`
- Enforcement: Test both `:ok` and `{:error, :limit_exceeded, _}` paths
