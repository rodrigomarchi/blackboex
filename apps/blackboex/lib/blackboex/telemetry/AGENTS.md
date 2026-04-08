# AGENTS.md — Telemetry Context

Observability layer for BlackBoex. Read before adding any new instrumentation.

## Overview

Two complementary systems:

1. **OpenTelemetry spans** — distributed tracing created inline at callsites via `OpenTelemetry.Tracer.with_span/2`. Domain app uses `opentelemetry_api` only (compile-time macros, zero runtime). Web app uses the full SDK.
2. **Custom telemetry events** — domain metrics emitted through `Blackboex.Telemetry.Events`, consumed by PromEx plugins (Prometheus/Grafana) and optionally OTLP.

## Events Module

**File:** `apps/blackboex/lib/blackboex/telemetry/events.ex`
**Module:** `Blackboex.Telemetry.Events`

Single contract for all custom event emission. Callers never call `:telemetry.execute/3` directly.

### `safe_execute/3` — The Core Invariant

All public emit functions delegate to `safe_execute/3`, which wraps `:telemetry.execute/3` in `rescue`. A crash in any handler (PromEx, OTLP) must never propagate into business logic.

### All Defined Events

| Public function | Event name | Measurements | Metadata tags |
|---|---|---|---|
| `emit_api_request/1` | `[:blackboex, :api, :request]` | `duration` (ms) | `api_id`, `method`, `status` |
| `emit_llm_call/1` | `[:blackboex, :llm, :call]` | `duration`, `input_tokens`, `output_tokens` | `provider`, `model` |
| `emit_codegen/1` | `[:blackboex, :codegen, :generate]` | `duration`, `description_length` | `template_type` |
| `emit_compile/1` | `[:blackboex, :codegen, :compile]` | `duration` | `api_id`, `success` |
| `emit_sandbox_execute/1` | `[:blackboex, :sandbox, :execute]` | `duration` | `api_id` |
| `emit_agent_run/1` | `[:blackboex, :agent, :run]` | `duration`, `iteration_count`, `cost_cents` | `run_id`, `run_type`, `status` |
| `emit_agent_tool/1` | `[:blackboex, :agent, :tool]` | `duration` | `tool_name`, `success`, `run_id` |
| `emit_circuit_breaker/1` | `[:blackboex, :circuit_breaker, :state_change]` | _(empty)_ | `provider`, `from_state`, `to_state` |
| `emit_session_timeout/1` | `[:blackboex, :agent, :session_timeout]` | `count: 1` | `run_id` |
| `emit_policy_denied/1` | `[:blackboex, :policy, :denied]` | `count: 1` | `action`, `user_id` |
| `emit_rate_limit_rejected/1` | `[:blackboex, :rate_limit, :rejected]` | `count: 1` | `type`, `key` |
| `emit_pool_saturation/1` | `[:blackboex, :ecto, :pool_saturation]` | `queue_time_ms` | _(empty)_ |

Infrastructure-level events emitted directly via `:telemetry.execute/3` (both have their own `rescue` guards):

| Emitter | Event name | Measurements |
|---|---|---|
| `BlackboexWeb.Telemetry.measure_beam_stats/0` | `[:blackboex, :beam, :stats]` | `process_count`, `memory_bytes`, `run_queue_length` |
| `BlackboexWeb.BeamMonitor` | `[:blackboex, :beam, :high_message_queue]` | `queue_len` |

## Event Naming Convention

```
[:blackboex, <subsystem>, <operation>]
```

Three segments only — PromEx tag resolution and OTLP span naming expect this depth.

## Span Patterns

Spans are created inline at the callsite:

```elixir
require OpenTelemetry.Tracer, as: Tracer

def my_operation(args) do
  Tracer.with_span "blackboex.<subsystem>.<operation>" do
    start_time = System.monotonic_time(:millisecond)
    result = do_work(args)
    Tracer.set_attributes([{"blackboex.api_id", args.api_id}, {"blackboex.success", match?({:ok, _}, result)}])
    Events.emit_compile(%{duration_ms: System.monotonic_time(:millisecond) - start_time, ...})
    result
  end
end
```

Existing span sites:

| Span name | Module |
|---|---|
| `"blackboex.codegen.compile"` | `Blackboex.CodeGen.Compiler.compile/2` |
| `"blackboex.codegen.generate"` | `Blackboex.Agent.CodePipeline` |
| `"blackboex.sandbox.execute"` | `Blackboex.CodeGen.Sandbox` |

Attribute naming: domain attrs prefixed `blackboex.`, Gen AI attrs use `gen_ai.*` namespace.

**Sampling:** prod = `{:parent_based, %{root: {:trace_id_ratio_based, 0.1}}}` (10%). Dev/test = `traces_exporter: :none`.

## How to Add New Telemetry

Checklist — use an existing plugin as template (e.g., `BlackboexWeb.PromEx.Plugins.AgentMetrics`):

1. Add a typed `emit_*/1` function to `Events` using `safe_execute/3`. Numeric measurements in second arg, categorical labels in third arg. Duration always in ms named `:duration`.
2. Call it from the callsite; capture `start_time = System.monotonic_time(:millisecond)` before the operation.
3. Create a PromEx plugin in `apps/blackboex_web/lib/blackboex_web/prom_ex/plugins/` if a Prometheus metric is needed. Register the plugin in `BlackboexWeb.PromEx`.
4. Wrap with `Tracer.with_span/2` if distributed tracing is needed (domain app only has `opentelemetry_api`).
5. Audit cardinality of every new metadata key before merging (see below).

## Metric Cardinality

High-cardinality Prometheus labels cause label explosion and Prometheus OOM. Check before adding any tag.

**Safe (bounded) tags:** `method`, `status`, `provider`, `model`, `template_type`, `run_type`, `success`, `type` (rate limit), `action` (policy), `tool_name`, `from_state`/`to_state`.

**Forbidden as Prometheus labels:** `api_id`, `run_id`, `user_id`, `key` (rate limit), any free-form string or slug. Fine in OTel span attributes (sampled, not aggregated).

Rule: if a tag value grows with user activity, it must not be a Prometheus label.

## Config

- **Dev/test** (`config/dev.exs`, `config/test.exs`): `config :opentelemetry, traces_exporter: :none`
- **Prod** (`config/runtime.exs`): batch processor, 10% sampling, HTTP protobuf to `OTEL_EXPORTER_OTLP_ENDPOINT` (default `http://localhost:4318`).

## Telemetry Handlers in `Blackboex.Application`

`attach_telemetry_handlers/0` wires two handlers at startup:

1. **`"blackboex-req-llm-token-usage"`** — translates `[:req_llm, :token_usage]` (ReqLLMClient library event) into `Events.emit_llm_call/1`.
2. **`"blackboex-ecto-pool-saturation"`** — listens to `[:blackboex, :repo, :query, :stop]`; emits `Events.emit_pool_saturation/1` when `queue_time > 50ms`.

New `:telemetry.attach` calls must go in `attach_telemetry_handlers/0`. Re-attaching the same handler ID raises — detach first if needed in tests.

## Gotchas

**Always use `safe_execute` — never call `:telemetry.execute/3` directly from domain code.** A buggy handler will crash the calling process without this wrapper.

**Metric cardinality explodes silently.** Adding `api_id` or `user_id` as a PromEx tag will not error at boot — it silently creates millions of series under load.

**`opentelemetry_api` vs `opentelemetry`.** Domain app (`blackboex`) depends only on `opentelemetry_api`. Do not add the full SDK to `apps/blackboex/mix.exs` — Dialyzer will warn.

**Span names must not change after first deployment.** OTLP backends index by span name; renames break dashboards and alerts.

**`safe_execute` always returns `:ok`.** Do not use the return value for flow control.

**`description_length` is a measurement, not a tag.** It is in the measurements map in `emit_codegen/1` — correct. As a tag it would create unbounded cardinality.

**`telemetry_poller` runs every 10s.** Use `@tag :capture_log` in noise-sensitive tests if `BlackboexWeb.Telemetry` is supervised.
