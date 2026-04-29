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
| Dashboard card section | `<.dashboard_section>` | `shared/dashboard_section.ex` |
| Code editor (CodeMirror) | `<.code_editor_field>` | `shared/code_editor_field.ex` |
| Period buttons (24h/7d/30d) | `<.period_selector>` | `shared/period_selector.ex` |
| Dashboard page header | `<.dashboard_page_header>` | `shared/dashboard_page_header.ex` |
| API key flash banner | `<.plain_key_banner>` | `shared/plain_key_banner.ex` |
| Inline code snippet | `<.inline_code>` | `shared/inline_code.ex` |
| Compact metric box | `<.stat_mini>` | `shared/stat_mini.ex` |
| Template category pills | `<.category_pills>` | `shared/category_pills.ex` |
| Selectable template grid | `<.template_grid>` | `shared/template_grid.ex` |
| Icon marker (colored chip) | `<.icon_badge>` | `shared/icon_badge.ex` |
| Execution history sidebar | `<.execution_history>` | `editor/execution_history.ex` |
| Terminal-style output pane | `<.terminal_output>` | `editor/terminal_output.ex` |
| Breadcrumb nav | `<.breadcrumbs>` | `shared/breadcrumbs.ex` |
| Two-column chart grid | `<.chart_grid>` | `shared/chart_grid.ex` |
| Dashboard tab nav | `<.dashboard_nav>` | `shared/dashboard_nav.ex` |
| Editor tab scroll wrapper | `<.editor_tab_panel>` | `shared/editor_tab_panel.ex` |
| Form/modal button row | `<.form_actions>` | `shared/form_actions.ex` |
| Horizontal list item row | `<.list_row>` | `shared/list_row.ex` |
| Segmented mode toggle | `<.mode_toggle>` | `shared/mode_toggle.ex` |
| Page content wrapper | `<.page>` / `<.page_section>` | `shared/page.ex` |
| Flat internal panel | `<.panel>` | `shared/panel.ex` |
| Elixir playground editor | `<.playground_editor_field>` | `shared/playground_editor_field.ex` |
| Project switcher sidebar | `<.project_switcher>` | `shared/project_switcher.ex` |
| Inline key-value chip | `<.stat_chip>` | `shared/stat_chip.ex` |
| Wrapper-less metric value | `<.stat_figure>` | `shared/stat_figure.ex` |
| Responsive stat card grid | `<.stat_grid>` | `shared/stat_grid.ex` |
| WYSIWYG rich text editor | `<.tiptap_editor_field>` | `shared/tiptap_editor_field.ex` |
| Underline-style tab bar | `<.underline_tabs>` | `shared/underline_tabs.ex` |
| Code language micro-label | `<.code_label>` | `editor/code_label.ex` |
| Editor page toolbar | `<.editor_page_header>` | `editor/page_header.ex` |
| Collapsible page tree | `<.page_tree>` | `editor/page_tree.ex` |
| Playground list sidebar | `<.playground_tree>` | `editor/playground_tree.ex` |
| Auto-save state indicator | `<.save_indicator>` | `editor/save_indicator.ex` |
| Playground AI chat | `<.playground_chat_panel>` | `editor/playground_chat_panel.ex` |
| Unified nav tree | `<SidebarTreeComponent>` (live_component) | `sidebar_tree_component.ex` |

### CSS Utilities (defined in `assets/css/app.css`)

| Utility | Purpose |
|---------|---------|
| `.text-muted-caption` | `text-xs text-muted-foreground` — compact muted text |
| `.text-muted-description` | `text-sm text-muted-foreground` — description text |
| `.link-muted` | Muted link with hover transition (breadcrumbs, refs) |
| `.link-entity` | Primary-colored entity link with hover underline |
| `.link-primary` | `text-xs text-primary hover:underline` — inline primary action link |
| `.link-destructive` | `text-xs text-destructive hover:underline` — inline destructive action link |
| `.section-label` | `flex items-center gap-1.5 text-sm font-medium text-muted-foreground` — icon+label section header (combine with `mb-3`/`mb-4`) |
| `.clickable-item` | `rounded border p-1.5 text-2xs cursor-pointer hover:bg-accent` — clickable list row (e.g. history items) |

---

## Auto-Import vs Explicit Import

**Auto-imported** via `use BlackboexWeb, :live_view` / `:html` / `:live_component`:
`Icon`, `Button`, `Flash`/`flash_group`, `FormField` (`<.input>`), `Table`, `Header`, `Helpers`, `StatusHelpers`, `Logo`, `JS`

**Explicit import required** (add to LiveView module):
`Badge`, `Card`, `Modal`, `DropdownMenu`, `Tabs`, `Avatar`, `Separator`, `Label`, `Input` (raw), `Sheet`, `Sidebar`, `Tooltip`, `Spinner`, `Skeleton`, `SectionHeading`, `FieldLabel`, `InlineInput`, `InlineSelect`, `InlineTextarea`, `StatusDot`, `UI.ActionRow`, `Shared.Breadcrumbs`, `Shared.CategoryPills`, `Shared.ChartGrid`, `Shared.Charts`, `Shared.CodeEditorField`, `Shared.DashboardHelpers`, `Shared.DashboardNav`, `Shared.DashboardPageHeader`, `Shared.DashboardSection`, `Shared.DescriptionList`, `Shared.EditorTabPanel`, `Shared.EmptyState`, `Shared.FormActions`, `Shared.IconBadge`, `Shared.InlineCode`, `Shared.ListRow`, `Shared.ModeToggle`, `Shared.Page`, `Shared.Panel`, `Shared.PeriodSelector`, `Shared.PlainKeyBanner`, `Shared.PlaygroundEditorField`, `Shared.ProgressBar`, `Shared.ProjectSwitcher`, `Shared.StatCard`, `Shared.StatChip`, `Shared.StatFigure`, `Shared.StatGrid`, `Shared.StatMini`, `Shared.TemplateGrid`, `Shared.TiptapEditorField`, `Shared.UnderlineTabs`

All from `BlackboexWeb.Components.*`.

**Editor function components** (import `BlackboexWeb.Components.Editor.*`):
`Toolbar` → `<.editor_toolbar>`, `CommandPalette` → `<.command_palette>`, `ValidationDashboard` → `<.validation_dashboard>`, `StatusBar` → `<.status_bar>`, `RightPanel` → `<.right_panel>`, `BottomPanel` → `<.bottom_panel>`, `CodeViewer` → `<.code_viewer>`, `CodeLabel` → `<.code_label>`, `PageHeader` → `<.editor_page_header>`, `PageTree` → `<.page_tree>`, `PlaygroundTree` → `<.playground_tree>`, `SaveIndicator` → `<.save_indicator>`, `PlaygroundChatPanel` → `<.playground_chat_panel>`

**Editor LiveComponents** (use `<.live_component module={...}>`):
`Editor.ChatPanel`, `Editor.RequestBuilder`, `Editor.ResponseViewer`

**Editor pure-Elixir helpers** (import, no HEEx):
`Editor.ChatPanelHelpers` — `tool_icon/1`, `format_tool_display_name/1`, `group_events/1`, `has_active_tool_call?/1`, `format_timestamp/1`, `format_tokens/1`, `format_cost/1`, `short_model/1`, `run_type_icon/1`, `run_type_label/1`, `diff_line_class/1`, `diff_prefix/1`, `format_diff_summary/1`, `test_summary/1`, `quick_actions/1`, `looks_like_code?/1`

**Shared pure-Elixir helpers** (import, no HEEx):
`Shared.DashboardHelpers` — `period_label/1`, `format_number/1`, `format_cost/1`, `format_tokens/1`, `format_duration/1`, `format_latency/1`

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

Common icons: `hero-bolt` (APIs), `hero-key` (keys), `hero-cog-6-tooth` (settings), `hero-plus` (add), `hero-trash` (delete), `hero-eye` (view), `hero-pencil-square` (edit), `hero-check-circle` (success), `hero-x-circle` (error), `hero-exclamation-circle` (warning), `hero-arrow-path` (refresh — add `animate-spin`), `hero-ellipsis-horizontal` (more menu), `hero-x-mark` (close), `hero-sparkles` (AI), `hero-beaker` (tests), `hero-document-text` (docs), `hero-command-line` (palette).

---

#### `<.button>`

Module: `BlackboexWeb.Components.Button`

Renders `<button>` by default. When `navigate`, `patch`, or `href` is provided, renders `<.link>` instead.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `type` | `:string` | `nil` | HTML button type (`"button"`, `"submit"`, `"reset"`) |
| `variant` | `:string` | `"default"` | `default`, `primary`, `secondary`, `destructive`, `outline`, `ghost`, `ghost-muted`, `ghost-dark`, `success`, `info`, `link` |
| `size` | `:string` | `"default"` | `default`, `sm`, `lg`, `icon`, `icon-sm`, `icon-xs`, `compact`, `pill`, `micro`, `list-item` |
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

| `api_key_status_classes/1` | `"Active"`, `"Expired"`, `"Revoked"` | API key status badge classes |
| `execution_status_classes/1` | `"completed"`, `"running"`, `"failed"`, `"pending"`, `"cancelled"`, `"halted"` | Flow execution badge classes |
| `execution_status_dot/1` | same | Solid background for status dot circles |
| `field_type_classes/1` | `"string"`, `"integer"`, `"float"`, `"boolean"`, `"array"`, `"object"` | Schema type color classes |
| `chart_color/1` | `:primary`, `:error`, `:warning`, `:success`, `:accent`, `:axis` | CSS variable string for SVG fills |

```heex
<.badge class={api_status_classes(@api.status)}>{@api.status}</.badge>
<.badge class={result_classes(:pass)}>Passed</.badge>
<.badge class={execution_status_classes("completed")}>completed</.badge>
```

#### CSS Design Tokens

All colors use semantic tokens defined in `app.css`. **Never use raw Tailwind color names** (e.g., `text-green-500`).

| Token Group | Example Classes | Use For |
|-------------|----------------|---------|
| Semantic feedback | `text-success-foreground`, `bg-warning/15`, `text-info-foreground`, `text-destructive` | Status indicators, alerts |
| Status lifecycle | `text-status-compiled-foreground`, `bg-status-published/10` | API/process lifecycle badges |
| Execution status | `text-status-completed-foreground`, `bg-status-failed/15` | Flow execution badges/dots |
| Icon accents | `text-accent-blue`, `text-accent-violet`, `text-accent-amber`, etc. | Decorative icon colors for visual differentiation |
| Field types | `text-type-string-foreground`, `text-type-number-foreground` | Schema field type indicators |
| Charts | `var(--color-chart-1)` through `var(--color-chart-5)` | SVG chart fills |

Available accent colors: `blue`, `violet`, `amber`, `emerald`, `red`, `purple`, `sky`, `teal`, `rose`, `orange`, `cyan`.

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
| `variant` | `:string` | `"default"` | `default`, `label` (uppercase tracked caption) |
| `tone` | `:string` | `"default"` | `default`, `muted` (forces `text-muted-foreground`) |
| `icon` | `:string` | `nil` | Hero icon name |
| `icon_class` | `:string` | `"size-4 text-muted-foreground"` | Icon CSS classes |
| `compact` | `:boolean` | `false` | Removes wrapper gap |
| `class` | `:any` | `nil` | Wrapper div classes |
| `heading_class` | `:any` | `nil` | Override heading element classes (escape hatch — prefer `level`/`variant`/`tone`) |

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
| `icon` | `:string` | `nil` | Hero icon name shown before the label |
| `icon_class` | `:string` | `nil` | Icon color/size class |
| `href` | `:string` | `nil` | When present, wraps card in `<.link navigate>` with hover border |
| `class` | `:string` | `nil` | Additional card classes |

```heex
<.stat_card label="Total Requests" value="12,345" />
<.stat_card label="Error Rate" value="5.2%" color="destructive" />
<.stat_card label="APIs" value={@api_count} icon="hero-bolt" icon_class="text-accent-blue" href={~p"/apis"} />
```

---

#### `<.dashboard_section>`

Module: `BlackboexWeb.Components.Shared.DashboardSection`

Card with icon+title header and content area. Replaces the repeated card+label pattern in dashboards.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `:string` | required | Section title text |
| `icon` | `:string` | required | Hero icon name |
| `icon_class` | `:string` | `nil` | Icon accent color (e.g. `"text-accent-violet"`) |
| `class` | `:any` | `nil` | Additional card classes |

Slot: `:inner_block` (required)

```heex
<.dashboard_section icon="hero-sparkles-mini" icon_class="text-accent-violet" title="LLM Calls">
  <.bar_chart data={@data} />
</.dashboard_section>
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

#### `<.breadcrumbs>`

Module: `BlackboexWeb.Components.Shared.Breadcrumbs`

Breadcrumb navigation showing hierarchy (e.g. Org > Project > Section). Each item is `%{label: "...", href: "..."}` or `%{label: "..."}` for the current (non-linked) item.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `items` | `:list` | required | List of `%{label, href}` maps; omit `href` for current page |

```heex
<.breadcrumbs items={[
  %{label: "APIs", href: ~p"/apis"},
  %{label: @api.name}
]} />
```

---

#### `<.chart_grid>`

Module: `BlackboexWeb.Components.Shared.ChartGrid`

Responsive two- or three-column grid for dashboard chart sections. Replaces `<div class="grid gap-4 lg:grid-cols-2">`.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `cols` | `:string` | `"2"` | `"2"` or `"3"` columns at `lg` breakpoint |
| `class` | `:any` | `nil` | Additional classes |

Slot: `:inner_block` (required)

```heex
<.chart_grid>
  <.dashboard_section title="Calls" icon="hero-bolt">...</.dashboard_section>
  <.dashboard_section title="Errors" icon="hero-x-circle">...</.dashboard_section>
</.chart_grid>
```

---

#### `<.dashboard_nav>`

Module: `BlackboexWeb.Components.Shared.DashboardNav`

Horizontal pill tab bar for the five dashboard sections (Overview / APIs / Flows / LLM / Usage). Each tab navigates via `<.link navigate>`.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `active` | `:atom` | required | `:overview`, `:apis`, `:flows`, `:llm`, or `:usage` |
| `base_path` | `:string` | required | Base URL prefix (e.g. `"/orgs/acme/dashboard"`) |

```heex
<.dashboard_nav active={:overview} base_path={~p"/orgs/#{@org.slug}/dashboard"} />
```

---

#### `<.editor_tab_panel>`

Module: `BlackboexWeb.Components.Shared.EditorTabPanel`

Scrollable full-height content wrapper for an editor tab. Owns vertical scroll, height, spacing rhythm, and optional max-width. Replaces repeated `<div class="p-6 overflow-y-auto h-full space-y-6">` in editor tab LiveViews.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `max_width` | `:string` | `"none"` | `"none"`, `"3xl"`, `"4xl"`, `"5xl"` |
| `padding` | `:string` | `"default"` | `"default"` (`p-6`) or `"sm"` (`p-4`) |
| `spacing` | `:string` | `"default"` | `"default"` (`space-y-6`) or `"none"` |
| `class` | `:any` | `nil` | Additional classes |

Slot: `:inner_block` (required)

```heex
<.editor_tab_panel max_width="3xl">
  <.section_heading>API Information</.section_heading>
  ...
</.editor_tab_panel>
```

---

#### `<.form_actions>`

Module: `BlackboexWeb.Components.Shared.FormActions`

Button row for form/modal footers and card action bars. Replaces `<div class="flex gap-2 justify-end pt-4">`.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `align` | `:string` | `"end"` | `"start"`, `"center"`, `"end"`, `"between"` |
| `spacing` | `:string` | `"default"` | `"default"` (adds `pt-4`) or `"tight"` (gap only) |
| `class` | `:any` | `nil` | Additional classes |

Slot: `:inner_block` (required)

```heex
<.form_actions>
  <.button type="button" variant="outline" phx-click="cancel">Cancel</.button>
  <.button type="submit" variant="primary">Save</.button>
</.form_actions>

<.form_actions align="between">
  <.button variant="destructive" phx-click="delete">Delete</.button>
  <.button variant="primary" phx-click="save">Save</.button>
</.form_actions>
```

---

#### `<.list_row>`

Module: `BlackboexWeb.Components.Shared.ListRow`

Horizontal flex row for list items (members, audit log entries, link rows). `justify-between` layout with optional border. Pair with `<.panel variant="divided" padding="none">` for divided lists.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `bordered` | `:boolean` | `true` | Renders `rounded border` around the row |
| `compact` | `:boolean` | `false` | Reduces vertical padding |
| `class` | `:any` | `nil` | Additional classes |

Slot: `:inner_block` (required)

```heex
<.list_row :for={member <- @members}>
  <span>{member.email}</span>
  <.badge>{member.role}</.badge>
</.list_row>

<%# Divided list (no individual borders) %>
<.panel variant="divided" padding="none">
  <.list_row :for={log <- @logs} bordered={false}>
    <span>{log.action}</span>
    <span class="text-xs">{log.at}</span>
  </.list_row>
</.panel>
```

---

#### `<.mode_toggle>`

Module: `BlackboexWeb.Components.Shared.ModeToggle`

Segmented toggle bar for switching between 2+ modes (e.g. template/blank). Options are `{value, label, icon}` tuples.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `options` | `:list` | required | List of `{value, label, icon}` tuples |
| `active` | `:any` | required | Currently active value |
| `click_event` | `:string` | `nil` | Shared event name; when `nil`, each option's `value` is the event name |
| `class` | `:string` | `nil` | Additional classes |

```heex
<.mode_toggle
  options={[{"template", "Template", "hero-squares-2x2"}, {"blank", "Blank", "hero-document"}]}
  active={@mode}
  click_event="set_mode"
/>
```

---

#### `<.page>` and `<.page_section>`

Module: `BlackboexWeb.Components.Shared.Page`

Page-level layout primitives. `<.page>` wraps the entire LiveView content with `space-y-6`. `<.page_section>` groups subsections with configurable spacing.

`<.page>` attrs: `class`, global `rest`. Slot: `:inner_block`.

`<.page_section>` attrs:

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `spacing` | `:string` | `"default"` | `"tight"` (`space-y-3`), `"default"` (`space-y-4`), `"loose"` (`space-y-6`) |
| `class` | `:any` | `nil` | Additional classes |

```heex
<.page>
  <.header>...</.header>
  <.page_section>
    <.card>...</.card>
    <.card>...</.card>
  </.page_section>
</.page>
```

---

#### `<.panel>`

Module: `BlackboexWeb.Components.Shared.Panel`

Lightweight flat panel for internal sections. Visually distinct from `<.card>`: no shadow, `rounded-lg` (not `rounded-xl`). Use `<.card>` for top-level containers, `<.panel>` for compact internal groupings.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `:string` | `"default"` | `"default"` (border bg-card), `"dashed"`, `"muted"` (softer bg), `"highlighted"` (success-tinted), `"divided"` (divide-y, for list rows) |
| `padding` | `:string` | `"default"` | `"none"`, `"sm"` (`p-3`), `"default"` (`p-4`), `"lg"` (`p-8`) |
| `class` | `:any` | `nil` | Additional classes |

Slot: `:inner_block` (required)

```heex
<.panel>
  <p class="text-sm">Content inside a flat panel</p>
</.panel>

<.panel variant="divided" padding="none">
  <.list_row :for={item <- @items} bordered={false}>...</.list_row>
</.panel>

<.panel variant="highlighted" padding="sm">
  <.badge class={api_status_classes("published")}>Published</.badge>
</.panel>
```

---

#### `<.playground_editor_field>`

Module: `BlackboexWeb.Components.Shared.PlaygroundEditorField`

Elixir code editor for Playgrounds, backed by the `PlaygroundEditor` JS hook. Provides keyboard shortcuts (Cmd+Enter to run, Cmd+S to save, Cmd+Shift+F to format), debounced sync, and server-driven completion. **Use instead of `<.code_editor_field>` in playground views.**

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `id` | `:string` | required | DOM id for the hook |
| `value` | `:any` | required | Initial code content |
| `max_height` | `:string` | `"max-h-full"` | Max-height Tailwind class on the CodeMirror editor |
| `height` | `:string` | `nil` | Fixed height (e.g. `"100%"`, `"400px"`) |
| `style` | `:string` | `nil` | Inline style escape hatch |
| `class` | `:any` | `nil` | Additional wrapper classes |

```heex
<.playground_editor_field id="pg-editor" value={@playground.code} height="100%" />
```

---

#### `<.project_switcher>`

Module: `BlackboexWeb.Components.Shared.ProjectSwitcher`

Sidebar project switcher showing current org name, active project, and a list of all projects with navigation links.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `org` | `:map` | required | Current organization (`%{name, slug}`) |
| `project` | `:map` | `nil` | Currently active project (`%{id, name, slug}`) |
| `projects` | `:list` | `[]` | All projects in the org |

```heex
<.project_switcher org={@org} project={@current_project} projects={@projects} />
```

---

#### `<.stat_chip>`

Module: `BlackboexWeb.Components.Shared.StatChip`

Inline bordered chip showing a key-value pair with an optional icon. Use for metadata rows (duration, node count, run ID, etc.).

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `:string` | required | Label text |
| `value` | `:any` | required | Value text |
| `icon` | `:string` | `nil` | Hero icon name |
| `icon_class` | `:string` | `nil` | Icon color/size override |
| `class` | `:any` | `nil` | Additional classes |

```heex
<.stat_chip icon="hero-clock" label="Duration" value="1.2s" />
<.stat_chip icon="hero-squares-2x2" label="Nodes" value="5" />
```

---

#### `<.stat_figure>`

Module: `BlackboexWeb.Components.Shared.StatFigure`

Wrapper-less metric value + label pair. Unlike `<.stat_card>`, has no border/background — intended to be placed inside an existing `<.card>` or `<.dashboard_section>`.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `label` | `:string` | required | Metric label |
| `value` | `:any` | required | Metric value |
| `color` | `:string` | `nil` | Tailwind text color class (e.g. `"text-status-failed-foreground"`) |
| `class` | `:any` | `nil` | Wrapper div classes |

```heex
<.stat_figure label="Running" value={@running_count} />
<.stat_figure label="Failed" value={@failed_count} color="text-status-failed-foreground" />
```

---

#### `<.stat_grid>`

Module: `BlackboexWeb.Components.Shared.StatGrid`

Responsive grid for stat card rows. Always 1 column on mobile, 2 at `sm`, up to N at `lg`. Replaces repeated `<div class="grid gap-4 sm:grid-cols-2 lg:grid-cols-4">`.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `cols` | `:string` | `"4"` | Max lg columns: `"2"`, `"3"`, `"4"`, `"5"` |
| `gap` | `:string` | `"4"` | Gap size: `"3"`, `"4"`, `"6"` |
| `class` | `:any` | `nil` | Additional classes |

Slot: `:inner_block` (required)

```heex
<.stat_grid cols="4">
  <.stat_card label="Calls" value="1.2k" />
  <.stat_card label="Errors" value="3" />
  <.stat_card label="Latency" value="42ms" />
  <.stat_card label="Success" value="99.7%" />
</.stat_grid>
```

---

#### `<.tiptap_editor_field>`

Module: `BlackboexWeb.Components.Shared.TiptapEditorField`

WYSIWYG rich text block editor backed by the `TiptapEditor` JS hook. Supports slash commands and bubble menus. **Use for page/doc content editing; use `<.code_editor_field>` for code.**

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `id` | `:string` | required | DOM id for the hook |
| `value` | `:string` | `""` | Initial HTML/JSON content |
| `readonly` | `:boolean` | `false` | Disables editing |
| `event` | `:string` | `nil` | LiveView event name for content changes |
| `field` | `:string` | `nil` | Field key sent in event payload |
| `placeholder` | `:string` | `"Type '/' for commands..."` | Editor placeholder text |
| `class` | `:any` | `nil` | Additional wrapper classes |

```heex
<.tiptap_editor_field id="page-editor" value={@page.content} event="content_changed" field="content" />
```

---

#### `<.underline_tabs>`

Module: `BlackboexWeb.Components.Shared.UnderlineTabs`

Underline-style tab bar (border-bottom indicator) for switching between content panels via `phx-click`. Supports optional badge counts on tabs.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `tabs` | `:list` | required | List of `{id, label}` tuples or `{id, label, badge}` triples |
| `active` | `:string` | required | Currently active tab id |
| `click_event` | `:string` | required | Event name sent on tab click (with `phx-value-tab={id}`) |
| `class` | `:string` | `nil` | Additional wrapper classes |

```heex
<.underline_tabs
  tabs={[{"overview", "Overview"}, {"keys", "Keys", length(@api_keys)}, {"logs", "Logs"}]}
  active={@active_tab}
  click_event="set_tab"
/>
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

#### `<.code_label>`

Module: `BlackboexWeb.Components.Editor.CodeLabel`

Micro-label for code block language/type indicators (e.g. "elixir", "json"). Two variants: `default` (muted foreground) and `dark` (for dark editor backgrounds).

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `variant` | `:string` | `"default"` | `"default"` or `"dark"` |
| `class` | `:any` | `nil` | Additional classes |

Slot: `:inner_block` (required)

```heex
<.code_label>elixir</.code_label>
<.code_label variant="dark">json</.code_label>
```

---

#### `<.editor_page_header>`

Module: `BlackboexWeb.Components.Editor.PageHeader`

Compact header toolbar for editor pages (Pages, Playgrounds). Provides back navigation arrow, title, optional badge, and action buttons. Follows the same visual pattern as `<.editor_toolbar>` but without API-specific attrs.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `title` | `:string` | required | Page title text |
| `back_path` | `:string` | required | Navigate path for the back arrow |
| `back_label` | `:string` | `"Back"` | Tooltip/aria label for back link |
| `class` | `:any` | `nil` | Additional header classes |

Slots: `:badge` (optional, for status badge), `:actions` (optional, right side buttons)

```heex
<.editor_page_header
  title={@page.title}
  back_path={~p"/orgs/#{@org.slug}/projects/#{@project.slug}/pages"}
  back_label="Pages"
>
  <:badge><.badge variant="secondary">draft</.badge></:badge>
  <:actions>
    <.button variant="primary" phx-click="save">Save</.button>
  </:actions>
</.editor_page_header>
```

---

#### `<.page_tree>`

Module: `BlackboexWeb.Components.Editor.PageTree`

Collapsible page tree sidebar for the page editor. Displays project pages in a nested hierarchy with expand/collapse, selection state, and hover actions (add child, delete).

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `tree` | `:list` | required | Nested tree: `[%{page: %Page{}, children: [...]}]` as returned by `Pages.list_page_tree/1` |
| `current_page_id` | `:string` | `nil` | ID of the currently selected page |
| `expanded_ids` | `:list` | `[]` | List of page IDs that are expanded |

Events emitted: `"select_page"` (`phx-value-slug`), `"toggle_tree_node"` (`phx-value-id`), `"new_page"`, `"new_child_page"` (`phx-value-parent-id`), `"request_confirm"` (delete).

```heex
<.page_tree tree={@page_tree} current_page_id={@page.id} expanded_ids={@expanded_ids} />
```

---

#### `<.playground_tree>`

Module: `BlackboexWeb.Components.Editor.PlaygroundTree`

Flat playground list sidebar for the playground editor. Displays all project playgrounds with selection state and hover delete action.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `playgrounds` | `:list` | required | Flat list of playground maps (`%{id, name, slug}`) |
| `current_playground_id` | `:string` | `nil` | ID of the currently selected playground |

Events emitted: `"select_playground"` (`phx-value-slug`), `"new_playground"`, `"request_confirm"` (delete, `phx-value-id/slug/name`).

```heex
<.playground_tree playgrounds={@playgrounds} current_playground_id={@playground.id} />
```

---

#### `<.save_indicator>`

Module: `BlackboexWeb.Components.Editor.SaveIndicator`

Tiny inline auto-save state indicator. Shows "Saved" (muted), "Saving..." (amber), or "Unsaved" (amber).

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `status` | `:atom` | `:saved` | `:saved`, `:saving`, or `:unsaved` |

```heex
<.save_indicator status={@save_status} />
```

---

#### `<.playground_chat_panel>`

Module: `BlackboexWeb.Components.Editor.PlaygroundChatPanel`

AI agent chat timeline + input for the Playground editor. Renders message bubbles, streaming code blocks, a thinking indicator, and a submit form. Visually consistent with the API `ChatPanel`.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `messages` | `:list` | required | List of `%{role, content}` maps (role: `"user"`, `"assistant"`, `"system"`) |
| `input` | `:string` | `""` | Current input value |
| `loading` | `:boolean` | `false` | Shows thinking/streaming indicator |
| `current_stream` | `:string` | `nil` | Streaming code tokens in progress |

Events consumed from parent: `"send_chat"` (form submit, `"message"` field), `"chat_input_change"` (form change), `"new_chat"` (header button).

```heex
<.playground_chat_panel
  messages={@chat_messages}
  input={@chat_input}
  loading={@chat_loading}
  current_stream={@streaming_tokens}
/>
```

---

#### LiveComponents (rendered with `<.live_component>`)

| Component | Module | Required assigns |
|-----------|--------|-----------------|
| ChatPanel | `BlackboexWeb.Components.Editor.ChatPanel` | `events`, `pending_edit`, `streaming_tokens`, `loading`, `run`, `input`, `template_type` |
| RequestBuilder | `BlackboexWeb.Components.Editor.RequestBuilder` | `method`, `url`, `loading`, `active_tab`, `params`, `headers`, `body_json`, `body_error`, `api_key` |
| ResponseViewer | `BlackboexWeb.Components.Editor.ResponseViewer` | `response`, `loading`, `error`, `violations`, `response_tab` |

---

### New Shared Components (explicit import required)

---

#### `<.code_editor_field>`

Module: `BlackboexWeb.Components.Shared.CodeEditorField`

Wrapper for the CodeMirror `phx-hook="CodeEditor"` pattern. **All CodeMirror editors MUST use this component.**

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `id` | `:string` | required | DOM id for the editor |
| `value` | `:any` | required | Content to display |
| `language` | `:string` | `"json"` | Syntax language |
| `readonly` | `:boolean` | `true` | Whether editor is read-only |
| `minimal` | `:boolean` | `true` | Minimal UI mode |
| `max_height` | `:string` | `"max-h-96"` | Max height class for cm-editor. Pass `""` when using fixed `height` |
| `event` | `:string` | `nil` | LiveView event name for changes |
| `field` | `:string` | `nil` | Field identifier for event payload |
| `class` | `:any` | `nil` | Additional CSS classes |
| `height` | `:string` | `nil` | Fixed pixel/viewport height (e.g. `"240px"`, `"35vh"`) — preferred over `style` |
| `style` | `:string` | `nil` | Inline style escape hatch (prefer `height` attr) |

---

#### `<.period_selector>`

Module: `BlackboexWeb.Components.Shared.PeriodSelector`

Period toggle buttons (24h/7d/30d) for dashboard views. Emits `"set_period"` event.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `period` | `:string` | required | Currently active period |

---

#### `<.dashboard_page_header>`

Module: `BlackboexWeb.Components.Shared.DashboardPageHeader`

Standard dashboard page header with icon, title, subtitle, navigation tabs, and period selector.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `icon` | `:string` | required | Hero icon name |
| `icon_class` | `:string` | required | Icon color class |
| `title` | `:string` | required | Page title |
| `subtitle` | `:string` | required | Page subtitle |
| `active_tab` | `:string` | required | Active dashboard nav tab |
| `period` | `:string` | required | Current period for selector |

---

#### `<.plain_key_banner>`

Module: `BlackboexWeb.Components.Shared.PlainKeyBanner`

One-time API key display banner with copy-friendly code block and dismiss button.

| Attr | Type | Default | Description |
|------|------|---------|-------------|
| `plain_key` | `:string` | required | The API key to display |

---

### Updated Components

- **`<.stat_card>`** — added `href` attr (optional). When present, wraps card in a `<.link navigate={}>` with hover border.
- **`<.badge>`** — added `variant="status"`, `size="xs"`, and semantic variants `success`, `warning`, `info`.
- **`<.button>`** — added variants `success`, `info`, `ghost-dark`, `outline-destructive`; sizes `compact`, `pill`, `micro`, `icon-sm`, `icon-xs`, `list-item`.
- **`<.card_content>`** — added `standalone` boolean (restores top padding when no card_header), `size="compact"`.
- **`<.card_header>`** — added `size="compact"` (tighter padding for dense layouts).
- **`<.card_title>`** — added `size="label"` (small uppercase tracking style).
- **StatusHelpers** — added `execution_status_text_class/1` for text color classes.
- **DashboardHelpers** — added `format_latency/1`, extended `format_duration/1` to handle minutes (>60s).

### New Components

- **`<.inline_code>`** — `shared/inline_code.ex` — inline code display with `default` and `block` variants.
- **`<.action_row>`** — `ui/action_row.ex` — horizontal row with `title`/`description`/`action` slots for danger-zone and settings rows. Variants: `default`, `destructive`. Explicit import: `BlackboexWeb.Components.UI.ActionRow`.

### Updated Components (Round 7)

- **`<.alert_banner>`** — added variants `neutral` (transparent border-only) and `primary` (primary-tinted). Full variant set: `destructive`, `warning`, `info`, `success`, `neutral`, `primary`.

### New Helpers

- **`FlowLive.ExecutionHelpers`** — shared `status_badge/1`, `status_icon/1`, `short_id/1`, `format_duration/1`, `format_time/1` for flow execution views.

### Removed

- `ui/sidebar/menu.ex` and `ui/sidebar/group.ex` — duplicates of functions in `ui/sidebar.ex`.

### CSS Tokens

- `text-2xs` (10px) and `text-micro` (11px) — custom font sizes defined in `@theme inline`. Use instead of `text-[10px]` / `text-[11px]`.
- `bg-editor-bg` — editor dark background color. Use instead of `bg-[#1e1e2e]`.

### New Components (US-003)

- **`BlackboexWeb.Components.SidebarTreeComponent`** (LiveComponent) — `sidebar_tree_component.ex`
  - **Type:** `live_component` — use `<.live_component module={SidebarTreeComponent} ...>`
  - **Assigns:** `:id` (required, string), `:current_scope` (map | nil), `:current_path` (string), `:collapsed` (boolean, accepted but ignored — sidebar hides us when collapsed)
  - **Internal state:**
    - `:projects` — list of `%{project: %Project{}, pages_count: int, apis_count: int, flows_count: int, playgrounds_count: int}` from `Projects.list_projects_with_counts/1`, loaded in `update/2`
    - `:expanded` — list of string keys (e.g. `"project:uuid"`, `"apis:uuid"`) merged from `Accounts.get_user_preference/3` at `["sidebar_tree", "expanded"]` and auto-expand from current path
    - `:tree_children` — map `%{"apis:<project_id>" => [%Api{}], ...}` populated lazily on expand
  - **ID key convention:** `"project:<uuid>"` (project row), `"pages:<uuid>"`, `"apis:<uuid>"`, `"flows:<uuid>"`, `"playgrounds:<uuid>"` (group rows, keyed by project_id)
  - **Internal state (US-201 additions):**
    - `:create_modal` — `nil` (closed) or `%{type: string, project_id: string, parent_id: string | nil}`. Type is always singular (`"api"`, `"flow"`, `"page"`, `"playground"`). Group-type strings (`"apis"`, etc.) are normalised on open.
    - `:create_error` — `string | nil` — inline error message set on failed create (changeset, limit, forbidden)
  - **Internal state (US-301 additions):**
    - `:open_menu_id` — `string | nil` — `"<singular_type>:<item_id>"` of the leaf whose ⋯ menu is open; only one at a time
    - `:renaming` — `nil` or `%{type: string, id: string, value: string}` — which leaf is in inline-rename mode and its current value
    - `:rename_error` — `string | nil` — error message from a failed rename (blank name or changeset error)
    - `:delete_modal` — `nil` or `%{type: string, id: string, name: string, confirm_text: string}` — state of the destructive-delete confirmation modal
  - **Internal state (US-401 additions):**
    - `:move_error` — `string | nil` — human-readable error message set when a DnD move is rejected; cleared on the next successful move
  - **DnD markup (US-401):**
    - The `<nav>` root carries `phx-hook="SidebarTreeDnD"` and `phx-target={@myself}` so that the `SidebarTreeDnD` JS hook delivers `move_node` events directly to this LiveComponent
    - Each group `<ul>` (when expanded) carries `data-tree-list data-parent-type={group_type} data-parent-id={project.id}` — used by Sortable.js to identify the drop zone and its type/parent
    - Each leaf `<li>` carries `data-tree-item data-node-id={item.id} data-node-type={singular_type}` — used by Sortable.js as the draggable unit
  - **Events handled:**
    - `"expand_node"` — `%{"type" => type, "id" => id}` — adds key to `:expanded`, lazy-loads children into `:tree_children`, persists async
    - `"collapse_node"` — `%{"type" => type, "id" => id}` — removes key from `:expanded`, persists async
    - `"open_create_modal"` — `%{"type" => type, "project-id" => pid}` (+ optional `"parent-id"`) — normalises type to singular, sets `:create_modal` assign
    - `"close_create_modal"` — clears `:create_modal` assign
    - `"create_resource"` — `%{"type" => type, "project_id" => pid, "name" => name}` (+ optional `"parent_id"`) — authorises via `@create_actions` whitelist, calls domain context, then `push_navigate` to canonical URL
    - `"open_item_menu"` — `%{"type" => singular_type, "id" => id}` — toggles `:open_menu_id`; closes if same item clicked again
    - `"close_item_menu"` — clears `:open_menu_id`
    - `"start_rename"` — `%{"type" => singular_type, "id" => id}` — sets `:renaming` from tree_children cache, closes menu
    - `"cancel_rename"` — clears `:renaming` and `:rename_error`
    - `"submit_rename"` — `%{"type" => type, "_id" => id, "value" => name}` — trims name, authorises via `@update_actions` whitelist, calls `fetch_owned_item` (IDOR check), calls `do_update`, then `refresh_children`; blank name sets `:rename_error`
    - `"open_delete_modal"` — `%{"type" => singular_type, "id" => id}` — sets `:delete_modal` from tree_children cache, closes menu
    - `"update_delete_confirm"` — `%{"confirm" => text}` — updates `:delete_modal.confirm_text` for live matching
    - `"close_delete_modal"` — clears `:delete_modal`
    - `"confirm_delete"` — authorises via `@delete_actions` whitelist, calls `fetch_owned_item` (IDOR check), calls `do_delete`, then `refresh_children`; if current path contains deleted item's id/slug, `push_navigate` to org overview
    - `"move_node"` — `%{"node_id" => id, "node_type" => type, "new_parent_type" => pt, "new_parent_id" => pid, "new_index" => idx}` — pushed by `SidebarTreeDnD` JS hook on drag-end; validated against `@valid_move_combos` compile-time whitelist, then authorised (IDOR + policy), then applies domain move; on success refreshes source + destination groups; on failure sets `:move_error` and pushes `"sidebar_tree:rollback"` client event
  - **Movement rules (US-401):**
    | From | To | Allowed? |
    |---|---|---|
    | page → other parent page (same project) | same project | YES — `Pages.move_page/3` |
    | page → other project | — | NO — `:forbidden` |
    | api / flow / playground → other project (same org) | same org | YES — `Apis.move_api/2`, `Flows.move_flow/2`, `Playgrounds.move_playground/2` |
    | any → other org | — | NO — `:forbidden` |
    | cross-type (api → flows group, etc.) | — | NO — `:invalid_target_type` |
  - **Security:** `@create_actions`, `@update_actions`, `@delete_actions` are compile-time whitelists mapping type strings to LetMe action atoms — no `String.to_atom/1` on user input. `fetch_owned_item/3` verifies resource belongs to `scope.organization.id` before any mutation (IDOR defense in depth). Confirm-to-delete pattern prevents accidental destructive actions. `@valid_move_combos` is a compile-time list of `{node_type, parent_type}` tuples; any unrecognised combination is rejected before hitting the DB.
  - **Auto-expand:** parses `:current_path` for `/orgs/:slug/projects/:slug[/type]` pattern; auto-expands matching project + group without a round-trip
  - **Canonical URL patterns:**
    - APIs: `/orgs/:org_slug/projects/:project_slug/apis/:api_slug/edit`
    - Flows: `/orgs/:org_slug/projects/:project_slug/flows/:flow_id/edit`
    - Pages: `/orgs/:org_slug/projects/:project_slug/pages/:page_slug/edit`
    - Playgrounds: `/orgs/:org_slug/projects/:project_slug/playgrounds/:playground_slug/edit`
  - **Children loading:** uses `Apis.list_for_project/1`, `Flows.list_for_project/1`, `Pages.list_root_pages_for_project/1`, `Playgrounds.list_for_project/1`
  - **Persistence:** expanded state written asynchronously via `Task.Supervisor.start_child(Blackboex.TaskSupervisor, ...)`
  - **Wired in:** `app_sidebar.ex` — the WORK group renders this component when `collapsed: false`. When `collapsed: true` the original flat icon-strip items are shown unchanged (editor layout). The component `id` is derived as `"#{sidebar_id}-tree"` to avoid duplicate-ID errors.
