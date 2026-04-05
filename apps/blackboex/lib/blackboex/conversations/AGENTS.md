# AGENTS.md — Conversations Context

Event-sourced agent interaction history. Provides the full audit trail for every AI code-generation run: what was requested, what the agent did, what it produced, and how much it cost.

## Overview

Three-level hierarchy:

```
Conversation (1 per API, permanent container)
  └── Run (1 per agent execution / user message)
        └── Event (1 per atomic action within a run)
```

A `Conversation` is created lazily on first agent trigger and never deleted. `Event` rows are append-only and ordered by `sequence` within their run.

## Data Model

### Conversation

Table: `conversations`

| Field                  | Type       | Default    | Notes                                      |
|------------------------|------------|------------|--------------------------------------------|
| `id`                   | UUID       | generated  | Primary key                                |
| `title`                | string     | nil        | Optional display title, max 500 chars      |
| `status`               | string     | `"active"` | `"active"` or `"archived"`                |
| `total_runs`           | integer    | 0          | Aggregate counter, incremented per run     |
| `total_events`         | integer    | 0          | Reserved for future use                    |
| `total_input_tokens`   | integer    | 0          | Lifetime input token sum                   |
| `total_output_tokens`  | integer    | 0          | Lifetime output token sum                  |
| `total_cost_cents`     | integer    | 0          | Lifetime cost in US cents                  |
| `api_id`               | UUID FK    | required   | Owning API — unique constraint with org    |
| `organization_id`      | UUID FK    | required   | Owning organization                        |

Unique constraint: `[:organization_id, :api_id]` — enforces the 1:1 per API invariant at the DB level.

### Run

Table: `runs`

| Field              | Type       | Default     | Notes                                              |
|--------------------|------------|-------------|----------------------------------------------------|
| `id`               | UUID       | generated   | Primary key                                        |
| `run_type`         | string     | required    | `generation`, `edit`, `test_only`, `doc_only`      |
| `status`           | string     | `"pending"` | See state machine below                            |
| `trigger_message`  | string     | nil         | User's original prompt/instruction                 |
| `config`           | map        | `%{}`       | Runtime config (max_iterations, max_time_ms, etc.) |
| `final_code`       | string     | nil         | Code artifact from successful run                  |
| `final_test_code`  | string     | nil         | Test artifact from successful run                  |
| `final_doc`        | string     | nil         | Documentation artifact from successful run         |
| `error_summary`    | string     | nil         | Human-readable failure description                 |
| `run_summary`      | string     | nil         | LLM-generated summary of what was accomplished     |
| `iteration_count`  | integer    | 0           | Number of fix/retry iterations consumed            |
| `event_count`      | integer    | 0           | Total events persisted for this run                |
| `input_tokens`     | integer    | 0           |                                                    |
| `output_tokens`    | integer    | 0           |                                                    |
| `cost_cents`       | integer    | 0           | Not currently populated by the pipeline            |
| `model`            | string     | nil         | Primary LLM model used                             |
| `fallback_model`   | string     | nil         |                                                    |
| `started_at`       | utc_datetime_usec | nil  |                                                    |
| `completed_at`     | utc_datetime_usec | nil  |                                                    |
| `duration_ms`      | integer    | nil         |                                                    |
| `conversation_id`  | UUID FK    | required    |                                                    |
| `api_id`           | UUID FK    | required    | Denormalized for queries                           |
| `user_id`          | integer FK | required    |                                                    |
| `organization_id`  | UUID FK    | required    | Denormalized                                       |
| `api_version_id`   | UUID FK    | nil         | Set on completion                                  |
| `updated_at`       | timestamp  |             | Touched every ~30s by `touch_run/1` as heartbeat   |

### Event

Table: `events`

| Field             | Type      | Notes                                                        |
|-------------------|-----------|--------------------------------------------------------------|
| `id`              | UUID      | Primary key                                                  |
| `event_type`      | string    | Required — see event types below                             |
| `sequence`        | integer   | Monotonic counter within a run (0-based)                     |
| `role`            | string    | `user`, `assistant`, `system`, or `tool`                     |
| `content`         | string    |                                                              |
| `tool_name`       | string    | Required for `tool_call`/`tool_result` events                |
| `tool_input`      | map       |                                                              |
| `tool_output`     | map       |                                                              |
| `tool_success`    | boolean   |                                                              |
| `tool_duration_ms`| integer   |                                                              |
| `code_snapshot`   | string    |                                                              |
| `test_snapshot`   | string    |                                                              |
| `input_tokens`    | integer   |                                                              |
| `output_tokens`   | integer   |                                                              |
| `cost_cents`      | integer   |                                                              |
| `metadata`        | map       |                                                              |
| `run_id`          | UUID FK   | Required                                                     |
| `conversation_id` | UUID FK   | Required (denormalized)                                      |
| `inserted_at`     | utc_datetime_usec | No `updated_at` — events are immutable             |

`Event` uses a bare `field :inserted_at` with `autogenerate`, not `timestamps()` — write-once records.

## Event Types

| Event Type          | When Used                                                     | Key Fields                                |
|---------------------|---------------------------------------------------------------|-------------------------------------------|
| `user_message`      | First event in every run                                      | `role: "user"`, `content`                 |
| `system_message`    | System-level instructions injected into the chain             | `role: "system"`, `content`               |
| `assistant_message` | LLM response text                                             | `role: "assistant"`, `content`, token fields |
| `tool_call`         | Agent invoking a generation/compilation tool                  | `tool_name`, `tool_input`                 |
| `tool_result`       | Response from a tool call                                     | `tool_name`, `tool_output`, `tool_success` |
| `code_snapshot`     | Intermediate code state at key pipeline steps                 | `code_snapshot`, `test_snapshot`          |
| `guardrail_trigger` | Security/safety rule fired during generation                  | `content`, `metadata`                     |
| `error`             | An error occurred                                             | `content`                                 |
| `status_change`     | Run status transition                                         | `content` (new status), `metadata`        |

Valid tool names: `generate_code`, `compile_code`, `format_code`, `lint_code`, `generate_tests`, `run_tests`, `generate_docs`, `submit_code`

The `Event` changeset enforces: if `event_type` is `tool_call` or `tool_result`, `tool_name` is required and must be one of the valid tool names.

## Run State Machine

```
pending ──► running ──► completed
                  │
                  ├──► failed
                  │
                  ├──► cancelled  (reserved — no current transition)
                  │
                  └──► partial
```

| Transition            | Trigger                                                              |
|-----------------------|----------------------------------------------------------------------|
| `pending → running`   | `Agent.Session` calls `complete_run(run, %{status: "running"})`    |
| `running → completed` | `handle_chain_success/2` — pipeline finished, artifacts saved       |
| `running → partial`   | `handle_chain_success/2` with `result.partial: true`               |
| `running → failed`    | `handle_chain_failure/2` — unrecoverable error                      |
| `running → failed`    | `RecoveryWorker` — run stuck > 5 min with no `updated_at` heartbeat |
| `pending → failed`    | `KickoffWorker` — Session GenServer failed to start                 |

## Public API

All functions in `Blackboex.Conversations`. Every function has a `@spec`.

```elixir
get_or_create_conversation(api_id, organization_id) :: {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
get_conversation(id) :: Conversation.t() | nil
get_conversation_by_api(api_id) :: Conversation.t() | nil
update_conversation_stats(Conversation.t(), map()) :: {:ok, Conversation.t()} | {:error, Ecto.Changeset.t()}
increment_conversation_stats(Conversation.t(), keyword()) :: {non_neg_integer(), nil}  # NOT {:ok, _}

create_run(attrs) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
get_run(id) :: Run.t() | nil
get_run!(id) :: Run.t()  # raises if not found
complete_run(Run.t(), attrs) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
update_run_metrics(Run.t(), attrs) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
touch_run(run_id) :: :ok  # heartbeat via Repo.update_all
list_runs(conversation_id, opts) :: [Run.t()]  # ordered desc inserted_at, default limit 50
list_stale_runs(stale_after_ms) :: [Run.t()]  # status "running" with old updated_at

append_event(attrs) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
list_events(run_id, opts) :: [Event.t()]  # ordered by sequence ASC, default limit 1000
next_sequence(run_id) :: non_neg_integer()  # SELECT COUNT(*) — see Gotchas
```

## Token and Cost Tracking

Per-event token/cost fields are raw values for that specific LLM call. `update_run_metrics/2` aggregates them at run completion. `cost_cents` on `Run` is not currently populated by the pipeline. `total_events`, `total_input_tokens`, `total_output_tokens`, and `total_cost_cents` on `Conversation` are reserved for future analytics — only `total_runs` is incremented today.

## Testing

No factories; use context functions directly. See `apps/blackboex/test/blackboex/agent/session_test.exs` and `recovery_worker_test.exs` for patterns. Tag integration tests as `@moduletag :integration`.

## Gotchas

**Sequence numbers are not atomic.** `next_sequence/1` is `SELECT COUNT(*)`, not a DB sequence. Safe only because each `Agent.Session` GenServer is the sole writer for its `run_id`. Any future multi-writer scenario needs a real DB sequence.

**Conversation creation is not atomic.** `get_or_create_conversation/2` is read-then-insert. The unique constraint on `[:organization_id, :api_id]` is the safety net; concurrent inserts cause one to fail. Oban retry covers the failure.

**`complete_run/2` is not idempotent.** Calling it on an already-completed run silently overwrites `completed_at` and `duration_ms`. The pipeline calls it twice by design (pending→running, then final status).

**`touch_run/1` is the liveness signal.** `RecoveryWorker` uses `updated_at < cutoff` to detect dead sessions. Any new long-running pipeline step must call `touch_run/1` or the 5-minute threshold may incorrectly fire.

**Events have no `updated_at`.** Do not call `Repo.update/1` on an event — the column does not exist.

**`list_runs/2` and `list_events/2` return no preloads.** Call `Repo.preload/2` explicitly.
