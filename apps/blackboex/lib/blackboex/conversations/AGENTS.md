# AGENTS.md — Conversations Context

Event-sourced agent interaction history. Facade: `Blackboex.Conversations` (`conversations.ex`).

## Hierarchy

```
Conversation (1 per API, permanent)
  └── Run (1 per agent execution)
        └── Event (append-only, ordered by sequence)
```

## Query Module

`ConversationQueries` — all `Ecto.Query` composition for conversations, runs, and events. Sub-modules call `ConversationQueries`, not inline queries.

## Key Functions

```elixir
get_or_create_conversation(api_id, org_id) :: {:ok, Conversation.t()} | {:error, ...}
create_run(attrs) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
complete_run(Run.t(), attrs) :: {:ok, Run.t()} | {:error, Ecto.Changeset.t()}
touch_run(run_id) :: :ok                          # heartbeat — MUST be called by long steps
list_stale_runs(stale_after_ms) :: [Run.t()]      # used by RecoveryWorker
append_event(attrs) :: {:ok, Event.t()} | {:error, Ecto.Changeset.t()}
next_sequence(run_id) :: non_neg_integer()        # SELECT COUNT(*) — safe only with single writer
list_runs(conversation_id, opts) :: [Run.t()]
list_events(run_id, opts) :: [Event.t()]
```

## Run State Machine

```
pending ──► running ──► completed
                  ├──► failed
                  └──► partial
```

## Event Types

`user_message`, `system_message`, `assistant_message`, `tool_call`, `tool_result`, `code_snapshot`, `guardrail_trigger`, `error`, `status_change`

Valid tool names: `generate_code`, `compile_code`, `format_code`, `lint_code`, `generate_tests`, `run_tests`, `generate_docs`, `submit_code`

## Schema Notes

- `Event` — no `updated_at`. Immutable. `sequence` is `SELECT COUNT(*)`, not a DB sequence.
- `Run.updated_at` — used as heartbeat by `RecoveryWorker`. Touch every ~30s during long operations.
- `Conversation` — unique on `[:organization_id, :api_id]`. Created lazily, never deleted.

## Gotchas

1. **`touch_run/1` is liveness** — RecoveryWorker marks runs with `updated_at < cutoff` as failed. Every long pipeline step must call it.
2. **Sequence numbers not atomic** — safe only because `Agent.Session` is the sole writer per run.
3. **`complete_run/2` not idempotent** — calling twice overwrites `completed_at`. Pipeline calls it twice by design (pending→running, then final status).
4. **Events have no `updated_at`** — never call `Repo.update/1` on an event.
5. **`list_runs/2` returns no preloads** — call `Repo.preload/2` explicitly.
