# AGENTS.md — Flows Context

Facade: `Blackboex.Flows` (`flows.ex`). All web/worker code calls through this facade. Direct sub-module access is forbidden.

## Schema

| Module | Purpose | File |
|--------|---------|------|
| `Flows.Flow` | Ecto schema — name, slug, description, status, definition (JSONB) | `flows/flow.ex` |

## Query Modules

| Module | Scope | File |
|--------|-------|------|
| `Flows.FlowQueries` | Flow record lookups, list, search | `flows/flow_queries.ex` |

**Rule:** All `Ecto.Query` composition lives in `*Queries` modules. No Repo calls inside queries.

## Public API

| Function | Purpose |
|----------|---------|
| `create_flow(attrs)` | Create a new flow |
| `list_flows(org_id)` | List all flows for an org, ordered by inserted_at DESC |
| `list_flows(org_id, opts)` | List with search filter |
| `list_flows_for_project(project_id)` | List flows for a project, ordered by inserted_at DESC |
| `list_for_project(project_id, opts \\ [])` | List flows for a project ordered by name ASC; accepts `:limit` opt (default 50) |
| `get_flow(org_id, flow_id)` | Get by org + id (IDOR-safe) |
| `get_for_org(org_id, flow_id)` | Org-scoped fetch by id; returns `nil` when not found or cross-org |
| `update_flow(flow, attrs)` | Update name/description/status |
| `move_flow(flow, new_project_id)` | Move flow to a different project within the same org; validates org membership via `ensure_project_in_org`; returns `{:error, :forbidden}` on cross-org attempt |
| `update_definition(flow, definition)` | Save Drawflow graph JSON |
| `delete_flow(flow)` | Delete flow |

## Status Machine

`draft` → `active` → `archived`

## Key Invariants

- **Organization scoping**: Always use `org_id` in lookups — never expose cross-org data
- **Slug uniqueness**: Per organization, auto-generated from name
- **Definition as opaque JSONB**: Server does not validate Drawflow internal structure


## Web Layer

| LiveView | Route | Purpose |
|----------|-------|---------|
| `FlowLive.Index` | `/flows` | Card listing, search, create modal, delete |
| `FlowLive.Edit` | `/flows/:id/edit` | Full-screen Drawflow editor with node palette |

## JS Integration

- `DrawflowEditor` hook in `assets/js/hooks/drawflow_editor.js`
- Drawflow vendored in `assets/vendor/drawflow.min.{js,css}`
- Communication: `export_definition` (server→client), `save_definition` (client→server)
- Canvas element uses `phx-update="ignore"` to prevent LiveView DOM interference

## Templates

| Module | ID | Description |
|--------|----|-------------|
| `Samples.FlowTemplates.HelloWorld` | `hello_world` | Contact Router — 3-branch flow (email/phone/error) |
| `Samples.FlowTemplates.Notification` | `notification` | Simple sub-flow: start → format → end |
| `Samples.FlowTemplates.AllNodesDemo` | `all_nodes_demo` | All 9 node types in a 10-node, 2-branch flow |

Registry: `Flows.Templates` — `list/0`, `get/1`, `list_by_category/0`

`Flows.Templates` is a compatibility facade over `Blackboex.Samples.Manifest`.
Add or update Flow sample payloads in `Blackboex.Samples.FlowTemplates.*` and register them through `Blackboex.Samples.Flow`.
Managed sample workspace Flows store `sample_uuid` and `sample_manifest_version`; manual template-created Flows do not.

## Fixtures

- `FlowsFixtures.flow_fixture/1` — creates flow with user + org
- `FlowsFixtures.flow_from_template_fixture/1` — creates flow from template
- Named setups: `:create_flow`, `:create_org_and_flow`
