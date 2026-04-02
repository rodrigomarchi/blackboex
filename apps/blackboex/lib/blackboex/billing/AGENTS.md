# AGENTS.md — Billing & Stripe

Stripe integration for subscriptions, usage tracking, and enforcement gates.

## Flow

```
1. User selects plan → Billing.create_checkout_session/4
   → Stripe Checkout → redirect to success_url

2. Stripe fires webhook → POST /webhooks/stripe
   → WebhookController verifies signature
   → Billing.WebhookHandler processes event
   → Billing.create_or_update_subscription/1 upserts local record

3. Usage gates → Billing.Enforcement.check/2
   → Called before: create_api, llm_generation
   → Returns :ok | {:error, :limit_exceeded, details}

4. Daily aggregation → UsageAggregationWorker (Oban cron)
   → Aggregates UsageEvents into DailyUsage
   → Idempotent upsert per org/date
```

## Plans & Limits

| Feature | Free | Pro | Enterprise |
|---------|------|-----|------------|
| APIs | Limited | Higher | Unlimited |
| LLM generations | Limited | Higher | Unlimited |
| Rate limit | Default | Configurable | Configurable |

## Key Modules

| Module | Purpose |
|--------|---------|
| `Billing` | Facade: `get_subscription/1`, `create_checkout_session/4`, `record_usage_event/1` |
| `Subscription` | Schema: stripe_customer_id, stripe_subscription_id, plan, status, period dates |
| `Enforcement` | `check/2` — gates expensive operations by plan limits |
| `UsageEvent` | Raw events: `api_invocation`, `llm_generation` with token metadata |
| `DailyUsage` | Aggregated: org_id, date, api_invocations, llm_generations, tokens, cost |
| `UsageAggregationWorker` | Oban daily cron, queue: billing, max_attempts: 3 |
| `StripeClient.Live` | Real Stripe API: checkout, portal, webhooks |
| `WebhookHandler` | Stripe event processing |
| `ProcessedEvent` | Idempotency tracking for webhooks |

## Webhook Idempotency

**Critical order: check → process → mark**

```
1. Check if event_id already in ProcessedEvent table
2. Process the event (update subscription, etc.)
3. Mark as processed ONLY on success
```

Never mark before processing — if handler crashes, event is lost forever (Stripe won't retry 200s).

## Gotchas

1. **Atom safety** — Don't use `String.to_existing_atom/1` with plan names from DB. Use explicit Map: `%{"free" => :free, "pro" => :pro, "enterprise" => :enterprise}`.
2. **Stripe secrets in prod** — `runtime.exs` must `raise` if STRIPE_KEY or STRIPE_WEBHOOK_SECRET missing.
3. **Webhook controller returns** — Return 500 on real failures (Stripe retries). Return 200 only for success or already_processed.
4. **DateTime.from_unix!** — Guard `is_integer/1` before calling on webhook payload data.
5. **UsageAggregationWorker batch** — Wrap each upsert in try/rescue. Single failure shouldn't kill entire batch.
6. **Decimal vs Float** — PostgreSQL `avg()` returns Decimal. Convert with `Decimal.to_float/1`.

## Testing

- Mock: `Blackboex.Billing.StripeClientMock` via Mox
- Webhook testing: Build event struct manually, call `WebhookHandler.handle/1`
- Enforcement: Test both `:ok` and `{:error, :limit_exceeded, _}` paths
- DailyUsage: Insert UsageEvents, run worker, verify aggregation
