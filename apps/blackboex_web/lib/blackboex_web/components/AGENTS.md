# AGENTS.md — Component Catalog for BlackboexWeb

## CRITICAL RULE — READ BEFORE WRITING ANY UI

**Every LiveView HEEx template MUST be a composition of components from this catalog.**

- NO raw `<div>`, `<span>`, `<h1>`, `<p>`, `<table>`, `<form>`, `<input>`, `<button>` tags in LiveView templates when a component exists for the purpose.
- NO inline `style="..."` attributes — use Tailwind utility classes via the `class` attribute only.
- NO duplicating component logic — always use the component.
- NO creating a new custom element when a component already handles the job.
- Check this catalog FIRST before writing any markup.

Violation of this rule creates inconsistent UI, breaks dark mode, bypasses semantic color tokens, and makes future refactors much harder.

---

## Quick-Reference Lookup

| Need | Component | Module |
|------|-----------|--------|
| Page title + actions | `<.header>` | `ui/header.ex` |
| Data display | `<.table>` | `ui/table.ex` |
| User input | `<.input>` (form_field) | `ui/form_field.ex` |
| Action trigger | `<.button>` | `ui/button.ex` |
| Status indicator | `<.badge>` | `ui/badge.ex` |
| Empty content | `<.empty_state>` | `shared/empty_state.ex` |
| Loading state | `<.skeleton>` / `<.spinner>` | `ui/skeleton.ex`, `ui/spinner.ex` |
| Modal dialog | `<.modal>` | `ui/modal.ex` |
| Slide-out panel | `<.sheet>` | `ui/sheet.ex` |
| Navigation tabs | `<.tabs>` | `ui/tabs.ex` |
| Metrics display | `<.stat_card>` | `shared/stat_card.ex` |
| Charts | `<.bar_chart>` / `<.line_chart>` | `shared/charts.ex` |
| Key-value pairs | `<.description_list>` | `shared/description_list.ex` |
| Usage meter | `<.progress_bar>` | `shared/progress_bar.ex` |
| Dropdown actions | `<.dropdown_menu>` | `ui/dropdown_menu.ex` |
| Hover info | `<.tooltip>` | `ui/tooltip.ex` |
| Content sections | `<.card>` | `ui/card.ex` |
| Dividers | `<.separator>` | `ui/separator.ex` |
| User avatar | `<.avatar>` | `ui/avatar.ex` |
| Virtual file tree | `<.file_tree>` | `editor/file_tree.ex` |
| File editor display | `<.file_editor>` | `editor/file_editor.ex` |
| Section title | `<.section_heading>` | `ui/section_heading.ex` |
| Form-free label | `<.field_label>` | `ui/field_label.ex` |
| Form-free input | `<.inline_input>` | `ui/inline_input.ex` |
| Form-free select | `<.inline_select>` | `ui/inline_select.ex` |
| Form-free textarea | `<.inline_textarea>` | `ui/inline_textarea.ex` |
| Status dot | `<.status_dot>` | `ui/status_dot.ex` |

---

## Auto-Import vs Explicit Import

**Auto-imported** via `use BlackboexWeb, :live_view` / `:html` / `:live_component`:
`Icon`, `Button`, `Flash`/`flash_group`, `FormField` (`<.input>`), `Table`, `Header`, `Helpers`, `StatusHelpers`, `Logo`, `JS`

**Explicit import required** (add to LiveView module):
`Badge`, `Card`, `Modal`, `DropdownMenu`, `Tabs`, `Avatar`, `Separator`, `Label`, `Input` (raw), `Sheet`, `Sidebar`, `Tooltip`, `Spinner`, `Skeleton`, `SectionHeading`, `FieldLabel`, `InlineInput`, `InlineSelect`, `InlineTextarea`, `StatusDot`, `Shared.Charts`, `Shared.StatCard`, `Shared.EmptyState`, `Shared.ProgressBar`, `Shared.DescriptionList`

All from `BlackboexWeb.Components.*`.

**Editor function components** (import `BlackboexWeb.Components.Editor.*`):
`Toolbar` → `<.editor_toolbar>`, `CommandPalette` → `<.command_palette>`, `ValidationDashboard` → `<.validation_dashboard>`, `StatusBar` → `<.status_bar>`, `RightPanel` → `<.right_panel>`, `BottomPanel` → `<.bottom_panel>`, `CodeViewer` → `<.code_viewer>`

**Editor LiveComponents** (use `<.live_component module={...}>`):
`Editor.ChatPanel`, `Editor.RequestBuilder`, `Editor.ResponseViewer`

---

## Layout System

| Layout | Use When | Declaration |
|--------|----------|-------------|
| `app` | Standard authenticated pages | `use BlackboexWeb, :live_view` (default) — provides nav bar, `max-w-6xl` container |
| `auth` | Login/registration pages | `on_mount` auth hooks + `:auth` layout |
| `editor` | Full-screen API editor | `@layout {BlackboexWeb.Layouts, :editor}` in router — bare `h-screen overflow-hidden` |

Flash: always use `put_flash/3` in handlers. `<.flash_group flash={@flash} />` is embedded in all layouts — do not place `<.flash>` directly in page templates.

---

## Component Catalog

### Auto-imported (no explicit import needed)

---

#### `<.icon>`

Module: `BlackboexWeb.Components.Icon`

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `name` | `:string` | required | Hero icon name, e.g. `"hero-x-mark"` |
| `class` | `:any` | `"size-4"` | CSS classes for sizing and color |

Styles via suffix: default (outline), `-solid`, `-mini`, `-micro`. Common sizes: `size-3`–`size-8`. Color inherits `currentColor`; override with `text-*` utilities.

Common icons: `hero-bolt` (APIs), `hero-key` (keys), `hero-credit-card` (billing), `hero-cog-6-tooth` (settings), `hero-plus` (add), `hero-trash` (delete), `hero-eye` (view), `hero-pencil-square` (edit), `hero-check-circle` (success), `hero-x-circle` (error), `hero-exclamation-circle` (warning), `hero-arrow-path` (refresh — add `animate-spin`), `hero-ellipsis-horizontal` (more menu), `hero-x-mark` (close), `hero-sparkles` (AI), `hero-beaker` (tests), `hero-document-text` (docs), `hero-command-line` (palette).

---

#### `<.button>`

Module: `BlackboexWeb.Components.Button`

Renders `<button>` by default. When `navigate`, `patch`, or `href` is provided, renders `<.link>` instead.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `:string` | `nil` | HTML button type (`"button"`, `"submit"`, `"reset"`) |
| `variant` | `:string` | `"default"` | `default`, `primary`, `secondary`, `destructive`, `outline`, `ghost`, `link` |
| `size` | `:string` | `"default"` | `default`, `sm`, `lg`, `icon` |
| `class` | `:any` | `nil` | Additional CSS classes |
| `navigate` / `patch` / `href` | global | — | Renders as `<.link>` |
| `disabled` / `phx-click` | global | — | Standard button attrs |

Slot: `:inner_block` (required)

```heex
<.button variant="primary" phx-click="save">Save</.button>
<.button variant="ghost" size="icon"><.icon name="hero-ellipsis-horizontal" /></.button>
<.button variant="link" navigate={~p"/apis"}>Back</.button>
```

---

#### `<.input>` (form-aware, FormField)

Module: `BlackboexWeb.Components.FormField`

Form-integrated input with label, errors, and Phoenix.HTML.FormField support. Always use this (not the raw `Input`) when working with Phoenix forms.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `field` | `Phoenix.HTML.FormField` | — | Form field, e.g. `@form[:email]` |
| `label` | `:string` | `nil` | Label text shown above the input |
| `type` | `:string` | `"text"` | `checkbox`, `date`, `datetime-local`, `email`, `file`, `number`, `password`, `search`, `select`, `tel`, `text`, `textarea`, `time`, `url`, `hidden` |
| `errors` | `:list` | `[]` | Error messages (auto-extracted from field) |
| `prompt` | `:string` | `nil` | Placeholder option for select |
| `options` | `:list` | — | Options for select type |
| `multiple` | `:boolean` | `false` | Multiple select |
| `class` / `error_class` | `:any` | `nil` | Override input/error-state classes |
| `rest` | global | — | `autocomplete`, `disabled`, `placeholder`, `readonly`, `required`, `rows`, etc. |

```heex
<.input field={@form[:email]} type="email" label="Email" />
<.input field={@form[:role]} type="select" label="Role"
  options={[{"Admin", "admin"}, {"User", "user"}]} prompt="Select role" />
<.input field={@form[:bio]} type="textarea" label="Bio" rows="4" />
```

---

#### `<.table>`

Module: `BlackboexWeb.Components.Table`

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `id` | `:string` | required | DOM id for the tbody |
| `rows` | `:list` | required | List or LiveStream |
| `row_id` | `:any` | `nil` | Function generating row DOM id |
| `row_click` | `:any` | `nil` | Function for `phx-click` per row |
| `row_item` | `:any` | `Function.identity/1` | Mapping function for each row |

Slots:
- `:col` — required, with `label` attr; uses `:let={item}` to access row data
- `:action` — optional last column for action buttons; uses `:let={item}`

```heex
<.table id="users" rows={@users} row_click={&JS.navigate(~p"/users/#{&1.id}")}>
  <:col :let={u} label="Name">{u.name}</:col>
  <:col :let={u} label="Status"><.badge class={api_key_status_classes(u.status)}>{u.status}</.badge></:col>
  <:action :let={u}><.button variant="ghost" size="icon" phx-click="delete" phx-value-id={u.id}><.icon name="hero-trash" class="text-destructive" /></.button></:action>
</.table>
```

---

#### `<.header>`

Module: `BlackboexWeb.Components.Header`

Page-level heading with optional subtitle and action area.

Slots:
- `:inner_block` — required; the main title text
- `:subtitle` — optional descriptive text below the title
- `:actions` — optional; when present, header becomes flex row with actions on the right

```heex
<.header>
  API Keys
  <:subtitle>Manage your API keys.</:subtitle>
  <:actions>
    <.button variant="primary" navigate={~p"/api-keys/new"}>New Key</.button>
  </:actions>
</.header>
```

---

#### Logo components

Module: `BlackboexWeb.Logo`

| Component | Attrs | Description |
|-----------|-------|-------------|
| `<.logo_icon>` | `class` (default `"size-6"`) | Hexagon + pipe symbol SVG |
| `<.logo_full>` | `class` (default `"h-7"`) | Icon + "BlackBoex" wordmark, wrapped in `<a href="/">` |
| `<.logo_wordmark>` | `class` (default `"text-lg"`) | Text-only "BlackBoex" span |

---

#### Status helper functions (StatusHelpers)

Elixir functions, not components. Use to build `class` attribute values on `<.badge>`.

| Function | Input | Output |
|----------|-------|--------|
| `api_status_classes/1` | `"draft"`, `"compiled"`, `"published"`, `"archived"` | Full badge classes (border + bg + text) |
| `api_status_border/1` | same | Border + text only (for inline chips) |
| `process_status_classes/1` | `"pending"`, `"generating"`, `"validating"`, `"running"` | Badge classes for agent process states |
| `result_classes/1` | `"pass"/:pass`, `"fail"/:fail`, `"skip"/:skip`, `"passed"`, `"failed"` | Pass/fail badge classes |
| `subscription_classes/1` | `"active"`, `"trialing"`, `"past_due"`, `"canceled"`, `"incomplete"` | Billing status badge classes |
| `api_key_status_classes/1` | `"Active"`, `"Expired"`, `"Revoked"` | API key status badge classes |
| `chart_color/1` | `:primary`, `:error`, `:warning`, `:success`, `:accent`, `:axis` | CSS variable string for SVG fills |

```heex
<.badge class={api_status_classes(@api.status)}>{@api.status}</.badge>
<.badge class={result_classes(:pass)}>Passed</.badge>
```

---

### Explicit import required

---

#### `<.badge>`

Module: `BlackboexWeb.Components.Badge`

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `:string` | `"default"` | `default`, `secondary`, `destructive`, `outline` |
| `class` | `:string` | `nil` | Additional or override classes |

Slot: `:inner_block` (required)

For semantic status colors, pass `class={api_status_classes(...)}` directly and omit `variant`.

```heex
<.badge variant="destructive">Error</.badge>
<.badge class={api_status_classes(@api.status)}>{@api.status}</.badge>
```

---

#### `<.card>`, `<.card_header>`, `<.card_title>`, `<.card_description>`, `<.card_content>`, `<.card_footer>`

Module: `BlackboexWeb.Components.Card`

All sub-components accept `class`, `rest` (:global), and `:inner_block`.

| Component | CSS Defaults |
|-----------|-------------|
| `<.card>` | `rounded-xl border bg-card text-card-foreground shadow` |
| `<.card_header>` | `flex flex-col space-y-1.5 p-6` |
| `<.card_title>` | `text-2xl font-semibold leading-none tracking-tight` |
| `<.card_description>` | `text-sm text-muted-foreground` |
| `<.card_content>` | `p-6 pt-0` |
| `<.card_footer>` | `flex items-center justify-between p-6 pt-0` |

```heex
<.card><.card_header><.card_title>Title</.card_title><.card_description>Subtitle</.card_description></.card_header><.card_content>...</.card_content></.card>
```

---

#### `<.input>` (raw, no form integration)

Module: `BlackboexWeb.Components.Input` — use ONLY without Phoenix.HTML.FormField (e.g., editor request builder). Attrs: `id`, `name`, `value`, `type`, `class`, global `rest`.

```heex
<.input type="text" name="query" placeholder="Search..." />
```

---

#### `<.label>`

Module: `BlackboexWeb.Components.Label` — attrs: `class`, global `for`.

```heex
<.label for="email">Email address</.label>
```

---

#### `<.section_heading>`

Module: `BlackboexWeb.Components.UI.SectionHeading`

Semantic heading for in-page section titles. Replaces repeated `<h2>`/`<h3>` + icon + description patterns.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `level` | `:string` | `"h2"` | `h1`, `h2`, `h3` |
| `icon` | `:string` | `nil` | Hero icon name |
| `icon_class` | `:string` | `"size-4 text-muted-foreground"` | Icon CSS classes |
| `class` | `:any` | `nil` | Wrapper div classes |
| `heading_class` | `:any` | `nil` | Override heading element classes |

Slot: `:inner_block` (required), `:description` (optional)

```heex
<.section_heading>Section Title</.section_heading>
<.section_heading level="h3" icon="hero-cog-6-tooth">Settings</.section_heading>
<.section_heading>
  API Keys
  <:description>Manage access tokens for this API.</:description>
</.section_heading>
```

---

#### `<.field_label>`

Module: `BlackboexWeb.Components.UI.FieldLabel`

Label with optional icon for form-free contexts (property panels, inline editors). Replaces the repeated `<label>` + icon pattern in flow editor.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `icon` | `:string` | `nil` | Hero icon name |
| `icon_color` | `:string` | `"text-blue-400"` | Icon color class |
| `class` | `:any` | `nil` | Additional classes |

Slot: `:inner_block` (required)

```heex
<.field_label icon="hero-code-bracket" icon_color="text-purple-400">Code</.field_label>
```

---

#### `<.inline_input>`

Module: `BlackboexWeb.Components.UI.InlineInput`

Minimal input without form wrapper. For use outside `<.form>` contexts (property panels, inline edits).

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `:string` | `"text"` | `text`, `number`, `password` |
| `value` | `:any` | `nil` | Current value |
| `placeholder` | `:string` | `nil` | Placeholder text |
| `class` | `:any` | `nil` | Additional classes |
| `rest` | global | — | `phx-blur`, `phx-change`, `phx-value-*`, etc. |

```heex
<.inline_input value={@value} phx-blur="update_field" phx-value-field="name" />
```

---

#### `<.inline_select>`

Module: `BlackboexWeb.Components.UI.InlineSelect`

Minimal select without form wrapper. For property panels and inline configuration.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `options` | `:list` | required | List of `{label, value}` tuples |
| `value` | `:any` | `nil` | Currently selected value |
| `name` | `:string` | `nil` | Input name |
| `class` | `:any` | `nil` | Additional classes |
| `rest` | global | — | `phx-change`, `phx-value-*`, etc. |

```heex
<.inline_select options={[{"GET", "GET"}, {"POST", "POST"}]} value={@method} phx-change="set_method" />
```

---

#### `<.inline_textarea>`

Module: `BlackboexWeb.Components.UI.InlineTextarea`

Minimal textarea without form wrapper. For property panels and inline editors.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `value` | `:any` | `nil` | Current value |
| `placeholder` | `:string` | `nil` | Placeholder text |
| `class` | `:any` | `nil` | Additional classes |
| `rest` | global | — | `phx-blur`, `phx-change`, `rows`, etc. |

```heex
<.inline_textarea value={@description} phx-blur="update_description" rows="3" />
```

---

#### `<.status_dot>`

Module: `BlackboexWeb.Components.UI.StatusDot`

Colored dot + label for entity status. Replaces the repeated `<span>` with `rounded-full bg-*` pattern.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `status` | `:string` | required | Status key (e.g. `"active"`, `"draft"`, `"running"`, `"completed"`, `"failed"`) |

Status colors are built-in: green (active/completed/success), yellow (draft/pending/running), red (failed/error/cancelled), blue (paused), gray (default).

```heex
<.status_dot status="active" />
<.status_dot status="failed" />
```

---

#### `<.modal>`

Module: `BlackboexWeb.Components.Modal`

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `show` | `:boolean` | required | Controls visibility |
| `on_close` | `:string` | required | Event name sent on backdrop click or Escape key |
| `title` | `:string` | `nil` | Modal header text |
| `class` | `:string` | `nil` | Additional classes on the dialog panel |

Slot: `:inner_block` (required). Handles: fixed backdrop, Escape key, backdrop click, close button.

```heex
<.modal show={@show_delete_modal} on_close="close_modal" title="Delete API">
  <p class="text-sm text-muted-foreground">This action cannot be undone.</p>
  <div class="mt-4 flex justify-end gap-2">
    <.button variant="outline" phx-click="close_modal">Cancel</.button>
    <.button variant="destructive" phx-click="confirm_delete">Delete</.button>
  </div>
</.modal>
```

---

#### `<.dropdown_menu>` and sub-components

Module: `BlackboexWeb.Components.DropdownMenu`

| Component | Key Attrs |
|-----------|-----------|
| `<.dropdown_menu>` | `class` |
| `<.dropdown_menu_trigger>` | `as_tag` (default `"div"`) |
| `<.dropdown_menu_content>` | `side` (`"top"/"right"/"bottom"/"left"`, default `"bottom"`), `align` (`"start"/"center"/"end"`, default `"start"`) |
| `<.dropdown_menu_label>` | `class` |
| `<.dropdown_menu_separator>` | `class` |
| `<.dropdown_menu_group>` | `class` |
| `<.dropdown_menu_item>` | `class` |
| `<.dropdown_menu_shortcut>` | `class` |

Trigger uses `phx-click` + `phx-click-away` for show/hide. No JS setup needed.

```heex
<.dropdown_menu>
  <.dropdown_menu_trigger>
    <.button variant="ghost" size="icon"><.icon name="hero-ellipsis-horizontal" /></.button>
  </.dropdown_menu_trigger>
  <.dropdown_menu_content align="end">
    <.dropdown_menu_item phx-click="edit" phx-value-id={@item.id}>Edit</.dropdown_menu_item>
    <.dropdown_menu_separator />
    <.dropdown_menu_item phx-click="delete" phx-value-id={@item.id}>Delete</.dropdown_menu_item>
  </.dropdown_menu_content>
</.dropdown_menu>
```

---

#### `<.tabs>`, `<.tabs_list>`, `<.tabs_trigger>`, `<.tabs_content>`

Module: `BlackboexWeb.Components.Tabs`

| Component | Key Attrs |
|-----------|-----------|
| `<.tabs>` | `id` (required), `default` (initial active tab value), `class`; yields `builder` via `:let` |
| `<.tabs_list>` | `class` |
| `<.tabs_trigger>` | `builder` (required, from `:let`), `value` (required), `class` |
| `<.tabs_content>` | `value` (required, matches trigger), `class` |

```heex
<.tabs id="api-tabs" default="overview" :let={builder}>
  <.tabs_list>
    <.tabs_trigger builder={builder} value="overview">Overview</.tabs_trigger>
    <.tabs_trigger builder={builder} value="analytics">Analytics</.tabs_trigger>
  </.tabs_list>
  <.tabs_content value="overview">...</.tabs_content>
  <.tabs_content value="analytics">...</.tabs_content>
</.tabs>
```

---

#### `<.avatar>`, `<.avatar_image>`, `<.avatar_fallback>`

Module: `BlackboexWeb.Components.Avatar`

| Component | Key Attrs |
|-----------|-----------|
| `<.avatar>` | `class` (default `h-10 w-10 rounded-full`) |
| `<.avatar_image>` | `src` (required), `alt` (required), `class` |
| `<.avatar_fallback>` | `class`; inner_block for initials/icon |

```heex
<.avatar>
  <.avatar_image src={@user.avatar_url} alt={@user.name} />
  <.avatar_fallback>{String.first(@user.name)}</.avatar_fallback>
</.avatar>
```

---

#### `<.separator>`

Module: `BlackboexWeb.Components.Separator` — attrs: `orientation` (`"horizontal"` default), `class`.

```heex
<.separator />
<.separator orientation="vertical" class="h-6" />
```

---

#### `<.sheet>` and sub-components

Module: `BlackboexWeb.Components.Sheet`

Slide-in side panel. Wire trigger to content via shared `id`/`target`.

| Component | Key Attrs |
|-----------|-----------|
| `<.sheet>` | `class` (wrapper, default `"inline-block"`) |
| `<.sheet_trigger>` | `target` (required — id of content), `class` |
| `<.sheet_content>` | `id` (required), `side` (`"left"/"right"/"top"/"bottom"`, default `"right"`), `class` |
| `<.sheet_header>` | `class` |
| `<.sheet_title>` | `class` |
| `<.sheet_description>` | `class` |
| `<.sheet_footer>` | `class` |
| `<.sheet_close>` | `target` (required — id to close), `class` |

```heex
<.sheet>
  <.sheet_trigger target="settings-sheet">
    <.button variant="outline">Settings</.button>
  </.sheet_trigger>
  <.sheet_content id="settings-sheet" side="right">
    <.sheet_header>
      <.sheet_title>Settings</.sheet_title>
    </.sheet_header>
    <div class="py-4"><%# content %></div>
    <.sheet_footer>
      <.sheet_close target="settings-sheet"><.button variant="outline">Cancel</.button></.sheet_close>
      <.button variant="primary" phx-click="save">Save</.button>
    </.sheet_footer>
  </.sheet_content>
</.sheet>
```

---

#### Sidebar components

Module: `BlackboexWeb.Components.Sidebar`

A full sidebar system for app-level navigation panels.

| Component | Key Attrs |
|-----------|-----------|
| `<.sidebar_provider>` | `class`, `style` — wraps entire sidebar+content layout |
| `<.sidebar>` | `id` (required), `side` (`"left"/"right"`), `variant` (`"sidebar"/"floating"/"inset"`), `collapsible` (`"offcanvas"/"icon"/"none"`), `state` (`"expanded"/"collapsed"`) |
| `<.sidebar_trigger>` | `target` (required — sidebar id), `as_tag` |
| `<.sidebar_rail>` | click target to toggle collapse |
| `<.sidebar_inset>` | wraps the main content area next to the sidebar |
| `<.sidebar_header>` | top section |
| `<.sidebar_footer>` | bottom section |
| `<.sidebar_content>` | scrollable middle section |
| `<.sidebar_group>` | logical group within content |
| `<.sidebar_group_label>` | `as_tag` — section label |
| `<.sidebar_group_action>` | action button for the group |
| `<.sidebar_group_content>` | wrapper for group items |
| `<.sidebar_menu>` | `<ul>` list of items |
| `<.sidebar_menu_item>` | `<div>` wrapper for a menu button |
| `<.sidebar_menu_button>` | `variant` (`"default"/"outline"`), `size` (`"default"/"sm"/"lg"`), `is_active`, `tooltip`, `as_tag` |
| `<.sidebar_menu_action>` | `show_on_hover` |
| `<.sidebar_menu_badge>` | numeric badge on menu item |
| `<.sidebar_menu_skeleton>` | `show_icon` — loading placeholder |
| `<.sidebar_menu_sub>` | nested sub-menu list |
| `<.sidebar_menu_sub_item>` | `<li>` |
| `<.sidebar_menu_sub_button>` | `size` (`"sm"/"md"`), `is_active`, `as_tag` |
| `<.sidebar_separator>` | horizontal line in sidebar |
| `<.sidebar_input>` | search input styled for sidebar |

---

#### `<.tooltip>`, `<.tooltip_trigger>`, `<.tooltip_content>`

Module: `BlackboexWeb.Components.Tooltip`

CSS-only hover tooltip (no JS).

| Component | Key Attrs |
|-----------|-----------|
| `<.tooltip>` | `class` |
| `<.tooltip_trigger>` | — renders slot only |
| `<.tooltip_content>` | `side` (`"top"/"right"/"bottom"/"left"`, default `"top"`), `class` |

```heex
<.tooltip>
  <.tooltip_trigger><.button variant="ghost" size="icon"><.icon name="hero-information-circle" /></.button></.tooltip_trigger>
  <.tooltip_content>Click to view details</.tooltip_content>
</.tooltip>
```

---

#### `<.spinner>` / `<.skeleton>`

`Spinner` — `class` (default `"size-4"`). `Skeleton` — `class` (nil default, set `h-*` and `w-*`).

```heex
<.spinner class="size-6 text-primary" />
<.skeleton class="h-4 w-32" />
```

---

### Shared Components (`shared/`)

---

#### `<.stat_card>`

Module: `BlackboexWeb.Components.Shared.StatCard`

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `:string` | required | Metric label |
| `value` | `:any` | required | Metric value (string or number) |
| `color` | `:string` | `nil` | `"destructive"` for red value text |
| `class` | `:string` | `nil` | Additional card classes |

```heex
<.stat_card label="Total Requests" value="12,345" />
<.stat_card label="Error Rate" value="5.2%" color="destructive" />
```

---

#### `<.empty_state>`

Module: `BlackboexWeb.Components.Shared.EmptyState`

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `:string` | required | Primary empty state message |
| `description` | `:string` | `nil` | Secondary description text |
| `icon` | `:string` | `nil` | Hero icon name |
| `class` | `:string` | `nil` | Additional classes |

Slot: `:actions` — optional action buttons

```heex
<.empty_state icon="hero-bolt" title="No APIs yet" description="Create your first API.">
  <:actions><.button variant="primary" navigate={~p"/apis/new"}>New API</.button></:actions>
</.empty_state>
```

---

#### `<.progress_bar>`

Module: `BlackboexWeb.Components.Shared.ProgressBar`

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `:string` | required | Metric label |
| `used` | `:any` | required | Used amount (display value) |
| `limit` | `:any` | required | Limit amount (can be `"Unlimited"`) |
| `percentage` | `:float` | `0.0` | Fill percentage (0.0–100.0) |
| `color` | `:string` | `"bg-primary"` | Bar fill color class |
| `class` | `:string` | `nil` | Additional wrapper classes |

```heex
<.progress_bar label="API Calls" used={450} limit={1000} percentage={45.0} />
<.progress_bar label="Error Rate" used={95} limit={100} percentage={95.0} color="bg-destructive" />
```

---

#### `<.description_list>`

Module: `BlackboexWeb.Components.Shared.DescriptionList`

| Attr | Type | Default |
|------|------|---------|
| `class` | `:string` | `nil` |

Slot: `:item` — required, with `label` attr (required)

```heex
<.description_list>
  <:item label="Status"><.badge class={api_status_classes(@api.status)}>{@api.status}</.badge></:item>
  <:item label="Created">{Calendar.strftime(@api.inserted_at, "%b %d, %Y")}</:item>
</.description_list>
```

---

#### `<.bar_chart>` and `<.line_chart>`

Module: `BlackboexWeb.Components.Shared.Charts`

Pure server-side SVG. No JavaScript dependencies.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `data` | `:list` | required | List of `%{label: String.t(), value: number()}` |
| `title` | `:string` | `""` | Chart title (shown above SVG) |
| `width` | `:integer` | `600` | SVG viewBox width |
| `height` | `:integer` | `300` | SVG viewBox height |
| `color` | `:string` | `"var(--color-chart-1)"` | Bar/line color |

Use `chart_color/1` from `StatusHelpers` for semantic colors that respond to theme changes.

```heex
<.bar_chart data={@daily_requests} title="Requests per Day" color={chart_color(:primary)} />
<.line_chart data={@error_rates} title="Error Rate" color={chart_color(:error)} />
```

---

### Editor Components (`editor/`)

Used exclusively in the API editor LiveView.

---

#### `<.editor_toolbar>`

Module: `BlackboexWeb.Components.Editor.Toolbar`

| Attr | Type | Default |
|------|------|---------|
| `api` | `:map` | required |
| `selected_version` | `:map` | `nil` |
| `generation_status` | `:string` | `nil` |

```heex
<.editor_toolbar api={@api} selected_version={@selected_version} generation_status={@generation_status} />
```

---

#### `<.command_palette>`

Module: `BlackboexWeb.Components.Editor.CommandPalette`

| Attr | Type | Default |
|------|------|---------|
| `open` | `:boolean` | `false` |
| `query` | `:string` | `""` |
| `api` | `:map` | required |
| `selected_index` | `:integer` | `0` |

---

#### `<.validation_dashboard>`

Module: `BlackboexWeb.Components.Editor.ValidationDashboard`

| Attr | Type | Default |
|------|------|---------|
| `report` | `:map` | `nil` |
| `loading` | `:boolean` | `false` |

The `report` map must have: `overall` (`:pass`/`:fail`), `compilation`, `format`, `credo`, `tests` (`:pass`/`:fail`/`:skipped`/`:warn`), plus `compilation_errors`, `format_issues`, `credo_issues`, `test_results` lists.

Also exports `<.validation_badge check="Compile" status={:pass} detail={nil} />`.

---

#### `<.status_bar>`

Module: `BlackboexWeb.Components.Editor.StatusBar`

| Attr | Type | Default |
|------|------|---------|
| `api` | `:map` | required |
| `versions` | `:list` | `[]` |
| `selected_version` | `:map` | `nil` |

---

#### `<.right_panel>`

Module: `BlackboexWeb.Components.Editor.RightPanel`

| Attr | Type | Default |
|------|------|---------|
| `mode` | `:atom` | required — `:chat` or `:config` |

Slot: `:inner_block` (required)

---

#### `<.bottom_panel>`

Module: `BlackboexWeb.Components.Editor.BottomPanel`

| Attr | Type | Default |
|------|------|---------|
| `active_tab` | `:string` | `"test"` — `"test"`, `"validation"`, `"versions"` |
| `validation_report` | `:map` | `nil` |

Slot: `:inner_block` (required)

---

#### `<.code_viewer>`

Module: `BlackboexWeb.Components.Editor.CodeViewer`

Server-side Makeup syntax highlighting with line numbers. Dark theme (`#1e1e2e`).

| Attr | Type | Default |
|------|------|---------|
| `code` | `:string` | required |
| `label` | `:string` | `nil` |
| `class` | `:string` | `nil` |

```heex
<.code_viewer code={@api.code} label="Code" class="h-full" />
```

---

#### LiveComponents (rendered with `<.live_component>`)

| Component | Module | Required assigns |
|-----------|--------|-----------------|
| ChatPanel | `BlackboexWeb.Components.Editor.ChatPanel` | `events`, `pending_edit`, `streaming_tokens`, `loading`, `run`, `input`, `template_type` |
| RequestBuilder | `BlackboexWeb.Components.Editor.RequestBuilder` | `method`, `url`, `loading`, `active_tab`, `params`, `headers`, `body_json`, `body_error`, `api_key` |
| ResponseViewer | `BlackboexWeb.Components.Editor.ResponseViewer` | `response`, `loading`, `error`, `violations`, `response_tab` |
