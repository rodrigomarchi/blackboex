# AGENTS.md — Backpex Admin Panel

This file documents the Backpex-powered admin panel at `/admin`. It covers all 23 LiveResource modules, the shared patterns they follow, authorization, field types, and how to extend the panel.

---

## Overview

The admin panel lives at `/admin` and is built entirely with [Backpex](https://github.com/naymspace/backpex). Every resource is a `Backpex.LiveResource` — a Phoenix LiveView that provides list, show, create, and edit views automatically from a field definition.

Access is restricted to users where `is_platform_admin: true`. There is a custom dashboard at `/admin` (not a LiveResource) that shows platform-wide row counts with links to each resource.

The admin panel uses a **separate asset bundle** (`admin.css` / `admin.js`) loaded from `admin_root.html.heex`.

---

## Standard LiveResource Pattern

Every admin resource follows this exact structure:

```elixir
defmodule BlackboexWeb.Admin.FooLive do
  @moduledoc """
  Backpex LiveResource for managing/viewing Foo in the admin panel.
  Read-only.  # or: Editable with caution.
  """

  alias Blackboex.SomeContext.Foo

  use Backpex.LiveResource,
    adapter_config: [
      schema: Foo,
      repo: Blackboex.Repo,
      update_changeset: &Foo.admin_changeset/3,
      create_changeset: &Foo.admin_changeset/3
    ],
    layout: {BlackboexWeb.Layouts, :admin}
    # optional: init_order: %{by: :inserted_at, direction: :desc}

  @impl Backpex.LiveResource
  def singular_name, do: "Foo"

  @impl Backpex.LiveResource
  def plural_name, do: "Foos"

  @impl Backpex.LiveResource
  def fields do
    [
      some_field: %{
        module: Backpex.Fields.Text,
        label: "Some Field",
        searchable: true           # enables live search on this column
      },
      other_field: %{
        module: Backpex.Fields.DateTime,
        label: "Created",
        only: [:index, :show]      # hides from create/edit forms
      }
    ]
  end

  @impl Backpex.LiveResource
  def can?(assigns, _action, _item), do: platform_admin?(assigns)

  defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
  defp platform_admin?(_), do: false
end
```

### Required `use Backpex.LiveResource` options

| Option | Purpose |
|---|---|
| `adapter_config: [schema: ...]` | The Ecto schema module |
| `adapter_config: [repo: ...]` | Always `Blackboex.Repo` |
| `adapter_config: [update_changeset: ...]` | Called on edit — always `&Schema.admin_changeset/3` |
| `adapter_config: [create_changeset: ...]` | Called on create — always `&Schema.admin_changeset/3` |
| `layout: {BlackboexWeb.Layouts, :admin}` | Required on every resource |

### Optional top-level options

| Option | Purpose |
|---|---|
| `init_order: %{by: :field, direction: :desc}` | Default sort order for the index list |

---

## Field Types Reference

Every field type used across the 23 resources:

### `Backpex.Fields.Text`
Plain text input. Used for strings, UUIDs, and short values.
```elixir
email: %{module: Backpex.Fields.Text, label: "Email", searchable: true}
```

### `Backpex.Fields.Boolean`
Checkbox. Used for boolean flags.
```elixir
is_platform_admin: %{module: Backpex.Fields.Boolean, label: "Platform Admin"}
```

### `Backpex.Fields.Select`
Dropdown with explicit options list. Used for enum fields.
```elixir
status: %{
  module: Backpex.Fields.Select,
  label: "Status",
  options: [Draft: "draft", Published: "published"]
}
```
Options use `[Label: "db_value"]` keyword list syntax. Atom values are also valid (e.g., `[Owner: :owner]`).

### `Backpex.Fields.DateTime`
DateTime picker. Used for timestamps.
```elixir
inserted_at: %{module: Backpex.Fields.DateTime, label: "Created", only: [:index, :show]}
```

### `Backpex.Fields.Date`
Date-only picker. Used for date fields (not datetime).
```elixir
date: %{module: Backpex.Fields.Date, label: "Date"}
```

### `Backpex.Fields.Number`
Numeric input. Used for integers, counters, durations, token counts, costs.
```elixir
cost_cents: %{module: Backpex.Fields.Number, label: "Cost (cents)"}
```

### `Backpex.Fields.Textarea`
Multi-line text area. Used for source code, prompts, LLM responses, large text blobs.
```elixir
source_code: %{module: Backpex.Fields.Textarea, label: "Source Code"}
```

### Custom `render:` function
Used for JSONB/map fields and security-sensitive fields that need custom presentation. Always combined with `readonly: true` and `only: [:show]`.
```elixir
metadata: %{
  module: Backpex.Fields.Text,
  label: "Metadata",
  readonly: true,
  only: [:show],
  render: fn assigns ->
    value = Map.get(assigns.item, :metadata)
    text = if is_map(value) and value != %{}, do: Jason.encode!(value, pretty: true), else: "—"
    assigns = Phoenix.Component.assign(assigns, :text, text)
    ~H"""
    <div
      id="admin-metadata"
      phx-hook="CodeEditor"
      data-language="json"
      data-readonly="true"
      data-minimal="true"
      data-value={@text}
      class="rounded-md overflow-hidden border [&_.cm-editor]:max-h-96"
      phx-update="ignore"
    />
    """
  end
}
```

### Field visibility: `only:`
Controls which views a field appears in:
- `only: [:index, :show]` — visible in list and detail, hidden from forms
- `only: [:show]` — visible in detail view only
- Omitting `only:` — appears everywhere (index, show, create, edit)

### Field mutability: `readonly: true`
Prevents the field from being edited. Used together with `only: [:show]` for display-only computed or sensitive fields. Note: `readonly` is a display hint — it does not replace changeset-level field restrictions.

---

## All 23 Resources

### Core

| Module | Schema | Route | Notes |
|---|---|---|---|
| `Admin.UserLive` | `Blackboex.Accounts.User` | `/admin/users` | Editable: `email`, `is_platform_admin`, `confirmed_at`. Searchable by email. |
| `Admin.UserTokenLive` | `Blackboex.Accounts.UserToken` | `/admin/user-tokens` | Token binary hidden via custom render for security. Sorted newest-first. |
| `Admin.OrganizationLive` | `Blackboex.Organizations.Organization` | `/admin/organizations` | Editable: `name`, `slug`, `plan`. Searchable by name/slug. |
| `Admin.MembershipLive` | `Blackboex.Organizations.Membership` | `/admin/memberships` | Edit limited to `role` changes only. |
| `Admin.ApiLive` | `Blackboex.Apis.Api` | `/admin/apis` | Editable. JSONB fields (`param_schema`, `example_request`, `example_response`) rendered read-only with pretty-printed JSON in show view. |

### API Data

| Module | Schema | Route | Notes |
|---|---|---|---|
| `Admin.ApiKeyLive` | `Blackboex.Apis.ApiKey` | `/admin/api-keys` | Searchable by `key_prefix` and `label`. Key hash not exposed. |
| `Admin.ApiVersionLive` | `Blackboex.Apis.ApiVersion` | `/admin/api-versions` | Sorted newest-first. Compilation errors rendered as pre-formatted text. |
| `Admin.AgentConversationLive` | `Blackboex.Conversations.Conversation` | `/admin/agent-conversations` | Token/cost aggregates visible. Searchable by `status`. |
| `Admin.AgentRunLive` | `Blackboex.Conversations.Run` | `/admin/agent-runs` | Full run detail including `final_code`, `error_summary`, `run_summary` in show view. |
| `Admin.AgentEventLive` | `Blackboex.Conversations.Event` | `/admin/agent-events` | Schema has `inserted_at` only — no `updated_at`. Content shown in show view only. |
| `Admin.DataStoreEntryLive` | `Blackboex.Apis.DataStore.Entry` | `/admin/data-store-entries` | Editable with caution. JSONB `value` rendered with `inspect/2` in show view. |
| `Admin.InvocationLogLive` | `Blackboex.Apis.InvocationLog` | `/admin/invocation-logs` | Sorted newest-first. Searchable by method, path, IP. |
| `Admin.MetricRollupLive` | `Blackboex.Apis.MetricRollup` | `/admin/metric-rollups` | Hourly rollups with p95 duration. |

### Testing

| Module | Schema | Route | Notes |
|---|---|---|---|
| `Admin.TestRequestLive` | `Blackboex.Testing.TestRequest` | `/admin/test-requests` | Sorted newest-first. Headers rendered via `inspect/2`. |
| `Admin.TestSuiteLive` | `Blackboex.Testing.TestSuite` | `/admin/test-suites` | Pass/fail counters. `results` JSONB shown in detail view. |

### LLM & Audit

| Module | Schema | Route | Notes |
|---|---|---|---|
| `Admin.LlmUsageLive` | `Blackboex.LLM.Usage` | `/admin/llm-usage` | Sorted newest-first. Searchable by provider, model, operation. |
| `Admin.AuditLogLive` | `Blackboex.Audit.AuditLog` | `/admin/audit-logs` | Sorted newest-first. JSONB `metadata` rendered in detail view. |
| `Admin.VersionLive` | `Blackboex.Audit.Version` | `/admin/versions` | ExAudit row-level change records. Sorted by `recorded_at` desc. `patch` map rendered with `inspect/2`. |

### Dashboard (not a LiveResource)

| Module | Route | Notes |
|---|---|---|
| `Admin.DashboardLive` | `/admin` | Plain `use BlackboexWeb, :live_view`. Runs `Repo.aggregate(..., :count)` for all 22 schemas at mount. Stat cards link to the corresponding LiveResource index. |

---

## Authorization

### Two-layer enforcement

**Layer 1 — `RequirePlatformAdmin` plug** (`BlackboexWeb.Plugs.RequirePlatformAdmin`)

Applied to the entire `/admin` scope via the `:require_platform_admin` pipeline. Checks `conn.assigns[:current_scope].user.is_platform_admin`. On failure: redirects to `/dashboard` with an error flash.

```elixir
pipeline :require_platform_admin do
  plug BlackboexWeb.Plugs.RequirePlatformAdmin
end
```

**Layer 2 — `can?/3` callback** on each LiveResource

Every resource implements:
```elixir
@impl Backpex.LiveResource
def can?(assigns, _action, _item), do: platform_admin?(assigns)

defp platform_admin?(%{current_scope: %{user: %{is_platform_admin: true}}}), do: true
defp platform_admin?(_), do: false
```

The `_action` parameter is a Backpex action atom (`:index`, `:show`, `:new`, `:edit`, `:delete`). All resources use a blanket check — no per-action differentiation. If finer-grained control is needed, pattern-match on `action`.

### Pipeline order

```elixir
pipe_through [
  :browser,
  :admin_layout,
  :require_authenticated_user,   # must be logged in
  :require_platform_admin,        # must be platform admin
  :audit_context                  # injects audit metadata for ExAudit
]
```

The `live_session :admin` also mounts `Backpex.InitAssigns` which sets up Backpex's internal assigns.

---

## Admin Layout

The admin panel uses a two-level layout system distinct from the regular app:

### `admin_root.html.heex` (root layout)
Loaded via the `:admin_layout` pipeline plug (`put_root_layout html: {BlackboexWeb.Layouts, :admin_root}`).

- Loads `admin.css` and `admin.js` (the separate Backpex asset bundle, **not** the app bundle)
- Renders in dark theme (single theme — no switcher; dark values are in `:root` of `admin.css`)
- Page title prefix: "BlackBoex Admin"
- Body is bare — Backpex renders its own sidebar/navigation inside `@inner_content`

### `:admin` layout function
Each LiveResource declares `layout: {BlackboexWeb.Layouts, :admin}`. The `admin` function is rendered by Backpex as the inner content layout. The `DashboardLive` uses it directly via `<BlackboexWeb.Layouts.admin flash={@flash} current_url="/admin" live_resource={nil}>`.

### Difference from app layout
The app layout (`BlackboexWeb.Layouts.app`) loads `app.css`/`app.js`, has a topbar nav, and is used for all user-facing LiveViews. The admin layout has no topbar — Backpex provides its own sidebar navigation rendered from the router's `live_resources` declarations.

---

## How to Add a New Admin Resource

**1. Create the `admin_changeset/3` on the domain schema.**

The arity is exactly 3: `(struct, attrs, _metadata)`. This is Backpex's convention — the third argument carries Backpex metadata and is typically ignored. Restrict fields to only what admins should be able to change:

```elixir
@spec admin_changeset(t(), map(), map()) :: Ecto.Changeset.t()
def admin_changeset(foo, attrs, _metadata) do
  foo
  |> cast(attrs, [:allowed_field_1, :allowed_field_2])
  |> validate_required([:allowed_field_1])
end
```

For read-only resources (no writes intended), delegate to the existing changeset:
```elixir
def admin_changeset(struct, attrs, _metadata), do: changeset(struct, attrs)
```

**2. Create the LiveResource module** in `apps/blackboex_web/lib/blackboex_web/admin/`.

Follow the standard template above. File name: `snake_case_live.ex`.

**3. Register the route** in `router.ex` inside the `live_session :admin` block:

```elixir
live_resources "/foos", FooLive
```

Place it in the appropriate group comment (Core / API data / Testing / LLM / Audit).

**4. Add a stat card** to `DashboardLive` (`dashboard_live.ex`):

```elixir
# In load_stats/0:
foos: Repo.aggregate(Blackboex.SomeContext.Foo, :count),

# In render/1:
<.stat_card title="Foos" value={@stats.foos} icon="hero-some-icon" href={~p"/admin/foos"} />
```

**5. Add the module alias** to the router scope's module namespace. The scope is `BlackboexWeb.Admin` so the module just needs to be `BlackboexWeb.Admin.FooLive` — no alias needed in the router itself.

---

## Gotchas

### `admin_changeset/3` arity is 3, not 2
Backpex calls the changeset function as `fun.(struct, attrs, metadata)`. If you write a 2-arity function and capture it with `&Foo.changeset/2`, it will raise at runtime. Always use arity 3 and accept the metadata as `_metadata`.

### Field restriction is the changeset's job, not the field list's
The `fields/0` definition controls what is *displayed*. It does not prevent writes. If a field is omitted from `fields/0` but present in `admin_changeset/3`'s `cast/3`, it can still be submitted via crafted requests. Restrict sensitive fields (passwords, hashed tokens, internal IDs) in the changeset, not just the field list.

### Read-only resources still declare `update_changeset` and `create_changeset`
Even resources documented as "Read-only" wire up `admin_changeset/3`. This is required by Backpex. The practical read-only constraint comes from not providing meaningful write access in practice, not from the Backpex config. To truly prevent writes, the `can?/3` callback could return `false` for `:new`, `:edit`, `:delete` actions — but currently no resource does this.

### `AgentEventLive` — no `updated_at`
`Blackboex.Conversations.Event` has `inserted_at` only. Do not add `updated_at` to the field list — it does not exist on the schema and will cause a runtime error.

### `VersionLive` — uses `recorded_at`, not `inserted_at`
`Blackboex.Audit.Version` is an ExAudit table. Its timestamp column is `recorded_at`, not `inserted_at`. The `init_order` is set accordingly: `%{by: :recorded_at, direction: :desc}`.

### Audit trail gap in admin operations
The `:audit_context` pipeline plug is in the admin pipeline, but ExAudit row-level tracking only covers schemas explicitly tracked (Subscription, Api, ApiKey, Organization). Admin edits to other resources (e.g., toggling `is_platform_admin` on a user) are not tracked in the `versions` table. Use `AuditLog` for manual audit entries if needed.

### JSONB fields must use custom `render:` — not `Backpex.Fields.Map`
There is no `Backpex.Fields.Map` in use. All JSONB columns (`param_schema`, `metadata`, `patch`, `results`, `value`) use `Backpex.Fields.Text` with a `render:` function that calls `Jason.encode!/2` or `inspect/2` and displays via the `CodeEditor` hook (`phx-hook="CodeEditor"` with `data-readonly="true"` and `data-minimal="true"`). Always gate these on `only: [:show]` and `readonly: true` to avoid Backpex trying to render a map value in a text input.

### Security-sensitive fields use custom render to suppress display
`UserTokenLive` renders the `token` binary as `[binary token — hidden for security]` rather than exposing the raw token bytes. Follow this pattern for any field containing secrets, hashed values, or raw binary data.

### `admin.css` / `admin.js` are separate bundles
The admin root layout loads `/assets/css/admin.css` and `/assets/js/admin.js`. These are built by the `blackboex_admin` esbuild/tailwind target, separate from the `blackboex_web` target. If Backpex components are unstyled, check that the admin bundle is being served and that Tailwind's content paths include Backpex's template files.
