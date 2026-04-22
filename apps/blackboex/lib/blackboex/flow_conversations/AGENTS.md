# FlowConversations Context

Persisted chat conversations, runs, and events for the **Flow editor AI agent**.
Intentionally separate from `Blackboex.Conversations`, `Blackboex.PlaygroundConversations`,
and `Blackboex.PageConversations` so each agent domain evolves independently.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.FlowConversations` | Facade — get/start/archive conversation, create/mark/complete/fail run, append/list events, `thread_history/2`, `increment_conversation_stats/2`, `next_sequence/1`. |
| `FlowConversation` | Schema — `belongs_to :flow`, `belongs_to :organization`, `belongs_to :project`, `status: "active" \| "archived"`, aggregated `total_runs/events/tokens/cost_cents`. Partial unique index: at most one `active` per `flow_id`. |
| `FlowRun` | Schema — `belongs_to :conversation`, `belongs_to :flow`, `belongs_to :user`. Fields: `run_type` (`"generate" \| "edit"`), `status` (`"pending" \| "running" \| "completed" \| "failed" \| "canceled"`), `trigger_message`, `definition_before` (map), `definition_after` (map), `run_summary`, `error_message`, tokens, cost, duration, timing. Changesets: `changeset/2`, `running_changeset/2`, `completion_changeset/2`. |
| `FlowEvent` | Schema — `belongs_to :run`, `sequence` (unique per run), `event_type` (`"user_message" \| "assistant_message" \| "definition_delta" \| "completed" \| "failed"`), `content`, `metadata`. |
| `FlowConversationQueries` | Pure `Ecto.Query` builders — no `Repo.*` calls. |

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `get_or_create_active_conversation/3` | `(flow_id, org_id, project_id) :: {:ok, FlowConversation.t()} \| {:error, Ecto.Changeset.t()}` | Active conversation | Returns existing active, or creates one |
| `start_new_conversation/3` | `(flow_id, org_id, project_id) :: {:ok, FlowConversation.t()} \| {:error, Ecto.Changeset.t()}` | Fresh active | Archives the current active (if any) and creates a new one |
| `archive_active_conversation/1` | `(flow_id) :: {:ok, FlowConversation.t()} \| :noop \| {:error, Ecto.Changeset.t()}` | Archived, `:noop`, or error | Sets `status: "archived"` on the active |
| `get_conversation/1` | `(id) :: FlowConversation.t() \| nil` | Conversation or nil | By id |
| `get_active_conversation/1` | `(flow_id) :: FlowConversation.t() \| nil` | Conversation or nil | Active by flow |
| `increment_conversation_stats/2` | `(FlowConversation.t(), keyword()) :: {non_neg_integer(), nil}` | Bulk-update result | Increments aggregated counters |
| `create_run/1` | `(map()) :: {:ok, FlowRun.t()} \| {:error, Ecto.Changeset.t()}` | New run or error | Required: `conversation_id`, `flow_id`, `organization_id`, `user_id`, `run_type` |
| `get_run/1`, `get_run!/1` | `(id) :: FlowRun.t() \| nil` / raises | Run | Fetch by id |
| `mark_run_running/1` | `(FlowRun.t()) :: {:ok, FlowRun.t()} \| {:error, Ecto.Changeset.t()}` | Updated | Sets `"running"` + `started_at` |
| `complete_run/2` | `(FlowRun.t(), map()) :: {:ok, FlowRun.t()} \| {:error, Ecto.Changeset.t()}` | Completed | Sets `completed_at`, `duration_ms`; `attrs` usually includes `definition_after`, `run_summary`, tokens/cost |
| `fail_run/2` | `(FlowRun.t(), reason) :: {:ok, FlowRun.t()} \| {:error, Ecto.Changeset.t()}` | Failed | Sets `"failed"`, `error_message`, `completed_at` |
| `list_runs/2` | `(conversation_id, opts) :: [FlowRun.t()]` | Runs | `opts: [limit: 50]`, ordered by `inserted_at DESC` |
| `append_event/2` | `(FlowRun.t(), map()) :: {:ok, FlowEvent.t()} \| {:error, Ecto.Changeset.t()}` | New event | Auto-assigns `sequence` via `next_sequence/1` if omitted |
| `list_events/2` | `(run_id, opts) :: [FlowEvent.t()]` | Events | `opts: [limit: 1000]`, ordered by `sequence ASC` |
| `list_recent_events_for_flow/2` | `(flow_id, opts) :: [FlowEvent.t()]` | Events | All runs of a flow; `opts: [limit: 200]` |
| `list_active_conversation_events/2` | `(flow_id, opts) :: [FlowEvent.t()]` | Events | Only from the active conversation; hydrates the chat UI on reconnect; `[]` if none active |
| `thread_history/2` | `(flow_id, opts) :: [%{role, content}]` | Message pairs | Converts user + assistant/completed events into `[%{role, content}]` oldest-first; `opts: [limit: 20]` |
| `next_sequence/1` | `(run_id) :: non_neg_integer()` | Next sequence | Count of events for the run |

## Database

| Table | Key columns |
|-------|-------------|
| `flow_conversations` | partial unique `(flow_id) WHERE status='active'`; indexes on `(organization_id)`, `(project_id)`, `(flow_id, inserted_at)` |
| `flow_runs` | indexes on `(conversation_id)`, `(flow_id, inserted_at)`, `(status, updated_at)`, `(organization_id)`. `definition_before`/`definition_after` are JSONB maps. |
| `flow_events` | unique `(run_id, sequence)`, index on `(event_type)` |

All FKs cascade on delete (deleting a flow removes its conversation, runs, and events).

## Fixtures

`Blackboex.FlowConversationsFixtures` is auto-imported via `DataCase` and `ConnCase`:
- `flow_conversation_fixture(attrs)` — get-or-create for a flow (auto-created if not passed).
- `flow_run_fixture(attrs)` — default `run_type: "edit"`, `status: "pending"`, empty `definition_before`.
- `flow_event_fixture(attrs)` — default `event_type: "user_message"`, auto-sequence.

## Relationship to other conversation contexts

Each domain has its own aggregate fields and enum values:
- `Blackboex.Conversations` → 1:1 with API
- `Blackboex.PlaygroundConversations` → 1:1 active per Playground (code)
- `Blackboex.PageConversations` → 1:1 active per Page (markdown content)
- `Blackboex.FlowConversations` → 1:1 active per Flow (JSONB definition map)

Merging them would require intrusive schema changes and obscure per-domain invariants.
