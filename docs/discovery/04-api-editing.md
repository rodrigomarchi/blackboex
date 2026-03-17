# Discovery: API Editing Workflow

> **Date**: 2026-03-17
> **Context**: BlackBoex -- platform where users describe APIs in natural language, an LLM generates Elixir code, and users can publish it as a REST endpoint.
> **Goal**: Design the editing workflow where users can view, modify, refine (via chat or manual edits), version, diff, and hot-reload generated API code.

---

## Table of Contents

1. [Code Editors in the Browser](#1-code-editors-in-the-browser)
2. [Conversational Editing (Chat-Driven Refinement)](#2-conversational-editing-chat-driven-refinement)
3. [Version Control for Generated Code](#3-version-control-for-generated-code)
4. [Diff Visualization](#4-diff-visualization)
5. [Hot Code Reloading](#5-hot-code-reloading)
6. [Schema Migration on Edit](#6-schema-migration-on-edit)
7. [Collaborative Editing](#7-collaborative-editing)
8. [Architecture Recommendation for BlackBoex](#8-architecture-recommendation-for-blackboex)

---

## 1. Code Editors in the Browser

### 1.1 Options Overview

| Editor | Bundle Size | Language Support | Diff Built-in | LiveView Integration | Maturity |
|---|---|---|---|---|---|
| **Monaco Editor** | ~2 MB (lazy-loadable) | Excellent (VS Code engine) | Yes (native diff editor) | `live_monaco_editor` hex package | Production-ready |
| **CodeMirror 6** | ~150 KB (modular) | Good (community grammars) | Via extensions | Manual hook (no official package) | Production-ready |
| **Ace Editor** | ~300 KB | Good | No native diff | Manual hook | Mature but declining |

### 1.2 Recommendation: Monaco via `live_monaco_editor`

Monaco is the clear winner for BlackBoex because:

- **Native diff editor** -- Monaco ships `createDiffEditor()` out of the box, which we need for showing what the LLM changed.
- **`live_monaco_editor`** -- An official Hex package built by the BeaconCMS team. It wraps Monaco in a Phoenix LiveView component with proper lifecycle management.
- **Elixir syntax** -- Monaco inherits VS Code's TextMate grammar system, so Elixir highlighting works via the `elixir` language ID.
- **Livebook precedent** -- Livebook (the official Elixir notebook tool) uses CodeMirror, but their use case is lightweight cells. For a full-file API editor with diff, Monaco is more appropriate.

### 1.3 Integration with Phoenix LiveView

Monaco (and any JS-heavy editor) integrates with LiveView via **JavaScript Hooks** (`phx-hook`). The hook lifecycle:

```
mounted()       -> Create editor instance, set initial value
updated()       -> Sync server-pushed code changes into the editor
destroyed()     -> Dispose editor instance to avoid memory leaks
```

#### Using `live_monaco_editor`

Add to `mix.exs`:

```elixir
{:live_monaco_editor, "~> 0.2"}
```

In `app.js`:

```javascript
import { CodeEditorHook } from "live_monaco_editor"

let liveSocket = new LiveSocket("/live", Socket, {
  hooks: { CodeEditorHook },
  // ...
})
```

In a LiveView template:

```heex
<LiveMonacoEditor.code_editor
  path="api_module.ex"
  value={@code}
  opts={
    Map.new([
      {"language", "elixir"},
      {"fontSize", 14},
      {"minimap", %{"enabled" => false}},
      {"wordWrap", "on"},
      {"scrollBeyondLastLine", false}
    ])
  }
/>
```

Listen for changes:

```elixir
def handle_event("lme:change", %{"value" => new_code}, socket) do
  {:noreply, assign(socket, :code, new_code)}
end
```

#### Custom Hook (if more control is needed)

```javascript
const CodeEditor = {
  mounted() {
    this.editor = monaco.editor.create(this.el, {
      value: this.el.dataset.code,
      language: "elixir",
      theme: "vs-dark",
      automaticLayout: true,
    })

    this.editor.onDidChangeModelContent(() => {
      this.pushEvent("code_changed", {
        code: this.editor.getValue()
      })
    })

    this.handleEvent("set_code", ({ code }) => {
      const currentCode = this.editor.getValue()
      if (currentCode !== code) {
        this.editor.setValue(code)
      }
    })
  },

  destroyed() {
    this.editor.dispose()
  }
}
```

### 1.4 Debouncing and Performance

User keystrokes should NOT be sent on every character. Use a debounce strategy:

```javascript
// In the hook
this.editor.onDidChangeModelContent(
  _.debounce(() => {
    this.pushEvent("code_changed", { code: this.editor.getValue() })
  }, 500)
)
```

Alternatively, only send code on explicit save (`Ctrl+S`) or when leaving the editor (blur event). For BlackBoex, where code is generated and then tweaked, **save-on-blur + explicit save** is preferable to continuous sync.

### 1.5 Read-Only vs. Editable Modes

The editor should support toggling between modes:

- **Read-only**: When viewing a previous version or diff.
- **Editable**: When the user is actively refining code.

```javascript
this.editor.updateOptions({ readOnly: isReadOnly })
```

---

## 2. Conversational Editing (Chat-Driven Refinement)

### 2.1 The Pattern: Chat + Code Side-by-Side

Modern AI code tools have converged on a split-pane UI pattern:

| Product | Left Pane | Right Pane | Key Innovation |
|---|---|---|---|
| **Claude Artifacts** | Chat conversation | Live preview / code | Iterative refinement through follow-up messages |
| **ChatGPT Canvas** | Chat | Collaborative editor | **Highlight-to-edit**: select code, type instruction |
| **Cursor** | Chat panel | Full code editor | Inline diff suggestions with accept/reject |
| **v0 (Vercel)** | Prompt input | Generated UI preview | Iterative prompt refinement |

### 2.2 UX Pattern for BlackBoex

The BlackBoex editing page should have three zones:

```
+-------------------------------------------+
|  [API Name]  [Version: v3]  [Publish]     |
+-------------------------------------------+
|              |                |            |
|   Chat       |   Code Editor  |  Preview  |
|   Panel      |   (Monaco)     |  Panel    |
|              |                |  (opt.)   |
|   User:      |  defmodule ... |           |
|   "Add auth" |    ...         |  Endpoint |
|              |    ...         |  tester   |
|   LLM:       |                |           |
|   "Added     |                |           |
|    bearer.." |                |           |
|              |                |            |
+-------------------------------------------+
|  [Diff View]  [History]  [Test]           |
+-------------------------------------------+
```

### 2.3 Interaction Flows

#### Flow A: Chat-Driven Edit

1. User types: "Add authentication with Bearer token"
2. System sends to LLM: current code + conversation history + instruction
3. LLM returns new version of the code
4. System shows diff (old vs. new) in the editor
5. User clicks "Accept" or "Reject" (or edits further)
6. On accept, new version is saved

#### Flow B: Manual Edit + Validation

1. User edits code directly in Monaco
2. On save, system compiles the code (`Code.compile_string/1`) to check syntax
3. If valid, new version is saved
4. If invalid, error annotations appear in the editor margin

#### Flow C: Highlight-to-Edit (ChatGPT Canvas Pattern)

1. User selects a section of code in the editor
2. A small input box appears: "What should this do instead?"
3. System sends just the selected range + instruction to the LLM
4. LLM returns a replacement for that specific section
5. Inline diff shows the proposed change

### 2.4 Prompt Architecture for Iterative Editing

Each edit request to the LLM should include:

```elixir
%{
  system_prompt: "You are editing an Elixir API module for BlackBoex...",
  messages: [
    # Full conversation history for this API
    %{role: "user", content: "Create a REST API for a todo list"},
    %{role: "assistant", content: "```elixir\ndefmodule ...\n```"},
    %{role: "user", content: "Add authentication with Bearer token"},
    # The new instruction
  ],
  # Current code state (may differ from last LLM output if user edited manually)
  current_code: "defmodule MyApi do\n  ...\nend",
}
```

Key principle: **always send the current code state**, not just the conversation. The user may have manually edited the code between chat messages, so the LLM needs to see the actual current state.

### 2.5 Structured Output for Edits

Instead of asking the LLM to return the full file every time (wasteful for large files), consider asking for a structured edit:

```json
{
  "explanation": "Added Bearer token authentication...",
  "edits": [
    {
      "type": "insert_after",
      "anchor": "plug :accepts, [\"json\"]",
      "code": "plug :authenticate_bearer"
    },
    {
      "type": "append_function",
      "code": "defp authenticate_bearer(conn, _opts) do\n  ...\nend"
    }
  ]
}
```

However, for BlackBoex v1, **full-file replacement is simpler and more reliable**. Structured edits can be explored later for large modules.

### 2.6 Conversation Persistence

Store the conversation alongside the API:

```elixir
schema "api_conversations" do
  belongs_to :api, Api
  field :messages, {:array, :map}  # [{role, content, timestamp}]
  timestamps()
end
```

This enables:
- Resuming editing sessions
- Understanding the "why" behind each version
- Replaying the design process

---

## 3. Version Control for Generated Code

### 3.1 Library Options

| Library | Approach | Rollback | Multi-table | Maintenance |
|---|---|---|---|---|
| **PaperTrail** | Stores full snapshots in a `versions` table | Yes, built-in | Via `item_type` + `item_id` | Active, v1.1.2 |
| **ex_audit** | Wraps `Ecto.Repo`, stores diffs | Yes, built-in | Transparent | Active, v0.10.0 |
| **Ecto Trail** | Changeset-based audit log | Manual | Separate table | Low activity |
| **Custom** | Purpose-built for code versioning | Full control | N/A | You maintain it |

### 3.2 Recommendation: Custom Version Table

For BlackBoex, neither PaperTrail nor ex_audit is ideal because we are not versioning generic Ecto records -- we are versioning **code artifacts** with associated metadata (LLM conversation, compilation status, deployment state). A purpose-built schema is cleaner:

```elixir
defmodule Blackboex.Apis.ApiVersion do
  use Ecto.Schema

  schema "api_versions" do
    belongs_to :api, Blackboex.Apis.Api
    field :version_number, :integer
    field :code, :string           # The full Elixir source code
    field :source, Ecto.Enum, values: [:llm_generated, :user_edited, :llm_refined]
    field :prompt, :string         # The user instruction that produced this version
    field :llm_response, :string   # The raw LLM response (for debugging)
    field :compilation_status, Ecto.Enum, values: [:pending, :success, :error]
    field :compilation_errors, {:array, :string}, default: []
    field :diff_from_previous, :string  # Stored diff for quick display
    field :metadata, :map, default: %{}
    belongs_to :created_by, Blackboex.Accounts.User

    timestamps()
  end
end
```

### 3.3 Version Lifecycle

```
User prompt ──> LLM generates code ──> Compile check ──> Save as version N
                                              │
                                         (errors?) ──> Show errors, do NOT save as version
                                                       Let user/LLM fix first
```

### 3.4 Rollback

```elixir
defmodule Blackboex.Apis do
  @spec rollback_api(Api.t(), integer()) :: {:ok, ApiVersion.t()} | {:error, term()}
  def rollback_api(%Api{} = api, target_version_number) do
    case Repo.get_by(ApiVersion, api_id: api.id, version_number: target_version_number) do
      nil ->
        {:error, :version_not_found}

      version ->
        # Create a NEW version with the old code (don't delete history)
        create_version(api, %{
          code: version.code,
          source: :user_edited,
          prompt: "Rollback to version #{target_version_number}"
        })
    end
  end
end
```

Key design decision: **rollback creates a new version** rather than deleting versions. This preserves full history.

### 3.5 Storage Considerations

- Each version stores the **full code**, not a delta. Code files for single-module APIs are typically 1-10 KB, so storage is not a concern even with hundreds of versions.
- For display purposes, the `diff_from_previous` field stores a pre-computed diff string so the UI does not need to recompute it every time.
- Old versions can be archived to cold storage after N days if needed.

---

## 4. Diff Visualization

### 4.1 Generating Diffs in Elixir

Elixir ships with `String.myers_difference/2`, which implements the Myers diff algorithm:

```elixir
iex> String.myers_difference("the fox hops", "the fox jumps")
[eq: "the fox ", del: "ho", ins: "jum", eq: "ps"]
```

For line-level diffs (more appropriate for code), split into lines first:

```elixir
defmodule Blackboex.Diff do
  @spec line_diff(String.t(), String.t()) :: [{:eq | :ins | :del, [String.t()]}]
  def line_diff(old_code, new_code) do
    old_lines = String.split(old_code, "\n")
    new_lines = String.split(new_code, "\n")
    List.myers_difference(old_lines, new_lines)
  end
end
```

`List.myers_difference/2` returns the same `:eq`, `:ins`, `:del` structure but operating on lists of lines.

### 4.2 Third-Party Diff Libraries

| Library | Description | Output Format |
|---|---|---|
| **`diff`** (bryanjos) | General diff with `Diff.Diffable` protocol | Edit script (keyword list) |
| **`diffie`** | Diff reports for strings and lists | Structured report |
| **`exdiff`** | Text diff with HTML output | HTML with CSS classes for ins/del/eq |
| Built-in `String.myers_difference/2` | No dependency needed | Keyword list edit script |
| Built-in `List.myers_difference/2` | No dependency needed | Keyword list edit script |

**Recommendation**: Use the built-in `List.myers_difference/2` for line-level diffs. No extra dependency needed.

### 4.3 Rendering Diffs in the Browser

#### Option A: Monaco Diff Editor (Recommended)

Monaco has a built-in diff editor that renders side-by-side or inline diffs with VS Code quality:

```javascript
const DiffViewer = {
  mounted() {
    const originalModel = monaco.editor.createModel(
      this.el.dataset.original, "elixir"
    )
    const modifiedModel = monaco.editor.createModel(
      this.el.dataset.modified, "elixir"
    )

    this.diffEditor = monaco.editor.createDiffEditor(this.el, {
      readOnly: true,
      renderSideBySide: true,       // false for inline view
      automaticLayout: true,
      originalEditable: false,
    })

    this.diffEditor.setModel({ original: originalModel, modified: modifiedModel })
  },

  destroyed() {
    this.diffEditor.dispose()
  }
}
```

This gives us:
- Side-by-side or inline diff views
- Syntax-highlighted diffs
- Mini-map showing change locations
- Navigation between changes

#### Option B: Server-Rendered Diff (for email notifications, lightweight views)

Generate HTML diffs server-side:

```elixir
defmodule BlackboexWeb.DiffRenderer do
  @spec to_html(String.t(), String.t()) :: Phoenix.HTML.safe()
  def to_html(old_code, new_code) do
    old_code
    |> String.split("\n")
    |> List.myers_difference(String.split(new_code, "\n"))
    |> Enum.flat_map(fn
      {:eq, lines}  -> Enum.map(lines, &{"eq", &1})
      {:del, lines} -> Enum.map(lines, &{"del", &1})
      {:ins, lines} -> Enum.map(lines, &{"ins", &1})
    end)
    |> Enum.map(fn {type, line} ->
      ~s(<div class="diff-#{type}">#{Phoenix.HTML.html_escape(line)}</div>)
    end)
    |> Enum.join("\n")
    |> Phoenix.HTML.raw()
  end
end
```

With Tailwind CSS:

```css
.diff-eq  { @apply text-gray-300; }
.diff-del { @apply bg-red-900/30 text-red-300; }
.diff-ins { @apply bg-green-900/30 text-green-300; }
```

### 4.4 Storing Diffs for Quick Access

Pre-compute and store the diff when creating a new version:

```elixir
defp compute_and_store_diff(api, new_code) do
  case get_latest_version(api) do
    nil -> ""
    prev ->
      prev.code
      |> String.split("\n")
      |> List.myers_difference(String.split(new_code, "\n"))
      |> inspect()  # Or use a more compact serialization
  end
end
```

---

## 5. Hot Code Reloading

### 5.1 BEAM Hot Code Loading Fundamentals

The BEAM VM can hold **two versions** of a module simultaneously: the "current" version and the "old" version. When a new version is loaded:

1. The new version becomes "current"
2. The previous "current" becomes "old"
3. Any processes running code in the "old" version continue until they make an external call, at which point they switch to "current"
4. If a third version is loaded, processes still on the "old" version are killed

Relevant Erlang functions:

```elixir
# Compile and load a module from a string
Code.compile_string(source_code)
# Returns: [{ModuleName, bytecode}]

# Purge old version of a module (kills processes on old version)
:code.purge(ModuleName)

# Soft purge (fails if processes still on old version)
:code.soft_purge(ModuleName)

# Load binary directly
:code.load_binary(ModuleName, ~c"filename.beam", bytecode)
```

### 5.2 Dynamic Module Loading for BlackBoex

When a user publishes an API, the system compiles and loads it as a BEAM module:

```elixir
defmodule Blackboex.Runtime.ModuleLoader do
  require Logger

  @spec load_module(String.t()) :: {:ok, module()} | {:error, term()}
  def load_module(source_code) do
    try do
      case Code.compile_string(source_code) do
        [{module_name, _bytecode} | _] ->
          Logger.info("Loaded module: #{inspect(module_name)}")
          {:ok, module_name}

        [] ->
          {:error, :no_module_defined}
      end
    rescue
      error in [CompileError, SyntaxError, TokenMissingError] ->
        {:error, {:compilation_failed, Exception.message(error)}}
    end
  end

  @spec reload_module(module(), String.t()) :: {:ok, module()} | {:error, term()}
  def reload_module(existing_module, new_source_code) do
    # Soft purge first -- if processes are running old code, wait
    :code.soft_purge(existing_module)

    case load_module(new_source_code) do
      {:ok, ^existing_module} = result ->
        result

      {:ok, different_module} ->
        # Module name changed -- clean up old one
        :code.purge(existing_module)
        :code.delete(existing_module)
        {:ok, different_module}

      error ->
        error
    end
  end
end
```

### 5.3 Security: Sandboxing User Code

**Critical concern**: Generated code runs inside the BEAM VM. A malicious or buggy module could:

- Access the file system
- Make network calls
- Crash the VM
- Read environment variables (DB credentials, API keys)

#### Sandboxing Options

| Approach | Security Level | Performance | Complexity |
|---|---|---|---|
| **Dune** (Hex package) | Moderate (allowlist-based) | Good (same VM) | Low |
| **Separate BEAM node** | High (OS-level isolation) | Moderate (network hop) | Medium |
| **Docker container per API** | Very high (full isolation) | Lower (container overhead) | High |
| **Firecracker microVM** | Highest | Lowest (VM startup) | Very high |

**Dune** (`{:dune, "~> 0.3"}`) provides an allowlist mechanism:
- No access to environment variables, file system, or network
- Prevents actual module creation while simulating basic module behavior
- Atom leak protection
- **Caveat**: Dune explicitly warns it cannot offer strong security guarantees

**Recommendation for BlackBoex**:

- **Phase 1 (MVP)**: Use `Code.compile_string/1` with a **restricted module template** -- the generated code must conform to a specific structure (router + handlers), and the compilation happens in a supervised process with a timeout. Do not allow arbitrary code; only fill in predefined slots.
- **Phase 2**: Run user APIs in **separate BEAM nodes** connected via distributed Erlang. If a user API crashes, only its node goes down.
- **Phase 3**: Move to **container-based isolation** (Docker/Firecracker) for production multi-tenant use.

### 5.4 Module Naming Strategy

Each user API needs a unique, deterministic module name:

```elixir
defmodule Blackboex.Runtime.ModuleNaming do
  @spec module_name(String.t()) :: module()
  def module_name(api_id) do
    # Deterministic: same API always gets the same module name
    Module.concat([Blackboex.UserApis, "Api_#{api_id}"])
  end
end

# Result: Blackboex.UserApis.Api_abc123def456
```

### 5.5 Zero-Downtime Reload Flow

```
1. User saves new version
2. Compile new code (Code.compile_string) -- if error, abort
3. :code.soft_purge(OldModule) -- waits for in-flight requests
4. Load new bytecode
5. Update routing table to point to new module
6. Confirm to user: "API updated, no downtime"
```

The BEAM's ability to hold two module versions simultaneously means in-flight requests complete on the old version while new requests hit the new version. This is inherently zero-downtime.

---

## 6. Schema Migration on Edit

### 6.1 The Problem

When a user edits an API and the data model changes (e.g., adds a field to the "todos" table), we need to run a database migration on their schema. This must happen:

- Without downtime (their API stays live)
- Safely (no data loss)
- Automatically (users should not write migrations manually)

### 6.2 Safe Migration Patterns

From Fly.io's "Safe Ecto Migrations" guide and Ecto documentation:

| Operation | Safe? | Notes |
|---|---|---|
| Add nullable column | Yes | Old code ignores it |
| Add column with default | Yes (Postgres 11+) | Postgres handles defaults efficiently |
| Add NOT NULL column | No | Must do in steps: add nullable, backfill, add constraint |
| Remove column | No | Old code still references it. Must deploy code first, then migrate |
| Rename column | No | Use add + copy + drop strategy |
| Add index | Use `CREATE INDEX CONCURRENTLY` | Requires `@disable_ddl_transaction true` |
| Change column type | Depends | Some casts are safe, others require new column |

### 6.3 Auto-Generated Migrations for BlackBoex

When the LLM produces a new version of an API, it should also produce a migration diff:

```elixir
defmodule Blackboex.Migrations.AutoGenerator do
  @spec generate_migration(old_schema :: map(), new_schema :: map()) :: String.t()
  def generate_migration(old_schema, new_schema) do
    added_fields = Map.keys(new_schema) -- Map.keys(old_schema)
    removed_fields = Map.keys(old_schema) -- Map.keys(new_schema)

    migration_steps =
      Enum.map(added_fields, fn field ->
        type = Map.get(new_schema, field)
        "add :#{field}, :#{type}"
      end) ++
      Enum.map(removed_fields, fn field ->
        "remove :#{field}  # CAUTION: data will be lost"
      end)

    """
    defmodule Blackboex.Repo.Migrations.UpdateApi#{:rand.uniform(999_999)} do
      use Ecto.Migration

      def change do
        alter table(:user_api_data) do
          #{Enum.join(migration_steps, "\n      ")}
        end
      end
    end
    """
  end
end
```

### 6.4 Multi-Tenant Migration Strategy

Each user API should have its own **namespaced tables** (or schemas in PostgreSQL terms):

```sql
-- Each API gets its own PostgreSQL schema
CREATE SCHEMA api_abc123def456;

-- API tables live inside it
CREATE TABLE api_abc123def456.todos (
  id BIGSERIAL PRIMARY KEY,
  title TEXT,
  completed BOOLEAN DEFAULT false
);
```

Benefits:
- **Isolation**: One API's migration cannot affect another
- **Clean teardown**: `DROP SCHEMA api_abc123def456 CASCADE` removes everything
- **Ecto support**: Set `@schema_prefix` in the generated Ecto schema

```elixir
# In generated code
defmodule Blackboex.UserApis.Api_abc123.Todo do
  use Ecto.Schema
  @schema_prefix "api_abc123def456"

  schema "todos" do
    field :title, :string
    field :completed, :boolean, default: false
    timestamps()
  end
end
```

### 6.5 Migration Execution

```elixir
defmodule Blackboex.Migrations.Runner do
  @spec run_migration(String.t(), String.t()) :: :ok | {:error, term()}
  def run_migration(api_id, migration_source) do
    # Compile the migration module
    [{migration_module, _}] = Code.compile_string(migration_source)

    # Run it within a transaction
    Ecto.Migrator.up(Blackboex.Repo, version_number(), migration_module)
  end

  defp version_number do
    System.system_time(:second)
  end
end
```

### 6.6 Rollback Considerations

When rolling back an API version, the migration must also be reversed:

1. Check if the rollback changes the schema
2. If yes, generate a reverse migration
3. Show the user what data changes will occur (e.g., "Column `priority` will be dropped, losing existing data")
4. Require explicit confirmation for destructive changes

---

## 7. Collaborative Editing

### 7.1 Phoenix's Built-in Real-Time Capabilities

Phoenix is uniquely suited for collaborative editing:

- **PubSub**: Built-in publish/subscribe for broadcasting changes across connections
- **Presence**: CRDT-based tracking of who is online and what they are doing
- **LiveView**: Server-rendered UI that updates in real-time over WebSockets

### 7.2 Architecture for Collaborative API Editing

```
User A (LiveView) ──> PubSub topic: "api:abc123" <── User B (LiveView)
                              │
                        GenServer (ApiEditor)
                         - Current code state
                         - Lock/cursor positions
                         - Change buffer
```

#### Using Phoenix Presence for Cursor Tracking

```elixir
defmodule BlackboexWeb.Presence do
  use Phoenix.Presence,
    otp_app: :blackboex_web,
    pubsub_server: Blackboex.PubSub
end

# In the LiveView
def mount(%{"api_id" => api_id}, _session, socket) do
  topic = "api_editor:#{api_id}"

  if connected?(socket) do
    BlackboexWeb.Presence.track(self(), topic, socket.assigns.current_user.id, %{
      username: socket.assigns.current_user.username,
      cursor_line: 0,
      cursor_col: 0,
      color: random_color()
    })

    Phoenix.PubSub.subscribe(Blackboex.PubSub, topic)
  end

  presences = BlackboexWeb.Presence.list(topic)
  {:ok, assign(socket, presences: presences, topic: topic)}
end

def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff", payload: diff}, socket) do
  presences =
    socket.assigns.presences
    |> BlackboexWeb.Presence.sync_diff(diff)

  {:noreply, assign(socket, presences: presences)}
end
```

### 7.3 Conflict Resolution Strategies

For code editing, true concurrent editing (like Google Docs) is extremely complex. Practical approaches:

| Strategy | Complexity | UX | Best For |
|---|---|---|---|
| **Lock-based** | Low | One editor at a time, others view | MVP |
| **Turn-based** | Low | Users take turns, see each other's cursors | Small teams |
| **OT (Operational Transform)** | Very high | Real-time concurrent editing | Google Docs-like |
| **CRDT (Yjs/Automerge)** | High | Real-time concurrent editing | Modern choice |

**Recommendation for BlackBoex**: Start with **lock-based** editing. When User A is editing, User B sees a read-only view with live updates. This is simple, avoids conflicts, and is sufficient for API editing (which is typically a solo activity).

### 7.4 CRDTs in Elixir

For future consideration, if true collaborative editing is needed:

- **Alchemy Book** (`github.com/rudi-c/alchemy-book`): A reference implementation of a collaborative text editor in Elixir using CRDTs.
- **Yjs**: A CRDT framework that runs in JavaScript. Can be integrated via a LiveView hook, with the Elixir backend acting as a relay/persistence layer.
- **Phoenix Presence itself uses CRDTs** internally for tracking presence state across nodes.

The approach would be:
1. Use Yjs on the client side (integrated with Monaco via `y-monaco`)
2. Relay updates through Phoenix Channels
3. Persist the Yjs document state in PostgreSQL
4. Render presence (cursors, selections) via Presence

This is a Phase 3+ feature and should not be built initially.

---

## 8. Architecture Recommendation for BlackBoex

### 8.1 MVP (Phase 1) Architecture

```
┌─────────────────────────────────────────────────────────┐
│                   LiveView Page                         │
│                                                         │
│  ┌──────────────┐  ┌──────────────────┐  ┌───────────┐ │
│  │  Chat Panel   │  │  Monaco Editor    │  │  Actions  │ │
│  │              │  │  (live_monaco_    │  │           │ │
│  │  Conversation│  │   editor)         │  │ [Save]    │ │
│  │  history     │  │                  │  │ [Compile] │ │
│  │              │  │  Elixir syntax   │  │ [Publish] │ │
│  │  Input box   │  │  highlighting    │  │ [Rollback]│ │
│  │  for prompts │  │                  │  │ [Diff]    │ │
│  └──────────────┘  └──────────────────┘  └───────────┘ │
│                                                         │
│  ┌─────────────────────────────────────────────────────┐│
│  │  Status Bar: Version 3 | Last compiled: OK | Live   ││
│  └─────────────────────────────────────────────────────┘│
└─────────────────────────────────────────────────────────┘
```

### 8.2 Data Model

```elixir
# In apps/blackboex/lib/blackboex/apis/api.ex
defmodule Blackboex.Apis.Api do
  use Ecto.Schema

  schema "apis" do
    field :name, :string
    field :slug, :string                  # URL-friendly identifier
    field :description, :string
    field :current_version_id, :id        # Points to the active version
    field :status, Ecto.Enum, values: [:draft, :published, :archived]
    field :module_name, :string           # e.g., "Blackboex.UserApis.Api_abc123"
    field :db_schema_prefix, :string      # e.g., "api_abc123"
    belongs_to :user, Blackboex.Accounts.User
    has_many :versions, Blackboex.Apis.ApiVersion
    has_one :conversation, Blackboex.Apis.ApiConversation
    timestamps()
  end
end

# In apps/blackboex/lib/blackboex/apis/api_version.ex
defmodule Blackboex.Apis.ApiVersion do
  use Ecto.Schema

  schema "api_versions" do
    belongs_to :api, Blackboex.Apis.Api
    field :version_number, :integer
    field :code, :string
    field :source, Ecto.Enum, values: [:llm_generated, :user_edited, :llm_refined]
    field :prompt, :string
    field :compilation_status, Ecto.Enum, values: [:pending, :success, :error]
    field :compilation_errors, {:array, :string}, default: []
    field :diff_from_previous, :string
    field :schema_snapshot, :map          # The data model at this version
    field :migration_code, :string        # Migration needed from previous version
    belongs_to :created_by, Blackboex.Accounts.User
    timestamps()
  end
end

# In apps/blackboex/lib/blackboex/apis/api_conversation.ex
defmodule Blackboex.Apis.ApiConversation do
  use Ecto.Schema

  schema "api_conversations" do
    belongs_to :api, Blackboex.Apis.Api
    field :messages, {:array, :map}, default: []
    # Each message: %{"role" => "user"|"assistant", "content" => "...", "timestamp" => "..."}
    timestamps()
  end
end
```

### 8.3 Core Editing Context

```elixir
defmodule Blackboex.Apis do
  alias Blackboex.Repo
  alias Blackboex.Apis.{Api, ApiVersion, ApiConversation}

  @spec create_version(Api.t(), map()) :: {:ok, ApiVersion.t()} | {:error, Ecto.Changeset.t()}
  def create_version(%Api{} = api, attrs) do
    latest = get_latest_version(api)
    version_number = if latest, do: latest.version_number + 1, else: 1

    diff =
      if latest do
        latest.code
        |> String.split("\n")
        |> List.myers_difference(String.split(attrs.code, "\n"))
        |> inspect()
      else
        ""
      end

    %ApiVersion{}
    |> ApiVersion.changeset(
      Map.merge(attrs, %{
        api_id: api.id,
        version_number: version_number,
        diff_from_previous: diff
      })
    )
    |> Repo.insert()
  end

  @spec compile_check(String.t()) :: {:ok, module()} | {:error, String.t()}
  def compile_check(code) do
    try do
      case Code.compile_string(code) do
        [{module, _bytecode} | _] -> {:ok, module}
        [] -> {:error, "No module defined"}
      end
    rescue
      e in [CompileError, SyntaxError, TokenMissingError] ->
        {:error, Exception.message(e)}
    end
  end

  @spec get_latest_version(Api.t()) :: ApiVersion.t() | nil
  def get_latest_version(%Api{} = api) do
    ApiVersion
    |> where(api_id: ^api.id)
    |> order_by(desc: :version_number)
    |> limit(1)
    |> Repo.one()
  end
end
```

### 8.4 LiveView Structure

```elixir
defmodule BlackboexWeb.ApiEditorLive do
  use BlackboexWeb, :live_view

  alias Blackboex.Apis

  @impl true
  def mount(%{"id" => api_id}, _session, socket) do
    api = Apis.get_api!(api_id)
    version = Apis.get_latest_version(api)

    {:ok,
     assign(socket,
       api: api,
       current_version: version,
       code: version && version.code || "",
       chat_messages: load_conversation(api),
       chat_input: "",
       compilation_status: version && version.compilation_status || :pending,
       show_diff: false,
       diff_original: nil,
       diff_modified: nil
     )}
  end

  @impl true
  def handle_event("chat_submit", %{"message" => message}, socket) do
    # 1. Add user message to conversation
    # 2. Send to LLM with current code + history
    # 3. Receive new code
    # 4. Show diff
    # 5. Wait for user acceptance
    {:noreply, socket |> assign(:processing, true) |> start_llm_request(message)}
  end

  @impl true
  def handle_event("code_changed", %{"code" => code}, socket) do
    {:noreply, assign(socket, :code, code)}
  end

  @impl true
  def handle_event("save_version", _params, socket) do
    case Apis.compile_check(socket.assigns.code) do
      {:ok, _module} ->
        {:ok, version} =
          Apis.create_version(socket.assigns.api, %{
            code: socket.assigns.code,
            source: :user_edited,
            compilation_status: :success
          })

        {:noreply,
         socket
         |> assign(:current_version, version)
         |> assign(:compilation_status, :success)
         |> put_flash(:info, "Version #{version.version_number} saved")}

      {:error, message} ->
        {:noreply,
         socket
         |> assign(:compilation_status, :error)
         |> put_flash(:error, "Compilation error: #{message}")}
    end
  end

  @impl true
  def handle_event("show_diff", %{"version" => version_str}, socket) do
    version_number = String.to_integer(version_str)
    old_version = Apis.get_version(socket.assigns.api, version_number)

    {:noreply,
     socket
     |> assign(:show_diff, true)
     |> assign(:diff_original, old_version.code)
     |> assign(:diff_modified, socket.assigns.code)}
  end

  @impl true
  def handle_event("rollback", %{"version" => version_str}, socket) do
    version_number = String.to_integer(version_str)

    case Apis.rollback_api(socket.assigns.api, version_number) do
      {:ok, new_version} ->
        {:noreply,
         socket
         |> assign(:current_version, new_version)
         |> assign(:code, new_version.code)
         |> put_flash(:info, "Rolled back to version #{version_number}")}

      {:error, :version_not_found} ->
        {:noreply, put_flash(socket, :error, "Version not found")}
    end
  end
end
```

### 8.5 Technology Choices Summary

| Concern | Choice | Rationale |
|---|---|---|
| Code editor | Monaco via `live_monaco_editor` | Built-in diff, VS Code quality, existing LiveView package |
| Diff engine | Built-in `List.myers_difference/2` | No dependency, sufficient for line-level code diffs |
| Diff display | Monaco `createDiffEditor` | Syntax-highlighted, side-by-side + inline modes |
| Versioning | Custom `api_versions` table | Purpose-built for code artifacts with metadata |
| Hot reload | `Code.compile_string/1` + `:code.soft_purge/1` | BEAM-native, zero-downtime |
| Sandbox (MVP) | Template-based restriction | Generated code fills predefined slots |
| Sandbox (later) | Separate BEAM nodes / containers | Real isolation for multi-tenant |
| Migrations | Auto-generated from schema diff | Per-API PostgreSQL schemas for isolation |
| Collaboration (MVP) | Lock-based via Presence | Simple, sufficient for API editing |
| Collaboration (later) | Yjs CRDT + Phoenix Channels | Full concurrent editing |
| Conversation storage | `api_conversations` table with JSON messages | Simple, queryable, sufficient |

### 8.6 Implementation Priority

1. **Sprint 1**: Monaco editor integration with `live_monaco_editor`, basic save/load
2. **Sprint 2**: Version table, version history UI, rollback
3. **Sprint 3**: Chat panel, LLM integration for iterative editing
4. **Sprint 4**: Diff visualization (Monaco diff editor)
5. **Sprint 5**: Hot code reload, publish workflow
6. **Sprint 6**: Schema migration detection and execution
7. **Future**: Collaborative editing, container isolation, highlight-to-edit

### 8.7 Key Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Malicious generated code | VM compromise | Template-based code generation (Phase 1), isolated nodes (Phase 2) |
| Large Monaco bundle | Slow page load | Lazy-load Monaco only on editor page, use CDN |
| LLM produces invalid code | Bad UX | Always compile-check before saving; show errors inline |
| Migration data loss | User data destroyed | Require confirmation for destructive migrations; snapshot before migrate |
| Editor state desync | Lost edits | Explicit save model (not auto-save); local storage backup via JS |
| Atom table exhaustion | VM crash | Use deterministic module names; purge unused modules; monitor atom count |

---

## Sources

- [live_monaco_editor - GitHub (BeaconCMS)](https://github.com/BeaconCMS/live_monaco_editor)
- [LiveMonacoEditor - HexDocs](https://hexdocs.pm/live_monaco_editor/LiveMonacoEditor.html)
- [How to use Monaco editor with Phoenix LiveView and esbuild](https://szajbus.dev/elixir/2023/05/15/how-to-use-monaco-editor-with-phoenix-live-view-and-esbuild.html)
- [Phoenix LiveView JS Interop - HexDocs](https://hexdocs.pm/phoenix_live_view/js-interop.html)
- [LiveMonacoEditor - Elixir Forum](https://elixirforum.com/t/livemonacoeditor-monaco-editor-component-for-phoenix-liveview/56212)
- [PaperTrail - GitHub](https://github.com/izelnakri/paper_trail)
- [PaperTrail - HexDocs](https://hexdocs.pm/paper_trail/readme.html)
- [Version history with PaperTrail and Ecto in LiveView - FullstackPhoenix](https://fullstackphoenix.com/videos/version-history-with-papertrail-ecto-liveview)
- [ex_audit - GitHub](https://github.com/ZennerIoT/ex_audit)
- [Diff library for Elixir - GitHub](https://github.com/bryanjos/diff)
- [Diffie - GitHub](https://github.com/davearonson/Diffie)
- [Exdiff - GitHub](https://github.com/jung-hunsoo/exdiff)
- [String.myers_difference - Elixir Docs](https://hexdocs.pm/elixir/String.html)
- [Monaco Diff Editor API](https://microsoft.github.io/monaco-editor/typedoc/interfaces/editor.IDiffEditorBaseOptions.html)
- [A Guide to Hot Code Reloading in Elixir - AppSignal](https://blog.appsignal.com/2021/07/27/a-guide-to-hot-code-reloading-in-elixir.html)
- [Understanding Elixir OTP - Hot-Swapping Modules](https://oozou.com/blog/understanding-elixir-otp-applications-part-4-hot-swapping-modules-151)
- [Elixir Hot Code Swapping to the Rescue](https://www.chriis.dev/opinion/elixir-hot-code-swapping-to-the-rescue)
- [Dune Sandbox for Elixir - GitHub](https://github.com/functional-rewire/dune)
- [Dune - HexDocs](https://hexdocs.pm/dune/Dune.html)
- [Compiling and loading modules dynamically - Elixir Forum](https://elixirforum.com/t/compiling-and-loading-modules-dynamically/32170)
- [Safe Ecto Migrations - Fly.io](https://fly.io/phoenix-files/safe-ecto-migrations/)
- [Ecto.Migration - HexDocs](https://hexdocs.pm/ecto_sql/Ecto.Migration.html)
- [How to Handle Database Migrations with Ecto](https://oneuptime.com/blog/post/2026-02-02-elixir-ecto-migrations/view)
- [Collaborative Real-Time Interfaces in Phoenix LiveView with CRDTs - DEV](https://dev.to/hexshift/how-to-build-collaborative-real-time-interfaces-in-phoenix-liveview-with-crdts-2iop)
- [Building a Real-Time Collaborative Editing Application with Phoenix LiveView](https://www.omgelixir.com/2024/05/building-real-time-collaborative.html)
- [Alchemy Book - Collaborative Editor in Elixir - GitHub](https://github.com/rudi-c/alchemy-book)
- [Livebook - GitHub](https://github.com/livebook-dev/livebook)
- [ChatGPT Canvas vs Claude Artifacts Comparison](https://xsoneconsultants.com/blog/chatgpt-canvas-vs-claude-artifacts/)
- [Next Gen Human-AI Collaboration: Artifacts, Canvas, Spaces](https://altar.io/next-gen-of-human-ai-collaboration/)
- [Code module - Elixir Docs](https://hexdocs.pm/elixir/Code.html)
