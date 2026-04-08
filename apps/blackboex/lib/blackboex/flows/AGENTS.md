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

## Fixtures

- `FlowsFixtures.flow_fixture/1` — creates flow with user + org
- Named setups: `:create_flow`, `:create_org_and_flow`
