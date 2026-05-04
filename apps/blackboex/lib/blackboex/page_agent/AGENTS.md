# PageAgent

AI chat agent dedicated to Pages. Generates or edits the markdown content of a
`Blackboex.Pages.Page`. Mirrors the shape of `Blackboex.PlaygroundAgent` but is
purely text-oriented — no sandbox/execution, just markdown produced by the LLM
and applied atomically to `page.content`.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.PageAgent` | Facade — `start/3` picks `:generate` vs `:edit` from `page.content`, checks org-scope IDOR, enqueues `KickoffWorker`. |
| `PageAgent.KickoffWorker` | Oban worker on queue `:page_agent`, `max_attempts: 1`, `unique: [keys: [:page_id], period: 30]`. Creates conversation + run + initial user-message event, broadcasts `:run_started`, starts `Session`. |
| `PageAgent.Session` | GenServer — CircuitBreaker check → `Task.Supervisor.async_nolink` on `Blackboex.SandboxTaskSupervisor` → 3-minute timeout. Monitored via Registry `PageAgent.SessionRegistry`. |
| `PageAgent.ChainRunner` | Runs the pipeline in the task; on success calls `Pages.record_ai_edit` to apply the edit and broadcasts `:run_completed`; on failure marks run failed and broadcasts `:run_failed`. |
| `PageAgent.ContentPipeline` | Single LLM call via `Blackboex.LLM.Config.client()`. No validation/fix loops. Streams when a `token_callback` is provided. Extracts markdown via `ContentParser`. |
| `PageAgent.ContentParser` | Extracts the first `~~~markdown` / `~~~md` / `~~~` (or backtick fallback) fence; picks up an optional `Summary:` line for `summary`. Tilde fence avoids ambiguity with nested ` ```elixir ` code blocks inside the page content. |
| `PageAgent.StreamManager` | Buffers LLM tokens in the process dictionary; flushes on 20+ chars or `\n` as `{:content_delta, %{delta, run_id}}` broadcasts. Also exposes `broadcast_run/2`, `broadcast_page/2`. |
| `PageAgent.Prompts` | Dedicated system prompts (`:generate` and `:edit`) in English. Teaches the model to return CommonMark+GFM markdown, instructs preservation of tone/style on edit, truncates `content_before` at 30k chars. |

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `start/3` | `(Page.t(), scope(), String.t()) :: {:ok, Oban.Job.t()} \| {:error, :limit_exceeded \| :empty_message \| :unauthorized \| term()}` | Enqueued Oban job or error | Validates quota, checks org ownership (IDOR), picks run type, enqueues `KickoffWorker` |

`scope` is `%{user: %{id: term()}, organization: %{id: term()}}` — the standard
`Blackboex.Accounts.Scope` struct satisfies this.

## PubSub topics

| Topic | Messages |
|-------|----------|
| `"page_agent:page:#{page_id}"` | `{:run_started, %{run_id, run_type, page_id}}`, also re-broadcast of `:run_completed` and `:run_failed` |
| `"page_agent:run:#{run_id}"` | `{:content_delta, %{delta, run_id}}`, `{:run_completed, %{content, summary, run_id, run}}`, `{:run_failed, %{reason, run_id}}` |

`PageLive.Edit` subscribes to the page topic in `mount` and to the run topic
when it receives `:run_started`.

## Supervision tree

In `Blackboex.Application`, alongside the playground agent registries:

```elixir
{Registry, keys: :unique, name: Blackboex.PageAgent.SessionRegistry},
{DynamicSupervisor, name: Blackboex.PageAgent.SessionSupervisor, strategy: :one_for_one}
```

Tasks run under the shared `Blackboex.SandboxTaskSupervisor`.

## Prompt response contract

The LLM must respond with exactly one `~~~markdown ... ~~~` block (tilde fences
allow nested ` ```language ` code blocks inside). Everything outside the fence
is ignored for content extraction, but a `Summary: ...` line (if present)
becomes the run's `run_summary`. Failing to emit a fence yields an error
`"model response did not contain a markdown block"` and marks the run failed.

## Budgeting and safety

- IDOR check in `start/3`: `page.organization_id` must equal `scope.organization.id`.
- Session timeout: **3 minutes**.
- Unique-job constraint on `page_id` for 30s prevents double-click spam.
- `CircuitBreaker.allow?(:anthropic)` gates chain execution; on open, run fails.

## Applying the edit

`ChainRunner.handle_chain_success/2` calls `Blackboex.Pages.record_ai_edit/3`,
which:
1. Validates the page belongs to the scope's organization (defense-in-depth IDOR).
2. Updates `page.content` via `update_page/2` with the new markdown.

The `BlackboexWeb.PageLive.Edit` LiveView updates its `page` assign on the
`:run_completed` broadcast; the Tiptap hook detects the changed `data-value`
and calls `editor.commands.setContent(md)` automatically — no `push_event` is
needed.

## Tests

- `Blackboex.PageAgent.*Test` — unit tests per module.
- `Blackboex.PageAgentIntegrationTest` (`@moduletag :integration`) — smoke test
  running the full pipeline end-to-end with a `Mox`-stubbed
  `Blackboex.LLM.ClientMock`.
- `BlackboexWeb.PageLive.EditChatTest` — LiveView-level chat behavior.
