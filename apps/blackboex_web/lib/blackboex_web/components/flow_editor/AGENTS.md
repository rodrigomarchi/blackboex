# Flow Editor Components — AGENTS.md

Function components for the flow editor (`/flows/:id/edit`).
All use `use BlackboexWeb, :html`. Events bubble to the parent `FlowLive.Edit` LiveView.

## Component Catalog

| File | Component | Description | Lines |
|------|-----------|-------------|-------|
| `flow_header.ex` | `flow_header/1` | Top bar: flow name, status badge, webhook URL, action buttons | ~100 |
| `node_palette.ex` | `node_palette/1` | Icon-only draggable sidebar for adding nodes to canvas | ~30 |
| `properties_drawer.ex` | `properties_drawer/1` | Side panel shell for node configuration (imports NodeProperties) | ~75 |
| `node_properties.ex` | `node_properties/1` | 12 pattern-matched clauses rendering type-specific property forms. Also defines `prop_field/1`, `prop_select/1`, `properties_tabs/1` | ~1060 |
| `json_preview_modal.ex` | `json_preview_modal/1` | Modal with CodeEditor hook showing formatted JSON definition | ~75 |
| `run_modal.ex` | `run_modal/1` | Modal for test-running a flow with JSON input and viewing results | ~100 |

## Size Exception

`node_properties.ex` exceeds the 150-line component limit by design. It contains 12 clauses of the same function component, one per node type (start, elixir_code, condition, end, http_request, delay, sub_flow, for_each, webhook_wait, fail, debug, fallback). Splitting into 12 files would harm discoverability without improving maintainability.

## Rules

- **No socket access** — these are pure function components. Events use `phx-click`, `phx-blur`, `phx-change` which bubble to the parent LiveView.
- **No business logic** — rendering only. Schema manipulation, field parsing, and state variable extraction live in `FlowLive.EditHelpers`.
- **Hooks** — `phx-hook="CodeEditor"` and `phx-hook="DrawflowEditor"` bind to the LiveView process, not the component module. They work correctly in function components.
