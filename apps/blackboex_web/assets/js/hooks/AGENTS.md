# JavaScript LiveView Hooks

## Overview

Phoenix LiveView hooks are JavaScript objects that manage client-side behaviour for DOM elements tagged with `phx-hook="HookName"`. Each hook can listen for LiveView server pushes (`handleEvent`), send events back to the server (`pushEvent`), and react to DOM lifecycle callbacks (`mounted`, `updated`, `destroyed`).

Hooks in this project are split by responsibility:

- `assets/js/hooks/**` — LiveView hook wiring only: DOM lookup, listener registration, `pushEvent`, `handleEvent`, lifecycle cleanup.
- `assets/js/hooks/global/**` — global hooks loaded by `app.js`.
- `assets/js/lib/**` — calculations, parsing, payload builders, editor setup, browser adapters, storage, layout, and render helpers.
- `assets/test/hooks/**` — hook tests, mirrored by hook area.
- `assets/test/lib/**` — library tests, mirrored by library area.

`app.js` is the single LiveSocket owner for the main web layout. It imports every public hook used by that layout and builds a complete `hooks` map before calling `new LiveSocket(...)`, matching the `retro_hex_chat` `v2_app.js` pattern. Do not use `window.__hooks`, lazy hook registration, or conditional feature bundles for hooks in the main layout.

**Mandatory:** every new or changed hook needs a test under `assets/test/hooks/**`; every new or changed lib needs a test under `assets/test/lib/**`. Vendor files are not part of the refactoring/test scope.

---

## Hook Catalog

### `CodeEditor` (`hooks/code_editor.js`)

**Purpose:** Mounts a read-only or editable [CodeMirror 6](https://codemirror.net/) code editor inside a div. Supports multiple languages and optional blur-triggered event pushing.

**Registered in:** `assets/js/app.js`

**Logic libs:** `lib/editor/code_editor.js`, `lib/codemirror_setup.js`, `lib/codemirror_theme.js`

**Tests:** `test/lib/editor/code_editor.test.js`, `test/lib/codemirror_setup.test.js`

**Used by:** `components/shared/code_editor_field.ex` via `phx-hook="CodeEditor"`

**DOM attributes:**

- `data-language` — language identifier for syntax highlighting (default: `"text"`; common values: `"json"`, `"elixir"`)
- `data-readonly` — `"true"` makes the editor non-editable
- `data-minimal` — `"true"` applies a stripped-down UI (no line numbers, no gutter)
- `data-value` — initial document content; also drives `updated()` diffs
- `data-event` — LiveView event name to push on blur (optional)
- `data-field` — field name included in the push payload alongside `value` (optional)

**Pushes to LiveView:**

- `<data-event value>` — fires on editor blur when `data-event` is set; payload is `%{value: string}` or `%{field: string, value: string}` when `data-field` is also set

**Handles from LiveView:** none

**Lifecycle:** `mounted` (initialises CodeMirror), `updated` (syncs `data-value` if it changed), `destroyed` (destroys the editor view)

---

### `PlaygroundEditor` (`hooks/playground_editor.js`)

**Purpose:** Full-featured Elixir code editor for the Playground page. Extends CodeMirror with keyboard shortcuts, 300 ms debounced live sync, and server-driven autocomplete.

**Registered in:** `assets/js/app.js`

**Logic libs:** `lib/editor/playground_editor.js`, `lib/elixir_completion.js`

**Tests:** `test/lib/editor/playground_editor.test.js`, `test/lib/elixir_completion.test.js`

**Used by:** `components/shared/playground_editor_field.ex` via `phx-hook="PlaygroundEditor"`

**DOM attributes:**

- `data-value` — initial document content; also drives `updated()` diffs

**Pushes to LiveView:**

- `"run"` — triggered by `Cmd+Enter` / `Ctrl+Enter`; payload `%{}`
- `"save_code"` — triggered by `Cmd+S` / `Ctrl+S`; payload `%{}`
- `"format_code"` — triggered by `Cmd+Shift+F` / `Ctrl+Shift+F`; payload `%{}`
- `"update_code"` — debounced (300 ms) on every document change; payload `%{value: string}`
- `"get_completions"` — sent by the Elixir completion source (see `lib/elixir_completion.js`) when the user types; payload includes cursor context

**Handles from LiveView:**

- `"formatted_code"` — replaces the full document with `%{code: string}` (response to a format request)
- `"completion_results"` — resolves pending completion promise with `%{items: [...]}` (server-driven autocomplete)
- `"playground_editor:set_value"` — replaces the full document with `%{code: string}`; sent by the AI agent after a chat run completes

**Lifecycle:** `mounted` (initialises CodeMirror with keymap, update listener, and completion extension), `updated` (syncs `data-value` if it changed), `destroyed` (destroys the editor view)

---

### `DrawflowEditor` (`hooks/drawflow_editor.js`)

**Purpose:** Manages the visual flow canvas (Drawflow library) for the API flow editor. Handles node drag-drop from the sidebar, auto-layout via dagre, zoom/pan toolbar actions, and execution-view overlays with per-node status pills and embedded CodeMirror JSON viewers.

**Registered in:** `assets/js/app.js`

**Logic libs:** `lib/flow/drawflow_converter.js`, `lib/flow/node_catalog.js`, `lib/flow/drawflow_layout.js`, `lib/flow/execution_view.js`

**Tests:** `test/lib/flow/**`

**Used by:** `live/flow_live/edit.ex` via `phx-hook="DrawflowEditor"`

**DOM attributes:**

- `data-definition` — JSON string of the flow in **BlackboexFlow** canonical format (`{version, nodes, edges}`) or legacy raw Drawflow JSON

**Pushes to LiveView:**

- `"node_selected"` — when a node is clicked; payload `%{id: string, type: string, data: map}`
- `"node_deselected"` — when a node is unselected, removed, or empty canvas is clicked; payload `%{}`
- `"save_definition"` — response to `"export_definition"` server request; payload `%{definition: BlackboexFlowMap}`
- `"show_json_preview"` — response to `"export_json_preview"` server request; payload `%{definition: BlackboexFlowMap}`

**Handles from LiveView:**

- `"set_node_data"` — updates a node's internal data and re-renders its label; payload `%{id: string, data: map}`
- `"export_definition"` — triggers client to serialize the canvas and push `"save_definition"` back; payload `%{}`
- `"export_json_preview"` — triggers client to serialize and push `"show_json_preview"` back; payload `%{}`
- `"load_execution_view"` — replaces the canvas with an execution overlay showing status pills and JSON output per node; payload `%{definition: BlackboexFlowMap, nodes: [%{id, status, duration_ms}]}`
- `"clear_execution_view"` — restores the canvas to the pre-execution state; payload `%{}`
- `"definition_saved"` — acknowledged no-op; payload `%{}`

**Lifecycle:** `mounted` (starts Drawflow, wires toolbar, drag-drop, and all event handlers), `destroyed` (clears the editor)

---

### `ResizablePanels` (`hooks/resizable_panels.js`)

**Purpose:** Enables drag-to-resize for playground panels. Finds all `[data-resize-handle]` elements inside the hook element, attaches mouse/touch drag handlers, enforces min/max constraints, and persists sizes to `localStorage` under the key `"playground-panel-sizes"`.

**Registered in:** `assets/js/app.js`

**Logic libs:** `lib/ui/resizable_panels.js`

**Tests:** `test/hooks/resizable_panels.test.js`, `test/lib/ui/resizable_panels.test.js`

**Used by:**

- `live/playground_live/edit.ex` via `phx-hook="ResizablePanels"` on `#playground-panels`
- `live/page_live/edit.ex` via `phx-hook="ResizablePanels"` on `#page-edit-root`

**DOM attributes on `[data-resize-handle]` children (not the hook element itself):**

- `data-resize-direction` — `"vertical"` (controls height) or `"horizontal"` (controls width)
- `data-resize-target` — `id` of the panel element to resize
- `data-resize-css-var` — _(optional)_ CSS custom property name (e.g. `"--playground-output-pane-height"`) to write the size to on `:root` instead of mutating `style.height/width` on the target. Use this when the target is inside a LiveView region whose re-render would otherwise reset the inline style; declare the target with `style="height: var(--name, <default>);"` so the server-rendered style is stable and the CSS variable carries the user's chosen size.

**Constraints (hardcoded):**

- vertical: min 100 px, max 600 px
- horizontal: min 200 px, max 500 px

**Pushes to LiveView:** none

**Handles from LiveView:** none

**Lifecycle:** `mounted` (restores persisted sizes, attaches drag handlers), `destroyed` (removes all listeners and cleans up overlay)

---

### `TiptapEditor` (`hooks/tiptap_editor.js`)

**Purpose:** Mounts a full rich-text editor (Tiptap + ProseMirror) with Markdown serialisation, slash commands, bubble menu, syntax-highlighted code blocks (lowlight), tables, task lists, links, images, and character count. Content is serialised as Markdown before being pushed to the server.

**Registered in:** `assets/js/app.js`

**Logic libs:** `lib/tiptap/lowlight_languages.js`, `lib/tiptap/bubble_menu.js`, `lib/tiptap/editor_options.js`, `lib/tiptap/markdown_sync.js`, `lib/tiptap/slash_commands.js`, `lib/tiptap/code_block_lang.js`

**Tests:** `test/lib/tiptap/**`

**Used by:** `components/shared/tiptap_editor_field.ex` via `phx-hook="TiptapEditor"`

**DOM attributes:**

- `data-value` — initial Markdown content; also drives `updated()` diffs
- `data-readonly` — `"true"` makes the editor non-editable
- `data-event` — LiveView event name to push on content change (optional)
- `data-field` — field name included in the push payload (optional)
- `data-placeholder` — placeholder text shown when the editor is empty (default: `"Type '/' for commands..."`)

**Pushes to LiveView:**

- `<data-event value>` — debounced (500 ms) on every content change and immediately on `Cmd+S`; payload is `%{value: markdown_string}` or `%{field: string, value: markdown_string}` when `data-field` is set

**Handles from LiveView:** none

**Lifecycle:** `mounted` (initialises Tiptap with all extensions and bubble menu), `updated` (syncs `data-value` when changed externally, skips update if it was triggered by the hook's own push to avoid infinite loops), `destroyed` (destroys the editor and clears the debounce timer)

---

### `KeyboardShortcuts` (`hooks/global/keyboard_shortcuts_hook.js`)

**Purpose:** Global keyboard shortcut handler for the API editor shell. Intercepts `keydown` on `window` and dispatches named LiveView events for common editor actions.

**Used by:** `live/api_live/edit/editor_shell.ex` via `phx-hook="KeyboardShortcuts"`

**Logic libs:** `lib/global/keyboard_shortcuts.js`

**Tests:** `test/hooks/global/keyboard_shortcuts_hook.test.js`, `test/lib/global/keyboard_shortcuts.test.js`

**DOM attributes:** none

**Pushes to LiveView:**

- `"toggle_command_palette"` — `Cmd+K` (always) or `Escape` when palette is open
- `"save"` — `Cmd+S` or `Cmd+Shift+S`
- `"toggle_chat"` — `Cmd+L`
- `"toggle_bottom_panel"` — `Cmd+J`
- `"toggle_config"` — `Cmd+I`
- `"send_request"` — `Cmd+Enter`
- `"close_panels"` — `Escape` when command palette is closed

**Handles from LiveView:** none

**Lifecycle:** `mounted` (attaches `keydown` listener to `window`), `destroyed` (removes listener)

---

### `AutoFocus` (`hooks/global/auto_focus_hook.js`)

**Purpose:** Focuses the element immediately on mount and on each update. Used for command palette inputs that need focus when they appear.

**Used by:** command palette input elements

**Tests:** `test/hooks/global/auto_focus_hook.test.js`

**DOM attributes:** none

**Pushes to LiveView:** none

**Handles from LiveView:** none

**Lifecycle:** `mounted` (calls `this.el.focus()`), `updated` (calls `this.el.focus()` and scrolls the selected command palette item into view)

---

### `ChatAutoScroll` (`hooks/global/chat_auto_scroll_hook.js`)

**Purpose:** Keeps a scrollable chat timeline pinned to the bottom as new messages and streaming tokens arrive. Uses both a `MutationObserver` and a 150 ms polling interval to catch morphdom text patches that the observer may miss. Pauses auto-scroll when the user manually scrolls up.

**Used by:**

- `components/editor/chat_panel.ex` on `#chat-messages` via `phx-hook="ChatAutoScroll"`
- `components/editor/playground_chat_panel.ex` on `#playground-chat-timeline` via `phx-hook="ChatAutoScroll"`

**Logic libs:** `lib/global/auto_scroll.js`

**Tests:** `test/hooks/global/auto_scroll_hooks.test.js`

**DOM attributes:** none

**Pushes to LiveView:** none

**Handles from LiveView:** none

**Lifecycle:** `mounted` (sets up MutationObserver, polling interval, and scroll listener), `updated` (scrolls to bottom if user has not scrolled up), `destroyed` (disconnects observer, clears interval)

---

### `EditorAutoScroll` (`hooks/global/editor_auto_scroll_hook.js`)

**Purpose:** Keeps the file editor's code region scrolled to the bottom during AI streaming. Polls every 150 ms for height changes and watches for manual scroll-up to pause auto-scroll. Targets the first `.overflow-y-auto` child inside the hook element.

**Used by:** `components/editor/file_editor.ex` on `#editor-scroll-region` via `phx-hook="EditorAutoScroll"`

**Logic libs:** `lib/global/auto_scroll.js`

**Tests:** `test/hooks/global/auto_scroll_hooks.test.js`

**DOM attributes:** none

**Pushes to LiveView:** none

**Handles from LiveView:** none

**Lifecycle:** `mounted` (attaches polling interval and scroll listener), `updated` (scrolls to bottom if user has not scrolled up), `destroyed` (clears polling interval)

---

### `CommandPaletteNav` (`hooks/global/command_palette_nav_hook.js`)

**Purpose:** Handles keyboard navigation (ArrowUp / ArrowDown) inside the command palette list and scrolls the currently selected item into view on each update.

**Logic libs:** `lib/global/command_palette.js`

**Tests:** `test/hooks/global/command_palette_nav_hook.test.js`, `test/lib/global/command_palette.test.js`

**Used by:** `components/editor/command_palette.ex` via `phx-hook="CommandPaletteNav"`

**DOM attributes:** none

**Pushes to LiveView:**

- `"command_palette_navigate"` — on `ArrowDown` or `ArrowUp`; payload `%{direction: "down" | "up"}`

**Handles from LiveView:** none

**Lifecycle:** `mounted` (focuses element, attaches `keydown` listener), `updated` (re-focuses element, scrolls selected item into view)

---

## Note on `drawflow_converter.js`

`hooks/drawflow_converter.js` is a compatibility shim, not a hook. The canonical implementation is `lib/flow/drawflow_converter.js` and exports two pure utility functions used internally by `DrawflowEditor`:

- `drawflowToBlackboex(drawflowData)` — converts Drawflow's internal JSON export to the canonical **BlackboexFlow** format (`{version, nodes, edges}`) stored in the database.
- `blackboexToDrawflow(blackboex, buildHTML)` — converts BlackboexFlow back to Drawflow import format, reconstructing port counts and connection maps.

---

### `SidebarTreeDnD` (`hooks/sidebar_tree_dnd.js`)

**Purpose:** Enables drag-and-drop reordering and reparenting within the sidebar navigation tree. Mounts one [Sortable.js](https://sortablejs.github.io/Sortable/) instance per `[data-tree-list]` element inside the hook root, with cross-list drag enabled via a shared group name `"sidebar-tree"`.

**Registered in:** `assets/js/app.js` — imported directly and added to the `hooks: {...}` map passed to `new LiveSocket(...)`.

**Logic libs:** `lib/ui/sidebar_tree_dnd.js`

**Tests:** `test/lib/ui/sidebar_tree_dnd.test.js`

**Used by:** `BlackboexWeb.Components.SidebarTreeComponent` — `phx-hook="SidebarTreeDnD"` on the `<nav>` element (which also has `phx-target={@myself}` so events route to the LiveComponent)

**Vendor dependency:** `assets/vendor/sortable.js` — Sortable.js 1.15.2 minified UMD bundle

**DOM attributes (consumed, not set by this hook):**

- `[data-tree-list]` on each group `<ul>` — marks it as a Sortable list
- `data-parent-type` on `[data-tree-list]` — group type (`"apis"`, `"flows"`, `"pages"`, `"playgrounds"`)
- `data-parent-id` on `[data-tree-list]` — project id of the containing project
- `[data-tree-item]` on each leaf `<li>` — marks it as a draggable item
- `data-node-id` on `[data-tree-item]` — resource UUID
- `data-node-type` on `[data-tree-item]` — singular resource type (`"api"`, `"flow"`, `"page"`, `"playground"`)

**Sortable config:**

- `group: "sidebar-tree"` — enables cross-list drag between all lists in the tree
- `delay: 150, delayOnTouchOnly: true` — prevents accidental drags on mobile
- `animation: 120` — smooth 120 ms reorder animation
- `draggable: "[data-tree-item]"` — only LI items are draggable (not the "No items" placeholder)

**Pushes to LiveView (via `pushEventTo(this.el, ...)`):**

- `"move_node"` — on drag-end; payload `%{node_id, node_type, new_parent_type, new_parent_id, new_index}`. Routes to the LiveComponent (not the parent LiveView) because `this.el` has `phx-target={@myself}`.

**Handles from LiveView:**

- `"sidebar_tree:rollback"` — destroys and reinitialises all Sortable instances on the next animation frame so the DOM snaps back to the server-authoritative order after a rejected move; payload `%{reason: string}` (ignored by client)

**Lifecycle:** `mounted` (initialises Sortable instances + registers rollback handler), `updated` (destroys + reinitialises all Sortable instances to pick up new DOM from LiveView patch), `destroyed` (destroys all Sortable instances)

---

### `SidebarCollapse` (`hooks/global/sidebar_collapse_hook.js`)

**Purpose:** Restores and persists the global sidebar collapsed state in `localStorage`.

**Registered in:** `assets/js/app.js`

**Logic libs:** `lib/global/sidebar_collapse.js`

**Tests:** `test/hooks/global/sidebar_collapse_hook.test.js`

**DOM attributes:** none

**Pushes to LiveView:** none

**Handles from LiveView:** none

**Lifecycle:** `mounted` (restores state and listens for `sidebar:toggled`), `destroyed` (removes listener)

---

## Adding a New Hook

1. **Create** `assets/js/hooks/my_hook.js` exporting a plain object with `mounted()` and any other lifecycle methods needed.
2. **Move logic** into `assets/js/lib/**` first when the hook needs calculations, parsing, storage, payload building, editor setup, or browser side effects.
3. **Register** the hook by importing it in `assets/js/app.js` and adding it to the initial `hooks` map passed to `LiveSocket`.
4. **Add tests**:
   - Hook wiring tests go in `assets/test/hooks/**`.
   - Lib tests go in `assets/test/lib/**`.
5. **Add `phx-hook="MyHook"`** to the target element in the relevant HEEx template or component. Include `phx-update="ignore"` if LiveView should not re-render the element's children (typical for editor hooks).
6. **Document it** here: hook name, file, purpose, DOM attributes, events pushed/handled, lifecycle callbacks, logic libs, tests, and which component uses it.
