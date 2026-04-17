# JavaScript LiveView Hooks

## Overview

Phoenix LiveView hooks are JavaScript objects that manage client-side behaviour for DOM elements tagged with `phx-hook="HookName"`. Each hook can listen for LiveView server pushes (`handleEvent`), send events back to the server (`pushEvent`), and react to DOM lifecycle callbacks (`mounted`, `updated`, `destroyed`).

Hooks in this project are split across two locations:

- **`assets/js/hooks/`** — complex editor hooks, each in its own file, loaded lazily via feature bundles (`editor_code.js`, `editor_flow.js`, `editor_tiptap.js`).
- **`assets/js/app.js`** — lightweight utility hooks defined inline and registered directly on the `LiveSocket`.

Feature-bundle hooks are registered into `window.__hooks` before `app.js` runs; `app.js` merges them into the `LiveSocket` hooks map via `{ ...featureHooks }`.

---

## Hook Catalog

### `CodeEditor` (`hooks/code_editor.js`)

**Purpose:** Mounts a read-only or editable [CodeMirror 6](https://codemirror.net/) code editor inside a div. Supports multiple languages and optional blur-triggered event pushing.

**Registered in:** `assets/js/editor_code.js` → `window.__hooks.CodeEditor`

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

**Registered in:** `assets/js/editor_code.js` → `window.__hooks.PlaygroundEditor`

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

**Registered in:** `assets/js/editor_flow.js` → `window.__hooks.DrawflowEditor`

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

**Registered in:** `assets/js/editor_code.js` → `window.__hooks.ResizablePanels`

**Used by:** `live/playground_live/edit.ex` via `phx-hook="ResizablePanels"` on `#playground-panels`

**DOM attributes on `[data-resize-handle]` children (not the hook element itself):**
- `data-resize-direction` — `"vertical"` (controls height) or `"horizontal"` (controls width)
- `data-resize-target` — `id` of the panel element to resize
- `data-resize-css-var` — *(optional)* CSS custom property name (e.g. `"--playground-output-pane-height"`) to write the size to on `:root` instead of mutating `style.height/width` on the target. Use this when the target is inside a LiveView region whose re-render would otherwise reset the inline style; declare the target with `style="height: var(--name, <default>);"` so the server-rendered style is stable and the CSS variable carries the user's chosen size.

**Constraints (hardcoded):**
- vertical: min 100 px, max 600 px
- horizontal: min 200 px, max 500 px

**Pushes to LiveView:** none

**Handles from LiveView:** none

**Lifecycle:** `mounted` (restores persisted sizes, attaches drag handlers), `destroyed` (removes all listeners and cleans up overlay)

---

### `TiptapEditor` (`hooks/tiptap_editor.js`)

**Purpose:** Mounts a full rich-text editor (Tiptap + ProseMirror) with Markdown serialisation, slash commands, bubble menu, syntax-highlighted code blocks (lowlight), tables, task lists, links, images, and character count. Content is serialised as Markdown before being pushed to the server.

**Registered in:** `assets/js/editor_tiptap.js` → `window.__hooks.TiptapEditor`

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

### `KeyboardShortcuts` (`app.js`)

**Purpose:** Global keyboard shortcut handler for the API editor shell. Intercepts `keydown` on `window` and dispatches named LiveView events for common editor actions.

**Used by:** `live/api_live/edit/editor_shell.ex` via `phx-hook="KeyboardShortcuts"`

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

### `AutoFocus` (`app.js`)

**Purpose:** Focuses the element immediately on mount and on each update. Used for command palette inputs that need focus when they appear.

**Used by:** command palette input elements

**DOM attributes:** none

**Pushes to LiveView:** none

**Handles from LiveView:** none

**Lifecycle:** `mounted` (calls `this.el.focus()`), `updated` (calls `this.el.focus()` and scrolls the selected command palette item into view)

---

### `ChatAutoScroll` (`app.js`)

**Purpose:** Keeps a scrollable chat timeline pinned to the bottom as new messages and streaming tokens arrive. Uses both a `MutationObserver` and a 150 ms polling interval to catch morphdom text patches that the observer may miss. Pauses auto-scroll when the user manually scrolls up.

**Used by:**
- `components/editor/chat_panel.ex` on `#chat-messages` via `phx-hook="ChatAutoScroll"`
- `components/editor/playground_chat_panel.ex` on `#playground-chat-timeline` via `phx-hook="ChatAutoScroll"`

**DOM attributes:** none

**Pushes to LiveView:** none

**Handles from LiveView:** none

**Lifecycle:** `mounted` (sets up MutationObserver, polling interval, and scroll listener), `updated` (scrolls to bottom if user has not scrolled up), `destroyed` (disconnects observer, clears interval)

---

### `EditorAutoScroll` (`app.js`)

**Purpose:** Keeps the file editor's code region scrolled to the bottom during AI streaming. Polls every 150 ms for height changes and watches for manual scroll-up to pause auto-scroll. Targets the first `.overflow-y-auto` child inside the hook element.

**Used by:** `components/editor/file_editor.ex` on `#editor-scroll-region` via `phx-hook="EditorAutoScroll"`

**DOM attributes:** none

**Pushes to LiveView:** none

**Handles from LiveView:** none

**Lifecycle:** `mounted` (attaches polling interval and scroll listener), `updated` (scrolls to bottom if user has not scrolled up), `destroyed` (clears polling interval)

---

### `CommandPaletteNav` (`app.js`)

**Purpose:** Handles keyboard navigation (ArrowUp / ArrowDown) inside the command palette list and scrolls the currently selected item into view on each update.

**Used by:** `components/editor/command_palette.ex` via `phx-hook="CommandPaletteNav"`

**DOM attributes:** none

**Pushes to LiveView:**
- `"command_palette_navigate"` — on `ArrowDown` or `ArrowUp`; payload `%{direction: "down" | "up"}`

**Handles from LiveView:** none

**Lifecycle:** `mounted` (focuses element, attaches `keydown` listener), `updated` (re-focuses element, scrolls selected item into view)

---

## Note on `drawflow_converter.js`

`hooks/drawflow_converter.js` is **not a hook** — it exports two pure utility functions used internally by `DrawflowEditor`:

- `drawflowToBlackboex(drawflowData)` — converts Drawflow's internal JSON export to the canonical **BlackboexFlow** format (`{version, nodes, edges}`) stored in the database.
- `blackboexToDrawflow(blackboex, buildHTML)` — converts BlackboexFlow back to Drawflow import format, reconstructing port counts and connection maps.

---

## Adding a New Hook

1. **Create** `assets/js/hooks/my_hook.js` exporting a plain object with `mounted()` and any other lifecycle methods needed.
2. **Register** the hook in the appropriate feature bundle:
   - For code/editor pages: add `window.__hooks.MyHook = MyHook` in `editor_code.js`, `editor_flow.js`, or `editor_tiptap.js`.
   - For a simple utility hook: define it inline in `app.js` and add it to the `hooks: { ... }` map passed to `new LiveSocket(...)`.
3. **Add `phx-hook="MyHook"`** to the target element in the relevant HEEx template or component. Include `phx-update="ignore"` if LiveView should not re-render the element's children (typical for editor hooks).
4. **Document it** here: hook name, file, purpose, DOM attributes, events pushed/handled, lifecycle callbacks, and which component uses it.
