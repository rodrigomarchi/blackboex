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
| `create_flow(attrs)` | Create flow with billing enforcement |
| `list_flows(org_id)` | List all flows for an org |
| `list_flows(org_id, opts)` | List with search filter |
| `get_flow(org_id, flow_id)` | Get by org + id (IDOR-safe) |
| `update_flow(flow, attrs)` | Update name/description/status |
| `update_definition(flow, definition)` | Save Drawflow graph JSON |
| `delete_flow(flow)` | Delete flow |

## Status Machine

`draft` → `active` → `archived`

## Key Invariants

- **Organization scoping**: Always use `org_id` in lookups — never expose cross-org data
- **Slug uniqueness**: Per organization, auto-generated from name
- **Definition as opaque JSONB**: Server does not validate Drawflow internal structure
- **Billing enforcement**: Uses same `max_apis` limit via `Enforcement.check_limit/2`

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
| `Templates.HelloWorld` | `hello_world` | Contact Router — 3-branch flow (email/phone/error) |
| `Templates.Notification` | `notification` | Simple sub-flow: start → format → end |
| `Templates.AllNodesDemo` | `all_nodes_demo` | All 9 node types in a 10-node, 2-branch flow |

Registry: `Flows.Templates` — `list/0`, `get/1`, `list_by_category/0`

## Fixtures

- `FlowsFixtures.flow_fixture/1` — creates flow with user + org
- `FlowsFixtures.flow_from_template_fixture/1` — creates flow from template
- Named setups: `:create_flow`, `:create_org_and_flow`
