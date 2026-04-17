# PlaygroundConversations Context

Persisted chat conversations, runs, and events for the **Playground AI agent**.
Intentionally separate from `Blackboex.Conversations` (which is 1:1 with an API) so
the two domains evolve independently.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.PlaygroundConversations` | Facade — `get_or_create_conversation/3`, `create_run/1`, `mark_run_running/1`, `complete_run/2`, `fail_run/2`, `append_event/2`, `list_runs/2`, `list_events/2`, `list_recent_events_for_playground/2`, `next_sequence/1`, `increment_conversation_stats/2` |
| `PlaygroundConversation` | Schema — `belongs_to :playground` (unique), `belongs_to :organization`, `belongs_to :project`, aggregated `total_runs/events/tokens/cost_cents` |
| `PlaygroundRun` | Schema — `belongs_to :conversation`, `belongs_to :playground`, `belongs_to :user`. Fields: `run_type` (`"generate" \| "edit"`), `status` (`"pending" \| "running" \| "completed" \| "failed" \| "canceled"`), `trigger_message`, `code_before`, `code_after`, `run_summary`, `error_message`, tokens, cost, duration, timing. Changesets: `changeset/2`, `running_changeset/2`, `completion_changeset/2`. |
| `PlaygroundEvent` | Schema — `belongs_to :run`, `sequence` (unique per run), `event_type` (`"user_message" \| "assistant_message" \| "code_delta" \| "completed" \| "failed"`), `content`, `metadata`. |
| `PlaygroundConversationQueries` | Query builders only — no `Repo.*` calls. |

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `get_or_create_active_conversation/3` | `(String.t(), String.t(), String.t()) :: {:ok, PlaygroundConversation.t()} \| {:error, Ecto.Changeset.t()}` | Active conversation | Returns the existing active conversation for a playground or creates one |
| `start_new_conversation/3` | `(String.t(), String.t(), String.t()) :: {:ok, PlaygroundConversation.t()} \| {:error, Ecto.Changeset.t()}` | Fresh active conversation | Archives the current active conversation (if any) and creates a new one |
| `archive_active_conversation/1` | `(String.t()) :: {:ok, PlaygroundConversation.t()} \| :noop \| {:error, Ecto.Changeset.t()}` | Updated conversation, `:noop` if none active, or error | Sets status to `"archived"` on the active conversation |
| `get_conversation/1` | `(String.t()) :: PlaygroundConversation.t() \| nil` | Conversation or nil | Fetches a conversation by id |
| `get_active_conversation/1` | `(String.t()) :: PlaygroundConversation.t() \| nil` | Conversation or nil | Fetches the active conversation for a playground |
| `increment_conversation_stats/2` | `(PlaygroundConversation.t(), keyword()) :: {non_neg_integer(), nil}` | Bulk-update result | Increments aggregated stats (e.g. `[total_runs: 1, total_tokens: 500]`) |
| `create_run/1` | `(map()) :: {:ok, PlaygroundRun.t()} \| {:error, Ecto.Changeset.t()}` | New run or changeset error | Inserts a run record; required fields: `conversation_id`, `playground_id`, `user_id`, `run_type`, `trigger_message` |
| `get_run/1` | `(String.t()) :: PlaygroundRun.t() \| nil` | Run or nil | Fetches a run by id |
| `get_run!/1` | `(String.t()) :: PlaygroundRun.t()` | Run (raises if missing) | Fetches a run by id, raises `Ecto.NoResultsError` if not found |
| `mark_run_running/1` | `(PlaygroundRun.t()) :: {:ok, PlaygroundRun.t()} \| {:error, Ecto.Changeset.t()}` | Updated run | Sets status `"running"` and `started_at` timestamp |
| `complete_run/2` | `(PlaygroundRun.t(), map()) :: {:ok, PlaygroundRun.t()} \| {:error, Ecto.Changeset.t()}` | Completed run | Sets `completed_at`, `duration_ms`; `attrs` should include `code_after`, `run_summary`, token/cost fields; defaults `status` to `"completed"` |
| `fail_run/2` | `(PlaygroundRun.t(), String.t()) :: {:ok, PlaygroundRun.t()} \| {:error, Ecto.Changeset.t()}` | Failed run | Sets status `"failed"`, `error_message`, `completed_at`, `duration_ms` |
| `list_runs/2` | `(String.t(), keyword()) :: [PlaygroundRun.t()]` | List of runs | Lists runs for a conversation; `opts: [limit: 50]` |
| `append_event/2` | `(PlaygroundRun.t(), map()) :: {:ok, PlaygroundEvent.t()} \| {:error, Ecto.Changeset.t()}` | New event | Inserts an event; auto-assigns `sequence` via `next_sequence/1` if omitted; required fields: `event_type`, `content` |
| `list_events/2` | `(String.t(), keyword()) :: [PlaygroundEvent.t()]` | List of events | Lists events for a run; `opts: [limit: 1000]` |
| `list_recent_events_for_playground/2` | `(String.t(), keyword()) :: [PlaygroundEvent.t()]` | List of events | Lists recent events across all runs of a playground; `opts: [limit: 200]` |
| `list_active_conversation_events/2` | `(String.t(), keyword()) :: [PlaygroundEvent.t()]` | List of events | Events for the active conversation only — used to hydrate the chat UI on reconnect; returns `[]` if no active conversation; `opts: [limit: 200]` |
| `thread_history/2` | `(String.t(), keyword()) :: [%{role: String.t(), content: String.t()}]` | List of role/content maps | Converts active-conversation events into `[%{role, content}]` pairs for LLM context injection; `opts: [limit: 20]` (message pairs, not raw events) |
| `next_sequence/1` | `(String.t()) :: non_neg_integer()` | Next sequence integer | Returns the next sequence number for events in a run (count of existing events) |

## Database

| Table | Key columns |
|-------|-------------|
| `playground_conversations` | unique `(playground_id)`, denormalized `organization_id`, `project_id` |
| `playground_runs` | indexes on `(conversation_id)`, `(playground_id, inserted_at)`, `(status, updated_at)`, `(organization_id)` |
| `playground_events` | unique `(run_id, sequence)`, index on `(event_type)` |

All FKs cascade on delete (deleting a playground removes its conversation, runs, and events).

## Sequence Auto-Increment

`append_event/2` picks the next `sequence` automatically via `next_sequence/1` when the
caller omits it. Callers who want to pin the first event to sequence 0 (e.g. `KickoffWorker`)
pass `sequence: 0` explicitly.

## Fixtures

`Blackboex.PlaygroundConversationsFixtures` is auto-imported via `DataCase` and `ConnCase`:
- `playground_conversation_fixture(attrs)` — get-or-create for a playground (auto-created if not passed)
- `playground_run_fixture(attrs)` — default `run_type: "edit"`, `status: "pending"`
- `playground_event_fixture(attrs)` — default `event_type: "user_message"`, auto-sequence

## Relationship to Blackboex.Conversations

Deliberately NOT reused. `Blackboex.Conversations.Conversation` has a rigid
`unique_constraint [:project_id, :api_id]` and `belongs_to :api`; retrofitting to support
either `api_id` or `playground_id` would require a risky data migration of the existing
runs/events/stats tables plus ongoing semantic confusion. Separate tables keep the two
agent domains isolated.
