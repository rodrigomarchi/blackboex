# PageConversations Context

Persisted chat conversations, runs, and events for the **Page editor AI agent**.
Intentionally separate from `Blackboex.PlaygroundConversations` and
`Blackboex.Conversations` (which are 1:1 with a Playground or API) so each
agent domain evolves independently.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.PageConversations` | Facade — get/start/archive conversation, create/mark/complete/fail run, append/list events, `thread_history/2`, `increment_conversation_stats/2`, `next_sequence/1`. |
| `PageConversation` | Schema — `belongs_to :page`, `belongs_to :organization`, `belongs_to :project`, `status: "active" \| "archived"`, aggregated `total_runs/events/tokens/cost_cents`. Partial unique index: at most one `active` per `page_id`. |
| `PageRun` | Schema — `belongs_to :conversation`, `belongs_to :page`, `belongs_to :user`. Fields: `run_type` (`"generate" \| "edit"`), `status` (`"pending" \| "running" \| "completed" \| "failed" \| "canceled"`), `trigger_message`, `content_before`, `content_after`, `run_summary`, `error_message`, tokens, cost, duration, timing. Changesets: `changeset/2`, `running_changeset/2`, `completion_changeset/2`. |
| `PageEvent` | Schema — `belongs_to :run`, `sequence` (unique per run), `event_type` (`"user_message" \| "assistant_message" \| "content_delta" \| "completed" \| "failed"`), `content`, `metadata`. |
| `PageConversationQueries` | Pure `Ecto.Query` builders — no `Repo.*` calls. |

## Public API

| Function | Signature | Returns | Description |
|----------|-----------|---------|-------------|
| `get_or_create_active_conversation/3` | `(page_id, org_id, project_id) :: {:ok, PageConversation.t()} \| {:error, Ecto.Changeset.t()}` | Active conversation | Returns existing active, or creates one |
| `start_new_conversation/3` | `(page_id, org_id, project_id) :: {:ok, PageConversation.t()} \| {:error, Ecto.Changeset.t()}` | Fresh active | Archives the current active (if any) and creates a new one |
| `archive_active_conversation/1` | `(page_id) :: {:ok, PageConversation.t()} \| :noop \| {:error, Ecto.Changeset.t()}` | Archived, `:noop`, or error | Sets `status: "archived"` on the active |
| `get_conversation/1` | `(id) :: PageConversation.t() \| nil` | Conversation or nil | By id |
| `get_active_conversation/1` | `(page_id) :: PageConversation.t() \| nil` | Conversation or nil | Active by page |
| `increment_conversation_stats/2` | `(PageConversation.t(), keyword()) :: {non_neg_integer(), nil}` | Bulk-update result | Increments aggregated counters (e.g., `[total_runs: 1, total_input_tokens: 100]`) |
| `create_run/1` | `(map()) :: {:ok, PageRun.t()} \| {:error, Ecto.Changeset.t()}` | New run or error | Required: `conversation_id`, `page_id`, `organization_id`, `user_id`, `run_type` |
| `get_run/1`, `get_run!/1` | `(id) :: PageRun.t() \| nil` / raises | Run | Fetch by id |
| `mark_run_running/1` | `(PageRun.t()) :: {:ok, PageRun.t()} \| {:error, Ecto.Changeset.t()}` | Updated | Sets `"running"` + `started_at` |
| `complete_run/2` | `(PageRun.t(), map()) :: {:ok, PageRun.t()} \| {:error, Ecto.Changeset.t()}` | Completed | Sets `completed_at`, `duration_ms`; `attrs` usually includes `content_after`, `run_summary`, tokens/cost |
| `fail_run/2` | `(PageRun.t(), reason) :: {:ok, PageRun.t()} \| {:error, Ecto.Changeset.t()}` | Failed | Sets `"failed"`, `error_message`, `completed_at` |
| `list_runs/2` | `(conversation_id, opts) :: [PageRun.t()]` | Runs | `opts: [limit: 50]`, ordered by `inserted_at DESC` |
| `append_event/2` | `(PageRun.t(), map()) :: {:ok, PageEvent.t()} \| {:error, Ecto.Changeset.t()}` | New event | Auto-assigns `sequence` via `next_sequence/1` if omitted |
| `list_events/2` | `(run_id, opts) :: [PageEvent.t()]` | Events | `opts: [limit: 1000]`, ordered by `sequence ASC` |
| `list_recent_events_for_page/2` | `(page_id, opts) :: [PageEvent.t()]` | Events | All runs of a page; `opts: [limit: 200]` |
| `list_active_conversation_events/2` | `(page_id, opts) :: [PageEvent.t()]` | Events | Only from the active conversation; hydrates the chat UI on reconnect; `[]` if none active |
| `thread_history/2` | `(page_id, opts) :: [%{role, content}]` | Message pairs | Converts user + assistant/completed events into `[%{role, content}]` oldest-first; `opts: [limit: 20]` |
| `next_sequence/1` | `(run_id) :: non_neg_integer()` | Next sequence | Count of events for the run |

## Database

| Table | Key columns |
|-------|-------------|
| `page_conversations` | partial unique `(page_id) WHERE status='active'`; indexes on `(organization_id)`, `(project_id)`, `(page_id, inserted_at)` |
| `page_runs` | indexes on `(conversation_id)`, `(page_id, inserted_at)`, `(status, updated_at)`, `(organization_id)` |
| `page_events` | unique `(run_id, sequence)`, index on `(event_type)` |

All FKs cascade on delete (deleting a page removes its conversation, runs, and events).

## Fixtures

`Blackboex.PageConversationsFixtures` is auto-imported via `DataCase` and `ConnCase`:
- `page_conversation_fixture(attrs)` — get-or-create for a page (auto-created if not passed). Uses `Repo` directly so the fixture does not depend on the facade.
- `page_run_fixture(attrs)` — default `run_type: "edit"`, `status: "pending"`.
- `page_event_fixture(attrs)` — default `event_type: "user_message"`, auto-sequence.

## Relationship to other conversation contexts

Deliberately not reused:
- `Blackboex.Conversations` → 1:1 with API
- `Blackboex.PlaygroundConversations` → 1:1 with Playground
- `Blackboex.PageConversations` → 1:1 active per Page

Each domain has its own enum values, aggregate fields (code/content), and
lifecycle. Merging them would require intrusive schema changes and would
obscure per-domain invariants.
