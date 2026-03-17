# 03 - Dynamic API Creation from LLM-Generated Code

Research date: 2026-03-17

---

## Table of Contents

1. [Overview](#1-overview)
2. [Dynamic Code Generation in Elixir](#2-dynamic-code-generation-in-elixir)
3. [AST Analysis and Code Validation](#3-ast-analysis-and-code-validation)
4. [Sandboxing and Security](#4-sandboxing-and-security)
5. [LLM Code Generation Pipeline](#5-llm-code-generation-pipeline)
6. [Template and Scaffold System](#6-template-and-scaffold-system)
7. [Dynamic Routing in Phoenix](#7-dynamic-routing-in-phoenix)
8. [Database Schema Generation](#8-database-schema-generation)
9. [Architecture Recommendation](#9-architecture-recommendation)
10. [Risk Matrix](#10-risk-matrix)
11. [Open Questions](#11-open-questions)

---

## 1. Overview

BlackBoex's core proposition: users describe an API in natural language, an LLM generates
Elixir code, and users publish it as a live REST endpoint. This document covers the full
technical pipeline from natural language input to deployed endpoint, with emphasis on
security.

The pipeline has five stages:

```
Natural Language -> LLM Prompt -> Generated Code -> Validation -> Compilation -> Deployment
     (user)        (template)      (raw Elixir)     (AST + sandbox)  (Module.create)  (dynamic route)
```

---

## 2. Dynamic Code Generation in Elixir

### 2.1 Core Primitives

The BEAM provides several mechanisms for runtime code manipulation:

#### `Code.string_to_quoted/2` - Parse without executing

Converts source code string to AST (Abstract Syntax Tree) without execution. This is the
**safest entry point** for handling LLM-generated code because nothing runs.

```elixir
{:ok, ast} = Code.string_to_quoted("""
  defmodule MyAPI do
    def handle(%{name: name}), do: %{greeting: "Hello, \#{name}"}
  end
""")
# Returns the AST tree, no code is executed
```

Key options:
- `:static_atoms_encoder` - intercept atom creation (critical for preventing atom table exhaustion)
- `:token_metadata` - include position info for error reporting
- `:emit_warnings` - control compiler warnings

#### `Code.compile_string/2` - Compile to bytecode

Compiles Elixir source string into loaded modules. Returns `[{module_name, bytecode}]`.

**Security warning from official docs:** "string can be any Elixir code and code can be
executed with the same privileges as the Erlang VM: this means that such code could
compromise the machine. Don't use compile_string/2 with untrusted input."

This means we must **never** call `Code.compile_string/2` on raw LLM output. Validation
must happen first.

#### `Code.eval_string/3` - Evaluate directly

Evaluates code and returns `{value, binding}`. Same security warning applies. Avoid for
LLM-generated code; prefer compilation into named modules.

#### `Module.create/3` - Create from AST

Creates a module from a quoted expression (AST). This is the **preferred approach** because
we can validate the AST before creating the module.

```elixir
contents = quote do
  def handle(params) do
    %{message: "Hello from dynamic API"}
  end
end

{:module, mod, bytecode, _} =
  Module.create(BlackBoex.UserAPIs.Api_abc123, contents, Macro.Env.location(__ENV__))
```

#### Erlang `:code` module - Low-level loading

For advanced scenarios:
- `:code.load_binary/3` - Load pre-compiled BEAM bytecode
- `:code.purge/1` - Remove old module version
- `:code.delete/1` - Mark current code as old
- `:code.soft_purge/1` - Remove old code only if no processes reference it

The BEAM supports two simultaneous versions of a module ("current" and "old"), enabling
hot code reloading. When a third version loads, the old version is purged and processes
still running it are terminated.

### 2.2 Module Lifecycle Management

Dynamic modules need lifecycle management:

```elixir
defmodule BlackBoex.ModuleManager do
  @spec load_module(atom(), binary()) :: {:ok, atom()} | {:error, term()}
  def load_module(module_name, source_code) do
    # 1. Parse to AST (safe - no execution)
    with {:ok, ast} <- Code.string_to_quoted(source_code),
         # 2. Validate AST (our custom validation)
         :ok <- BlackBoex.CodeValidator.validate(ast),
         # 3. Wrap in sandboxed module template
         wrapped_ast <- wrap_in_template(module_name, ast),
         # 4. Compile and load
         {:module, ^module_name, _bytecode, _} <-
           Module.create(module_name, wrapped_ast, Macro.Env.location(__ENV__)) do
      {:ok, module_name}
    end
  end

  @spec unload_module(atom()) :: :ok
  def unload_module(module_name) do
    :code.purge(module_name)
    :code.delete(module_name)
    :ok
  end
end
```

### 2.3 Atom Table Considerations

The BEAM atom table has a fixed limit (default 1,048,576 atoms). Dynamic modules create
atoms for:
- Module names
- Function names
- Map keys (if atoms)

Mitigations:
- Use deterministic module naming: `BlackBoex.UserAPIs.Api_<uuid>`
- Reuse module names when users update their APIs (purge + reload)
- Use `Code.string_to_quoted/2` with `:static_atoms_encoder` to intercept and limit atom creation
- Monitor atom table usage via `:erlang.system_info(:atom_count)`

---

## 3. AST Analysis and Code Validation

This is the first line of defense. Before any code executes, we analyze the AST to reject
dangerous patterns.

### 3.1 Elixir AST Structure

Every Elixir expression is represented as a three-element tuple:

```elixir
{:function_name, metadata_keyword_list, [arguments]}
```

Literals (atoms, integers, floats, strings, lists, two-element tuples) represent themselves.
Everything else is nested tuples.

Example - `IO.puts("hello")` becomes:

```elixir
{{:., [], [{:__aliases__, [alias: false], [:IO]}, :puts]}, [], ["hello"]}
```

### 3.2 AST Traversal Tools

Elixir's `Macro` module provides traversal functions:

- `Macro.prewalk/2` - depth-first, pre-order (parent before children)
- `Macro.postwalk/2` - depth-first, post-order (children before parent)
- `Macro.traverse/4` - separate pre and post callbacks with accumulator
- `Macro.prewalker/1` - lazy enumerable for early termination
- `Macro.path/2` - find the path to a node matching a predicate
- `Macro.validate/1` - check if AST is structurally valid
- `Macro.decompose_call/1` - break function calls into `{module, function, args}`

### 3.3 Building an AST Allowlist Validator

The approach: walk the AST and check every function call against an allowlist. Reject code
that calls anything not explicitly permitted.

```elixir
defmodule BlackBoex.CodeValidator do
  @moduledoc "Validates LLM-generated code AST against an allowlist."

  # Modules the generated code is allowed to call
  @allowed_modules %{
    Enum => :all,
    Map => :all,
    List => :all,
    String => :all,
    Integer => :all,
    Float => :all,
    Kernel => [
      :+, :-, :*, :/, :==, :!=, :>, :<, :>=, :<=,
      :&&, :||, :!, :not, :and, :or,
      :div, :rem, :abs, :max, :min,
      :is_nil, :is_binary, :is_integer, :is_float, :is_boolean, :is_list, :is_map,
      :to_string, :inspect, :length, :hd, :tl,
      :if, :unless, :case, :cond
    ],
    Jason => [:encode!, :decode!],
    Date => :all,
    Time => :all,
    DateTime => :all,
    NaiveDateTime => :all,
    Regex => [:match?, :run, :scan, :replace, :split]
  }

  # Explicitly banned constructs (even if they appear as local calls)
  @banned_atoms [
    :spawn, :spawn_link, :spawn_monitor,
    :send, :receive,
    :apply, :__ENV__, :__DIR__, :__CALLER__,
    :import, :require, :use, :alias,
    :defmacro, :defmacrop, :defprotocol, :defimpl,
    :open, :read, :write, :cmd, :eval_string, :compile_string
  ]

  @spec validate(Macro.t()) :: :ok | {:error, String.t()}
  def validate(ast) do
    case Macro.prewalk(ast, [], &check_node/2) do
      {_ast, []} -> :ok
      {_ast, violations} -> {:error, format_violations(violations)}
    end
  end

  # Remote function call: Module.function(args)
  defp check_node({{:., _, [{:__aliases__, _, module_parts}, func]}, _, _args} = node, acc) do
    module = Module.concat(module_parts)
    case Map.get(@allowed_modules, module) do
      :all -> {node, acc}
      allowed when is_list(allowed) ->
        if func in allowed, do: {node, acc}, else: {node, ["#{module}.#{func} not allowed" | acc]}
      nil -> {node, ["Module #{module} not allowed" | acc]}
    end
  end

  # Local function call - check against banned list
  defp check_node({func, _, _args} = node, acc) when is_atom(func) do
    if func in @banned_atoms do
      {node, ["#{func} is banned" | acc]}
    else
      {node, acc}
    end
  end

  # Everything else passes
  defp check_node(node, acc), do: {node, acc}

  defp format_violations(violations) do
    "Code validation failed:\n" <> Enum.join(Enum.reverse(violations), "\n")
  end
end
```

### 3.4 Sourceror for Advanced AST Work

The **Sourceror** library (hex: `sourceror`) extends standard AST capabilities:
- Preserves comments and formatting in AST
- Provides Zipper-based navigation for surgical modifications
- Supports patch-based code modifications
- Useful for: injecting instrumentation, wrapping function bodies in try/catch,
  rewriting module references

### 3.5 Credo for Programmatic Analysis

Credo can be used programmatically to analyze code quality:

```elixir
# Parse source to Credo source file, run checks
source = Credo.SourceFile.parse(code_string, "generated.ex")
issues = Credo.Check.run(source, Credo.Check.Readability.ModuleDoc)
```

This adds a layer of quality checking on top of security validation.

---

## 4. Sandboxing and Security

**This is the most critical section.** Running LLM-generated code is inherently dangerous.
Defense in depth is mandatory.

### 4.1 Threat Model

| Threat | Impact | Likelihood |
|--------|--------|------------|
| System command execution (`System.cmd`, `:os.cmd`) | Critical - full system compromise | High if not blocked |
| File system access (`File.*`, `:file.*`) | Critical - data exfiltration/corruption | High if not blocked |
| Network access (`:gen_tcp`, `:httpc`, Req) | High - data exfiltration, SSRF | High if not blocked |
| Process spawning (DoS via process bomb) | High - system destabilization | Medium |
| Atom table exhaustion | High - VM crash | Medium |
| Memory exhaustion | High - VM crash/OOM | Medium |
| CPU exhaustion (infinite loops) | Medium - degraded service | High |
| Code injection via metaprogramming | Critical - sandbox escape | Medium |
| Message passing to system processes | High - state corruption | Low |
| NIF loading | Critical - arbitrary native code | Low if blocked |

### 4.2 Defense Layers

The architecture must implement **defense in depth** with multiple independent layers:

```
Layer 1: AST Validation (allowlist)
  |
Layer 2: Dune Sandbox (runtime restrictions)
  |
Layer 3: Process Isolation (separate process, resource limits)
  |
Layer 4: BEAM Node Isolation (separate Erlang node)
  |
Layer 5: OS-Level Isolation (container/microVM)
```

#### Layer 1: AST Validation (described in Section 3)

Walk the AST before compilation. Reject any code that references disallowed modules or
functions. This catches the obvious cases but is **not sufficient alone** because:
- Elixir metaprogramming can construct calls dynamically
- `apply/3` can invoke any function with runtime-determined arguments
- String-based code evaluation escapes AST analysis

#### Layer 2: Dune Sandbox

**Dune** (hex: `dune`, ~50k downloads) is the most mature Elixir sandbox library.

Features:
- Configurable allowlist of permitted modules/functions
- Atom leak prevention (replaces user atoms with `:atom1`, `:atom2`, etc.)
- Resource limits: timeout, reductions (CPU), memory
- I/O capture
- Module simulation via maps of anonymous functions (no actual module creation)
- Returns structured results: `%Dune.Success{}` or `%Dune.Failure{}`

```elixir
# Basic usage
Dune.eval_string("Enum.map([1,2,3], & &1 * 2)")
#=> %Dune.Success{value: [2, 4, 6], inspected: "[2, 4, 6]"}

Dune.eval_string("File.cwd!()")
#=> %Dune.Failure{type: :restricted, message: "function is restricted"}

Dune.eval_string("List.duplicate(:spam, 100_000)")
#=> %Dune.Failure{type: :memory, message: "Execution stopped - memory limit exceeded"}
```

Custom allowlist:

```elixir
defmodule BlackBoex.APIAllowlist do
  use Dune.Allowlist, extend: Dune.Allowlist.Default

  # Allow our safe domain functions
  allow BlackBoex.SafeHelpers, only: [:format_response, :validate_params]
  allow Jason, only: [:encode!, :decode!]
end
```

**Critical caveat from Dune's README:** "Dune cannot offer strong security guarantees."
It is best-effort. The author explicitly warns against deploying it on servers with
sensitive database access. Dune should be **one layer** in defense-in-depth, not the only
layer.

**Dune limitations:**
- No custom structs, behaviours, protocols
- No concurrency/OTP
- No advanced metaprogramming
- Cannot create real modules (uses map-based simulation)

For BlackBoex, Dune's limitation of not creating real modules is actually problematic because
we need actual modules to serve HTTP requests. This means we should use Dune for
**validation/testing** of generated code, but use our own controlled compilation for the
actual deployment.

#### Layer 3: Process Isolation

Execute user code in a separate process with resource constraints:

```elixir
defmodule BlackBoex.Executor do
  @spec execute_safely(function(), keyword()) :: {:ok, term()} | {:error, term()}
  def execute_safely(fun, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 5_000)
    max_heap = Keyword.get(opts, :max_heap_size, 10_000_000)  # ~80MB

    task = Task.Supervisor.async_nolink(BlackBoex.TaskSupervisor, fn ->
      # Set process-level resource limits
      Process.flag(:max_heap_size, %{size: max_heap, kill: true, error_logger: true})
      fun.()
    end)

    case Task.yield(task, timeout) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> {:ok, result}
      {:exit, reason} -> {:error, {:crashed, reason}}
      nil -> {:error, :timeout}
    end
  end
end
```

Key process-level protections:
- `:max_heap_size` - kills process if heap exceeds limit
- `Task.Supervisor.async_nolink/2` - parent survives child crash
- `Task.yield/2` + `Task.shutdown/2` - enforces timeout with kill

#### Layer 4: Separate BEAM Node

For stronger isolation, run user code on a separate Erlang node. This is the approach
Livebook uses - each runtime is a separate BEAM process connected via distributed Erlang.

```elixir
defmodule BlackBoex.IsolatedNode do
  @spec start_sandbox_node() :: {:ok, node()} | {:error, term()}
  def start_sandbox_node() do
    # Start a new BEAM node with restricted capabilities
    node_name = :"sandbox_#{:erlang.unique_integer([:positive])}@127.0.0.1"

    case :slave.start_link('127.0.0.1', node_name, '-setcookie #{Node.get_cookie()}') do
      {:ok, node} ->
        # Load only necessary modules on the sandbox node
        load_sandbox_modules(node)
        {:ok, node}
      error -> error
    end
  end

  @spec execute_on_node(node(), function()) :: {:ok, term()} | {:error, term()}
  def execute_on_node(node, fun) do
    try do
      result = :erpc.call(node, fun, 5_000)
      {:ok, result}
    catch
      :exit, reason -> {:error, reason}
    end
  end
end
```

Benefits: complete memory isolation, separate atom table, can be killed without affecting
the main application. Cost: higher latency, more resource overhead.

#### Layer 5: OS-Level Isolation

For production, consider running sandbox nodes inside containers or microVMs:

**Firecracker microVMs:**
- Sub-125ms boot time
- <5 MiB memory overhead per microVM
- KVM-based isolation with minimal attack surface (only 5 emulated devices)
- Used by AWS Lambda and Fargate
- A companion "jailer" program provides secondary defense
- Best option for true multi-tenant isolation

**Docker containers:**
- More common, easier to set up
- Linux namespaces + cgroups for isolation
- Can restrict: network, filesystem, syscalls (seccomp), capabilities
- Higher overhead than Firecracker but simpler operationally

**Recommended approach for BlackBoex:**
- Development/MVP: Layer 1 (AST) + Layer 2 (Dune for testing) + Layer 3 (Process isolation)
- Production v1: Add Layer 4 (separate BEAM node per execution)
- Production v2: Add Layer 5 (Firecracker microVM per tenant)

### 4.3 Safeish - Bytecode-Level Validation

**Safeish** (hex: `safeish`) takes a different approach: it examines compiled BEAM bytecode
to detect dangerous operations. NOT FOR PRODUCTION USE (experimental), but the concept is
valuable.

It blocks: process spawning, message passing, file/network access, compilation, dynamic
atom creation, unrestricted `apply`.

Could be used as an additional validation layer after compilation:

```elixir
# After compiling to bytecode, before loading
case Safeish.check(bytecode, whitelist: [Enum, Map, String]) do
  :ok -> :code.load_binary(module_name, 'generated.beam', bytecode)
  {:error, risks} -> {:error, "Bytecode contains unsafe operations: #{inspect(risks)}"}
end
```

### 4.4 Other Sandbox Libraries

| Library | Approach | Maturity | Notes |
|---------|----------|----------|-------|
| **dune** | AST rewriting + allowlist | Best available | Cannot create real modules |
| **safeish** | Bytecode analysis | Experimental | Validates after compilation |
| **sandbox** (Lua) | Runs code in Lua VM | Stable | Different language, limited interop |
| **alcove** | Unix process containers | Mature (210k downloads) | OS-level isolation from Elixir |
| **prx** | Unix process sandboxing | Stable | Lower level than alcove |
| **quicksand** | QuickJS JavaScript sandbox | Very new | JS execution, not Elixir |

---

## 5. LLM Code Generation Pipeline

### 5.1 Pipeline Architecture

```
                                   +------------------+
                                   |   User Input     |
                                   | (natural language)|
                                   +--------+---------+
                                            |
                                   +--------v---------+
                                   | Prompt Builder   |
                                   | (template + NL)  |
                                   +--------+---------+
                                            |
                                   +--------v---------+
                                   |  LLM Provider    |
                                   | (Anthropic/OpenAI)|
                                   +--------+---------+
                                            |
                                   +--------v---------+
                                   | Response Parser  |
                                   | (extract code)   |
                                   +--------+---------+
                                            |
                              +-------------v--------------+
                              |      Validation Pipeline    |
                              |  1. Syntax check            |
                              |  2. AST allowlist           |
                              |  3. Dune sandbox test       |
                              |  4. Type/spec check         |
                              +-------------+--------------+
                                            |
                              +-------------v--------------+
                              |    Module Compilation       |
                              |  1. Wrap in template        |
                              |  2. Module.create/3         |
                              |  3. Bytecode validation     |
                              +-------------+--------------+
                                            |
                              +-------------v--------------+
                              |    Route Registration       |
                              |  1. Store in DB             |
                              |  2. Register in dispatcher  |
                              |  3. Health check            |
                              +-------------+--------------+
                                            |
                              +-------------v--------------+
                              |    Live Endpoint            |
                              |  /api/v1/<user>/<api-slug>  |
                              +----------------------------+
```

### 5.2 Structured LLM Output with Instructor

Use the **Instructor** library to get structured, validated LLM responses:

```elixir
defmodule BlackBoex.CodeGen.GeneratedAPI do
  use Ecto.Schema

  @llm_doc """
  The generated Elixir code for a REST API endpoint.
  The handler_code must be a valid Elixir function body that:
  - Accepts a single `params` map argument
  - Returns a map that will be JSON-encoded as the response
  - Only uses allowed modules: Enum, Map, List, String, Integer, Float, Date, DateTime
  - Does NOT use: File, System, Process, Port, :os, Code, IO, Node
  - Does NOT use: spawn, send, receive, apply, import, require, use
  """

  embedded_schema do
    field :handler_code, :string
    field :description, :string
    field :method, :string  # GET, POST, PUT, DELETE
    field :example_request, :map
    field :example_response, :map
    field :param_schema, :map  # JSON Schema for input validation
  end

  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_required([:handler_code, :method, :description])
    |> Ecto.Changeset.validate_inclusion(:method, ["GET", "POST", "PUT", "PATCH", "DELETE"])
    |> validate_code_parses()
  end

  defp validate_code_parses(changeset) do
    case Ecto.Changeset.get_field(changeset, :handler_code) do
      nil -> changeset
      code ->
        case Code.string_to_quoted(code) do
          {:ok, _ast} -> changeset
          {:error, _} ->
            Ecto.Changeset.add_error(changeset, :handler_code, "is not valid Elixir syntax")
        end
    end
  end
end
```

### 5.3 LLM Provider Integration

Elixir packages for LLM access (sorted by maturity):

| Package | Provider | Downloads | Notes |
|---------|----------|-----------|-------|
| `openai` | OpenAI | 692k | Most popular, community maintained |
| `anthropix` | Anthropic | 175k | Unofficial Claude client |
| `openai_ex` | OpenAI | 301k | Full typespec coverage |
| `instructor` | Multi | 148k | Structured output, validation+retry |
| `anthropic_community` | Anthropic | 48k | Unofficial wrapper |
| `elixir_llm` | Multi | New | Unified interface for all providers |

**Recommendation:** Use `instructor` for code generation (structured output with retry on
validation failure) combined with a direct client (`anthropix` or `openai_ex`) for the
underlying API calls.

### 5.4 The Prompt Engineering Layer

The prompt is critical. It must produce code that:
1. Fits our template (single function, specific signature)
2. Only uses allowed modules
3. Handles edge cases
4. Returns a consistent response format

```elixir
defmodule BlackBoex.CodeGen.Prompter do
  @system_prompt """
  You are an Elixir code generator for REST API endpoints.

  RULES:
  1. Generate ONLY the function body. Do not generate defmodule or def.
  2. The function receives a single argument `params` which is a map with string keys.
  3. The function must return a map that will be JSON-encoded.
  4. You may ONLY use these modules: Enum, Map, List, String, Integer, Float,
     Kernel, Date, Time, DateTime, NaiveDateTime, Regex, Jason, Tuple.
  5. You MUST NOT use: File, System, Process, Port, Node, Code, IO, :os, :file,
     :gen_tcp, :httpc, :net, spawn, send, receive, apply, import, require, use,
     defmacro, defprotocol.
  6. For data persistence, use the provided `store` module:
     - store.get(key) -> value or nil
     - store.put(key, value) -> :ok
     - store.delete(key) -> :ok
     - store.list() -> [key]
  7. Handle missing/invalid params gracefully with descriptive error maps.
  8. Keep the code simple and readable.

  RESPONSE FORMAT:
  Return a JSON object with these fields:
  - handler_code: the Elixir function body as a string
  - method: HTTP method (GET, POST, PUT, PATCH, DELETE)
  - description: what the API does
  - example_request: example request params
  - example_response: example response body
  - param_schema: JSON Schema describing expected parameters
  """

  @spec build_prompt(String.t()) :: [map()]
  def build_prompt(user_description) do
    [
      %{role: "system", content: @system_prompt},
      %{role: "user", content: "Create an API endpoint that: #{user_description}"}
    ]
  end
end
```

### 5.5 Retry and Iterative Refinement

When generated code fails validation:

```elixir
defmodule BlackBoex.CodeGen.Pipeline do
  @max_retries 3

  @spec generate(String.t()) :: {:ok, map()} | {:error, String.t()}
  def generate(user_description) do
    messages = BlackBoex.CodeGen.Prompter.build_prompt(user_description)
    generate_with_retries(messages, @max_retries)
  end

  defp generate_with_retries(_messages, 0), do: {:error, "Failed after max retries"}

  defp generate_with_retries(messages, retries_left) do
    with {:ok, response} <- call_llm(messages),
         {:ok, parsed} <- parse_response(response),
         {:ok, ast} <- Code.string_to_quoted(parsed.handler_code),
         :ok <- BlackBoex.CodeValidator.validate(ast),
         :ok <- sandbox_test(parsed) do
      {:ok, parsed}
    else
      {:error, reason} ->
        # Feed the error back to the LLM for correction
        correction = %{
          role: "user",
          content: "The generated code failed validation: #{reason}\nPlease fix it."
        }
        generate_with_retries(messages ++ [correction], retries_left - 1)
    end
  end

  defp sandbox_test(parsed) do
    # Test the code in Dune sandbox with example params
    test_code = """
    params = #{inspect(parsed.example_request)}
    #{parsed.handler_code}
    """
    case Dune.eval_string(test_code) do
      %Dune.Success{} -> :ok
      %Dune.Failure{message: msg} -> {:error, "Sandbox test failed: #{msg}"}
    end
  end
end
```

---

## 6. Template and Scaffold System

### 6.1 Module Template

LLM-generated code must be wrapped in a controlled template. The LLM generates **only the
handler function body**; we wrap it in the module structure.

```elixir
defmodule BlackBoex.CodeGen.Template do
  @spec wrap(atom(), String.t(), String.t(), map()) :: {:ok, Macro.t()} | {:error, term()}
  def wrap(module_name, handler_code, method, opts \\ %{}) do
    with {:ok, handler_ast} <- Code.string_to_quoted(handler_code) do
      ast = quote do
        @moduledoc unquote(Map.get(opts, :description, "Generated API endpoint"))

        # The store provides simple key-value persistence scoped to this API
        @store_module unquote(Map.get(opts, :store_module, BlackBoex.NullStore))

        @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
        def call(conn, _opts) do
          if conn.method == unquote(String.upcase(method)) do
            params = conn.params
            store = @store_module

            try do
              result = unquote(handler_ast)
              conn
              |> Plug.Conn.put_resp_content_type("application/json")
              |> Plug.Conn.send_resp(200, Jason.encode!(result))
            rescue
              e ->
                conn
                |> Plug.Conn.put_resp_content_type("application/json")
                |> Plug.Conn.send_resp(500, Jason.encode!(%{error: Exception.message(e)}))
            end
          else
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(405, Jason.encode!(%{error: "Method not allowed"}))
          end
        end

        @spec init(keyword()) :: keyword()
        def init(opts), do: opts
      end

      {:ok, ast}
    end
  end
end
```

### 6.2 Template Variations

Different templates for different API patterns:

**CRUD Template** - When the LLM detects the user wants data storage:
- Generates index/show/create/update/delete handlers
- Includes schemaless changeset validation
- Wires up the key-value store

**Computation Template** - Pure functions, no state:
- Simpler template, just input -> output
- No store dependency
- Easiest to sandbox

**Webhook Template** - Receives data, transforms, returns:
- Input validation emphasis
- Structured error responses
- Idempotency support

### 6.3 EEx for Template Generation

For more complex templates, use EEx:

```elixir
# Template file: priv/templates/api_module.ex.eex
defmodule <%= @module_name %> do
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    params = conn.params
    <%= for {method, handler} <- @handlers do %>
    if conn.method == "<%= String.upcase(method) %>" do
      result = (fn params ->
        <%= handler %>
      end).(params)
      # ... send response
    end
    <% end %>
  end
end
```

---

## 7. Dynamic Routing in Phoenix

### 7.1 The Problem

Phoenix compiles routes into optimized pattern-matching at compile time. There is **no
native mechanism** to add routes at runtime. From Phoenix docs: "Phoenix compiles all of
your routes to a single case-statement with pattern matching rules."

### 7.2 Solution: Catch-All Route + Dynamic Dispatcher

The recommended approach is a **catch-all route** that forwards to a dynamic dispatcher
Plug:

```elixir
# In router.ex
scope "/api/v1", BlackBoexWeb do
  pipe_through :api

  # Static routes for platform APIs
  resources "/users", UserController

  # Catch-all for dynamic user APIs
  forward "/run", DynamicAPIPlug
end
```

The dispatcher looks up the target module at runtime:

```elixir
defmodule BlackBoexWeb.DynamicAPIPlug do
  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: path_info} = conn, _opts) do
    case path_info do
      [user_slug, api_slug | rest] ->
        dispatch(conn, user_slug, api_slug, rest)
      _ ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "Not found"}))
    end
  end

  defp dispatch(conn, user_slug, api_slug, remaining_path) do
    case BlackBoex.APIRegistry.lookup(user_slug, api_slug) do
      {:ok, module_name} ->
        conn = %{conn | path_info: remaining_path}
        module_name.call(conn, [])

      {:error, :not_found} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(404, Jason.encode!(%{error: "API not found"}))

      {:error, :disabled} ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(503, Jason.encode!(%{error: "API is currently disabled"}))
    end
  end
end
```

### 7.3 API Registry

An ETS-backed registry for fast O(1) lookups:

```elixir
defmodule BlackBoex.APIRegistry do
  use GenServer

  @table :api_registry

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec register(String.t(), String.t(), atom()) :: :ok
  def register(user_slug, api_slug, module_name) do
    :ets.insert(@table, {{user_slug, api_slug}, module_name, :active})
    :ok
  end

  @spec unregister(String.t(), String.t()) :: :ok
  def unregister(user_slug, api_slug) do
    :ets.delete(@table, {user_slug, api_slug})
    :ok
  end

  @spec lookup(String.t(), String.t()) :: {:ok, atom()} | {:error, :not_found | :disabled}
  def lookup(user_slug, api_slug) do
    case :ets.lookup(@table, {user_slug, api_slug}) do
      [{{^user_slug, ^api_slug}, module_name, :active}] -> {:ok, module_name}
      [{{^user_slug, ^api_slug}, _module_name, :disabled}] -> {:error, :disabled}
      [] -> {:error, :not_found}
    end
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    # Load all active APIs from database on startup
    load_from_database()
    {:ok, %{table: table}}
  end

  defp load_from_database do
    # Query all active APIs and register them
    # Also recompile their modules from stored source
  end
end
```

### 7.4 URL Structure

```
/api/v1/run/{user_slug}/{api_slug}
```

Examples:
- `POST /api/v1/run/rodrigo/greeting-api`
- `GET  /api/v1/run/rodrigo/fibonacci?n=10`
- `POST /api/v1/run/acme/invoice-calculator`

### 7.5 Plug.Router as Alternative

For more complex per-API routing (sub-resources), each generated API could be a
`Plug.Router`:

```elixir
# Generated module could use Plug.Router for multi-route APIs
defmodule BlackBoex.UserAPIs.Api_abc123 do
  use Plug.Router

  plug :match
  plug :dispatch

  get "/" do
    send_resp(conn, 200, Jason.encode!(%{items: store.list()}))
  end

  post "/" do
    # create item
  end

  get "/:id" do
    # get item by id
  end
end
```

However, this adds complexity. For the MVP, a single handler function per API is simpler
and safer.

---

## 8. Database Schema Generation

### 8.1 The Challenge

Some APIs need persistent storage. Options:

1. **Key-value store** - Simplest, no schema needed
2. **JSON column** - Single table, flexible structure
3. **Dynamic tables** - Full relational, complex

### 8.2 Recommended: JSON Storage with Schemaless Ecto

For the MVP, avoid dynamic table creation. Use a single `api_data` table:

```elixir
# Migration
create table(:api_data) do
  add :api_id, references(:apis, on_delete: :delete_all), null: false
  add :key, :string, null: false
  add :value, :jsonb, null: false
  timestamps()
end

create unique_index(:api_data, [:api_id, :key])
```

The store module exposed to generated code:

```elixir
defmodule BlackBoex.APIStore do
  @moduledoc "Scoped key-value store for dynamic APIs."

  @spec get(Ecto.UUID.t(), String.t()) :: term() | nil
  def get(api_id, key) do
    case Repo.get_by(APIData, api_id: api_id, key: key) do
      nil -> nil
      record -> record.value
    end
  end

  @spec put(Ecto.UUID.t(), String.t(), term()) :: :ok
  def put(api_id, key, value) do
    %APIData{}
    |> Ecto.Changeset.change(%{api_id: api_id, key: key, value: value})
    |> Repo.insert(
      on_conflict: [set: [value: value, updated_at: DateTime.utc_now()]],
      conflict_target: [:api_id, :key]
    )
    |> case do
      {:ok, _} -> :ok
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec delete(Ecto.UUID.t(), String.t()) :: :ok
  def delete(api_id, key) do
    from(d in APIData, where: d.api_id == ^api_id and d.key == ^key)
    |> Repo.delete_all()
    :ok
  end

  @spec list(Ecto.UUID.t()) :: [String.t()]
  def list(api_id) do
    from(d in APIData, where: d.api_id == ^api_id, select: d.key)
    |> Repo.all()
  end
end
```

### 8.3 Schemaless Changesets for Dynamic Validation

When an API defines a param schema, validate incoming data without a compiled schema module:

```elixir
defmodule BlackBoex.DynamicValidator do
  @spec validate(map(), map()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def validate(params, schema_definition) do
    # schema_definition: %{"name" => :string, "age" => :integer, "email" => :string}
    types = Map.new(schema_definition, fn {k, v} -> {String.to_existing_atom(k), v} end)
    data = %{}

    {data, types}
    |> Ecto.Changeset.cast(params, Map.keys(types))
    |> Ecto.Changeset.validate_required(Map.keys(types))
    |> case do
      %{valid?: true} = changeset -> {:ok, Ecto.Changeset.apply_changes(changeset)}
      changeset -> {:error, changeset}
    end
  end
end
```

### 8.4 Multi-Tenant Isolation with Prefixes

For production scale, use PostgreSQL schema prefixes for tenant isolation:

```elixir
# Each user gets their own PostgreSQL schema
Repo.query("CREATE SCHEMA IF NOT EXISTS user_#{user_id}")

# Queries scoped to user
from(d in APIData, prefix: "user_#{user_id}")
|> Repo.all()
```

Migrations can run per-prefix:

```elixir
Ecto.Migrator.run(Repo, [{version, MigrationModule}], :up,
  all: true,
  prefix: "user_#{user_id}"
)
```

### 8.5 Future: Dynamic Table Creation

If a user's API truly needs relational data, we could dynamically create tables:

```elixir
defmodule BlackBoex.DynamicMigration do
  use Ecto.Migration

  def up(table_name, columns, prefix) do
    create table(table_name, prefix: prefix) do
      for {name, type} <- columns do
        add name, type
      end
      timestamps()
    end
  end
end

# Run programmatically
Ecto.Migrator.up(Repo, version, BlackBoex.DynamicMigration, prefix: "user_#{user_id}")
```

This is complex and should be deferred to a later phase.

---

## 9. Architecture Recommendation

### 9.1 MVP Architecture

```
                     +-------------------+
                     |   Phoenix App     |
                     |                   |
                     |  +-------------+  |
  HTTP request ----->|  | Router      |  |
                     |  |  /api/v1/*  |  |
                     |  +------+------+  |
                     |         |         |
                     |  +------v------+  |
                     |  | Dynamic     |  |
                     |  | Dispatcher  |  |
                     |  +------+------+  |
                     |         |         |
                     |  +------v------+  |        +------------------+
                     |  | API Registry|  |<------>| PostgreSQL       |
                     |  | (ETS)       |  |        | - apis table     |
                     |  +------+------+  |        | - api_data table |
                     |         |         |        | - users table    |
                     |  +------v------+  |        +------------------+
                     |  | Generated   |  |
                     |  | Module      |  |
                     |  | (in-process)|  |
                     |  +-------------+  |
                     +-------------------+
```

### 9.2 Domain Model

```elixir
# In blackboex (domain app)
defmodule BlackBoex.APIs.API do
  use Ecto.Schema

  schema "apis" do
    field :slug, :string
    field :name, :string
    field :description, :string
    field :method, :string
    field :source_code, :string          # LLM-generated handler code
    field :module_name, :string          # e.g. "Elixir.BlackBoex.UserAPIs.Api_abc123"
    field :status, Ecto.Enum, values: [:draft, :active, :disabled, :error]
    field :version, :integer, default: 1
    field :param_schema, :map            # JSON Schema for input validation
    field :example_request, :map
    field :example_response, :map
    field :llm_prompt, :string           # Original user description
    field :error_message, :string        # Last compilation/validation error

    belongs_to :user, BlackBoex.Accounts.User
    timestamps()
  end
end
```

### 9.3 Full Pipeline Flow

1. **User describes API** in natural language via LiveView form
2. **Prompt builder** constructs system + user prompt from template
3. **LLM call** via Instructor produces structured response with handler code
4. **Syntax validation** - `Code.string_to_quoted/2` confirms valid Elixir
5. **AST validation** - Walk AST to check allowlist (Section 3.3)
6. **Sandbox test** - Run handler with example params in Dune (Section 4.2)
7. **Store in database** - Save source code, metadata, status=draft
8. **User reviews** generated code and example output in LiveView
9. **User publishes** - triggers compilation
10. **Compilation** - Wrap in template (Section 6.1), `Module.create/3`
11. **Registration** - Add to ETS registry (Section 7.3)
12. **Live** - API is accessible at `/api/v1/run/{user}/{slug}`

### 9.4 Process Supervision Tree

```
BlackBoex.Application
  |
  +-- BlackBoex.Repo
  +-- BlackBoex.TaskSupervisor           (for sandboxed execution)
  +-- BlackBoex.APIRegistry              (ETS-backed registry)
  +-- BlackBoex.ModuleManager            (compiles/loads/unloads modules)
  +-- BlackBoex.CodeGen.Pipeline         (LLM interaction)
  +-- BlackBoexWeb.Endpoint              (Phoenix)
```

### 9.5 Key Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| LLM generates only handler body | Yes | Reduces attack surface, easier to validate |
| Module per API | Yes | Clean lifecycle, easy to purge/reload |
| ETS for route lookup | Yes | O(1) reads, concurrent access |
| JSON storage (not dynamic tables) | MVP | Simpler, safer, sufficient for most cases |
| Dune for sandbox testing | Yes | Best available Elixir sandbox |
| Process isolation for execution | Yes | Memory/CPU limits per request |
| Separate BEAM node | Later | Production hardening |
| Firecracker | Later | Multi-tenant production |

---

## 10. Risk Matrix

| Risk | Severity | Mitigation | Phase |
|------|----------|------------|-------|
| LLM generates malicious code | Critical | AST validation + Dune sandbox + process isolation | MVP |
| Sandbox escape | Critical | Defense in depth, separate node in production | v1 |
| Atom table exhaustion | High | Deterministic naming, monitoring, limits | MVP |
| Memory exhaustion | High | Process max_heap_size flag | MVP |
| CPU exhaustion | High | Task timeout + reduction counting | MVP |
| Module leak (never purged) | Medium | Lifecycle management, periodic cleanup | MVP |
| LLM generates bad/buggy code | Medium | Sandbox testing, user review, retry pipeline | MVP |
| Database abuse via store | Medium | Rate limiting, storage quotas per API | MVP |
| Atom creation via user input | Medium | static_atoms_encoder in parsing | MVP |
| Hot code reload race conditions | Low | Serial module loading via GenServer | MVP |

---

## 11. Open Questions

1. **Module naming strategy** - UUID-based (`Api_abc123`) vs sequential vs content-hash?
   Content-hash enables deduplication but complicates updates.

2. **Versioning** - When a user updates their API, do we keep the old module loaded during
   transition? The BEAM supports two versions simultaneously, which helps.

3. **Rate limiting** - Per-user, per-API, or both? Should be configurable.

4. **Cold start** - On application restart, all dynamic modules must be recompiled from
   stored source code. How to handle thousands of APIs? Lazy loading (compile on first
   request) vs eager loading at startup.

5. **Observability** - How to attribute telemetry (latency, errors) to specific dynamic
   APIs? Plug.Telemetry with dynamic span names.

6. **Testing** - How do users test their APIs before publishing? A "try it" feature that
   runs in Dune sandbox with user-provided params.

7. **Collaboration** - Can multiple users share/fork APIs? Implications for the module
   namespace.

8. **Marketplace** - If APIs become public, need content moderation and abuse prevention.

9. **State migration** - When a user updates their API, what happens to stored data?
   The key-value store is schema-free, so this is partially addressed, but complex cases
   need thought.

10. **LLM cost management** - Retries multiply cost. Cache successful generations?
    Use cheaper models for simple APIs?
