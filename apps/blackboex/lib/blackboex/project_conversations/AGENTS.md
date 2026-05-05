# ProjectConversations Context

Persisted chat conversations, runs, and events for the **Project-level
agent** (the orchestrator that turns one user message into a multi-step
`Plan` and dispatches each step to the matching per-artifact agent).

Intentionally separate from `Blackboex.Conversations`,
`Blackboex.PlaygroundConversations`, `Blackboex.PageConversations`, and
`Blackboex.FlowConversations` so each agent domain evolves independently.

## Modules

| Module | Role |
|--------|------|
| `Blackboex.ProjectConversations` | Facade — get/start/archive conversation, create/mark/complete/fail run, append/list events, `next_sequence/1`, `increment_conversation_stats/2`. |
| `ProjectConversation` | Schema — `belongs_to :project`, `belongs_to :organization`, `status: "active" \| "archived"`, aggregated `total_runs/events/tokens/cost_cents`. Partial unique index: at most one `active` per `project_id`. |
| `ProjectRun` | Schema — `belongs_to :conversation`, `belongs_to :project`, `belongs_to :organization`, `belongs_to :user`. Fields: `run_type` (`"plan" \| "execute"`), `status` (`"pending" \| "running" \| "completed" \| "failed" \| "canceled"`), `trigger_message`, `run_summary`, `error_message`, tokens, cost, duration, timing. Changesets: `changeset/2`, `running_changeset/2`, `completion_changeset/2`. |
| `ProjectEvent` | Schema — `belongs_to :run`, `sequence` (unique per run), `event_type` (`"user_message" \| "assistant_message" \| "plan_drafted" \| "plan_approved" \| "task_dispatched" \| "task_completed" \| "task_failed" \| "completed" \| "failed"`), `content`, `metadata`. |
| `ProjectConversationQueries` | Pure `Ecto.Query` builders — no `Repo.*` calls. |

## Public API

| Function | Signature | Description |
|----------|-----------|-------------|
| `get_or_create_active_conversation/2` | `(project_id, org_id) :: {:ok, ProjectConversation.t()} \| {:error, Ecto.Changeset.t()}` | Returns existing active or creates one (race-safe). |
| `start_new_conversation/2` | `(project_id, org_id) :: {:ok, ProjectConversation.t()} \| {:error, Ecto.Changeset.t()}` | Archives the current active and creates a new one. |
| `archive_active_conversation/1` | `(project_id) :: {:ok, ProjectConversation.t()} \| :noop \| {:error, Ecto.Changeset.t()}` | Marks active as archived. |
| `get_conversation/1`, `get_active_conversation/1` | by id / by project_id | Fetch helpers. |
| `increment_conversation_stats/2` | `(ProjectConversation.t(), keyword()) :: {non_neg_integer(), nil}` | Bulk-updates aggregated counters. |
| `create_run/1` | `(map()) :: {:ok, ProjectRun.t()} \| {:error, Ecto.Changeset.t()}` | Required: `conversation_id`, `project_id`, `organization_id`, `user_id`, `run_type`. |
| `get_run/1`, `get_run!/1` | by id | Fetch helpers. |
| `mark_run_running/1` | `(ProjectRun.t()) :: {:ok, ProjectRun.t()} \| {:error, Ecto.Changeset.t()}` | Sets `"running"` + `started_at`. |
| `complete_run/2` | `(ProjectRun.t(), map()) :: {:ok, ProjectRun.t()} \| {:error, Ecto.Changeset.t()}` | Sets `completed_at`, `duration_ms`. |
| `fail_run/2` | `(ProjectRun.t(), reason) :: {:ok, ProjectRun.t()} \| {:error, Ecto.Changeset.t()}` | Sets `"failed"`, `error_message`, `completed_at`. |
| `list_runs/2` | `(conversation_id, opts) :: [ProjectRun.t()]` | `opts: [limit: 50]`, ordered by `inserted_at DESC`. |
| `append_event/2` | `(ProjectRun.t(), map()) :: {:ok, ProjectEvent.t()} \| {:error, Ecto.Changeset.t()}` | Auto-assigns `sequence` if omitted. |
| `list_events/2` | `(run_id, opts) :: [ProjectEvent.t()]` | `opts: [limit: 1000]`, ordered by `sequence ASC`. |
| `list_recent_events_for_project/2` | `(project_id, opts) :: [ProjectEvent.t()]` | All runs of a project; `opts: [limit: 200]`. |
| `list_active_conversation_events/2` | `(project_id, opts) :: [ProjectEvent.t()]` | Only the active conversation; `[]` if none. |
| `next_sequence/1` | `(run_id) :: non_neg_integer()` | Count of events for the run. |

## Database

| Table | Key columns |
|-------|-------------|
| `project_conversations` | partial unique `(project_id) WHERE status='active'`; indexes on `(organization_id)`, `(project_id, inserted_at)` |
| `project_runs` | indexes on `(conversation_id)`, `(project_id, inserted_at)`, `(status, updated_at)`, `(organization_id)` |
| `project_events` | unique `(run_id, sequence)`, index on `(event_type)` |

All FKs cascade on delete (deleting a project removes its conversations,
runs, and events).

## Fixtures

`Blackboex.ProjectConversationsFixtures` is auto-imported via `DataCase`
and `ConnCase`:
- `project_conversation_fixture(attrs)` — get-or-create for a project (auto-created if not passed).
- `project_run_fixture(attrs)` — default `run_type: "plan"`, `status: "pending"`.
- `project_event_fixture(attrs)` — default `event_type: "user_message"`, auto-sequence.
- Named setup `:create_project_conversation` — creates an active conversation for a context with `:project`.

## Relationship to other conversation contexts

Each domain has its own aggregate fields and enum values:
- `Blackboex.Conversations` → 1:1 with API
- `Blackboex.PlaygroundConversations` → 1:1 active per Playground (code)
- `Blackboex.PageConversations` → 1:1 active per Page (markdown content)
- `Blackboex.FlowConversations` → 1:1 active per Flow (JSONB definition map)
- `Blackboex.ProjectConversations` → 1:1 active per Project (orchestration agent)

Merging them would require intrusive schema changes and obscure per-domain
invariants.
