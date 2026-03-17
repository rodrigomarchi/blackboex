# Discovery: API Publishing and Deployment System

> **Date**: 2026-03-17
> **Context**: BlackBoex -- platform where users describe APIs in natural language, an LLM generates Elixir code, and users publish it as a REST endpoint with a public URL.
> **Goal**: Design the architecture for dynamically publishing, routing, securing, documenting, and versioning user-generated APIs.

---

## Table of Contents

1. [High-Level Architecture](#1-high-level-architecture)
2. [Dynamic Routing and URL Assignment](#2-dynamic-routing-and-url-assignment)
3. [API Gateway Pattern](#3-api-gateway-pattern)
4. [Safe Code Execution and Sandboxing](#4-safe-code-execution-and-sandboxing)
5. [Authentication for Published APIs](#5-authentication-for-published-apis)
6. [Rate Limiting and Throttling](#6-rate-limiting-and-throttling)
7. [API Documentation Auto-Generation](#7-api-documentation-auto-generation)
8. [Deployment Pipeline and Zero-Downtime Updates](#8-deployment-pipeline-and-zero-downtime-updates)
9. [Custom Domains](#9-custom-domains)
10. [API Versioning](#10-api-versioning)
11. [Data Model](#11-data-model)
12. [Security Considerations](#12-security-considerations)
13. [Architecture Recommendation for BlackBoex](#13-architecture-recommendation-for-blackboex)

---

## 1. High-Level Architecture

BlackBoex needs to act as a **Function-as-a-Service (FaaS) platform** built on the BEAM VM. The flow is:

```
User describes API in natural language
        |
        v
LLM generates Elixir code (module with handler functions)
        |
        v
Code is validated, sandboxed, and compiled at runtime
        |
        v
API is published with a unique URL
        |
        v
External consumers call the URL (GET/POST)
        |
        v
Gateway routes request -> sandbox executes code -> response returned
```

The BEAM VM is uniquely suited for this because:
- **Lightweight processes**: Each API invocation can run in an isolated process
- **Preemptive scheduling**: One user's API cannot starve others of CPU
- **Fault tolerance**: A crashing handler is isolated via supervisors
- **Hot code loading**: Modules can be compiled and loaded at runtime without restarts

---

## 2. Dynamic Routing and URL Assignment

### URL Strategy Options

| Strategy | Example | Pros | Cons |
|---|---|---|---|
| **Path-based** | `api.blackboex.com/u/user123/my-api` | Simple, single domain, easy TLS | Long URLs, no isolation between users |
| **Subdomain per user** | `user123.blackboex.com/my-api` | Clean separation, feels like own service | Wildcard DNS/TLS needed, cookie isolation |
| **Subdomain per API** | `my-api-abc123.blackboex.com` | Maximum isolation | Explosion of subdomains, DNS complexity |

**Recommendation**: Use **path-based routing** as the default, with optional subdomain-per-user for Pro/paid users. This keeps infrastructure simple while providing a clean upgrade path.

### Path-Based Implementation

The gateway uses a catch-all route that dynamically dispatches to user API handlers:

```elixir
# In the Phoenix Router
scope "/u", BlackboexWeb do
  pipe_through [:api, :api_auth, :rate_limit]

  # Catch-all: /:username/:api_slug with any HTTP method
  match :get, "/:username/:api_slug", ApiGatewayController, :handle
  match :post, "/:username/:api_slug", ApiGatewayController, :handle
  match :get, "/:username/:api_slug/*path", ApiGatewayController, :handle
  match :post, "/:username/:api_slug/*path", ApiGatewayController, :handle
end
```

```elixir
defmodule BlackboexWeb.ApiGatewayController do
  use BlackboexWeb, :controller

  alias Blackboex.ApiRegistry
  alias Blackboex.Sandbox

  @spec handle(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def handle(conn, %{"username" => username, "api_slug" => slug} = params) do
    case ApiRegistry.lookup(username, slug) do
      {:ok, api} ->
        execute_api(conn, api, params)

      {:error, :not_found} ->
        conn
        |> put_status(404)
        |> json(%{error: "API not found"})

      {:error, :disabled} ->
        conn
        |> put_status(503)
        |> json(%{error: "API is currently disabled"})
    end
  end

  defp execute_api(conn, api, params) do
    request_data = %{
      method: conn.method,
      path: params["path"] || [],
      query_params: conn.query_params,
      body: conn.body_params,
      headers: relevant_headers(conn)
    }

    case Sandbox.execute(api, request_data, timeout: api.timeout_ms) do
      {:ok, response} ->
        conn
        |> put_status(response.status || 200)
        |> json(response.body)

      {:error, :timeout} ->
        conn
        |> put_status(504)
        |> json(%{error: "API execution timed out"})

      {:error, reason} ->
        conn
        |> put_status(500)
        |> json(%{error: "Internal API error", detail: inspect(reason)})
    end
  end
end
```

### Subdomain-Based Implementation

For subdomain routing, use a custom Plug that extracts the subdomain and sets it in the connection assigns:

```elixir
defmodule BlackboexWeb.Plugs.SubdomainRouter do
  @behaviour Plug

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case extract_subdomain(conn.host) do
      nil ->
        # No subdomain -- serve main app
        conn

      subdomain ->
        conn
        |> Plug.Conn.assign(:subdomain, subdomain)
        |> Plug.Conn.assign(:routing_mode, :subdomain)
    end
  end

  defp extract_subdomain(host) do
    # Assumes base domain is "blackboex.com" or "blackboex.localhost"
    base_domain = Application.get_env(:blackboex_web, :base_domain, "blackboex.com")

    case String.replace_suffix(host, "." <> base_domain, "") do
      ^host -> nil  # No subdomain found
      "" -> nil
      subdomain -> subdomain
    end
  end
end
```

References:
- [Subdomain-Based Multi-Tenancy in Phoenix -- Alembic](https://alembic.com.au/blog/subdomain-based-multi-tenancy-in-phoenix)
- [Create a multi-tenant, whitelabel application in Elixir & Phoenix -- Dynamic subdomain routing](https://medium.com/redsquirrel-tech/create-a-multi-tenant-whitelabel-application-in-elixir-phoenix-part-ii-dynamic-subdomain-a0f77fc0dc1)
- [Subdomains With Phoenix -- Gazler](https://blog.gazler.com/blog/2015/07/18/subdomains-with-phoenix/)

---

## 3. API Gateway Pattern

### The Gateway as a Plug Pipeline

The gateway is not a separate service -- it is a Plug pipeline within the same Phoenix application. The BEAM's process model makes this safe: each request runs in its own process.

```
Request
  |
  v
[SubdomainRouter]  -- extracts tenant/user context
  |
  v
[ApiKeyAuth]       -- verifies API key, loads user
  |
  v
[RateLimiter]      -- enforces rate limits per API key
  |
  v
[ApiResolver]      -- looks up the API definition from ETS/DB
  |
  v
[RequestValidator] -- validates input against API schema
  |
  v
[SandboxExecutor]  -- runs user code in isolated process
  |
  v
[ResponseFormatter] -- normalizes and returns response
```

### API Registry with ETS

For fast lookups, published APIs are cached in ETS with a GenServer managing the cache:

```elixir
defmodule Blackboex.ApiRegistry do
  use GenServer

  @table :api_registry
  @type api_key :: {String.t(), String.t()}  # {username, slug}

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @spec lookup(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def lookup(username, slug) do
    case :ets.lookup(@table, {username, slug}) do
      [{_key, api}] when api.status == :active -> {:ok, api}
      [{_key, api}] when api.status == :disabled -> {:error, :disabled}
      [] -> {:error, :not_found}
    end
  end

  @spec register(map()) :: :ok
  def register(api) do
    GenServer.call(__MODULE__, {:register, api})
  end

  @spec unregister(String.t(), String.t()) :: :ok
  def unregister(username, slug) do
    GenServer.call(__MODULE__, {:unregister, username, slug})
  end

  @impl true
  def init(_opts) do
    table = :ets.new(@table, [:set, :named_table, :protected, read_concurrency: true])

    # Load all active APIs from database on startup
    load_active_apis(table)

    {:ok, %{table: table}}
  end

  @impl true
  def handle_call({:register, api}, _from, state) do
    :ets.insert(@table, {{api.username, api.slug}, api})
    {:reply, :ok, state}
  end

  @impl true
  def handle_call({:unregister, username, slug}, _from, state) do
    :ets.delete(@table, {username, slug})
    {:reply, :ok, state}
  end

  defp load_active_apis(table) do
    Blackboex.Apis.list_active()
    |> Enum.each(fn api ->
      :ets.insert(table, {{api.username, api.slug}, api})
    end)
  end
end
```

### Reverse Proxy Plug (for Future Use)

If BlackBoex evolves to run user APIs as separate processes or nodes, the `reverse_proxy_plug` library provides a battle-tested Plug-based reverse proxy with HTTP/2 support, chunked transfer encoding, and dynamic upstream configuration:

```elixir
# Dynamic upstream based on request
defmodule BlackboexWeb.Plugs.ApiProxy do
  use ReverseProxyPlug, upstream: &__MODULE__.resolve_upstream/1

  @spec resolve_upstream(Plug.Conn.t()) :: String.t()
  def resolve_upstream(conn) do
    api = conn.assigns[:resolved_api]
    "http://#{api.host}:#{api.port}"
  end
end
```

References:
- [ReverseProxyPlug -- GitHub](https://github.com/tallarium/reverse_proxy_plug)
- [Annon API Gateway -- Configurable API gateway in Elixir](https://github.com/Nebo15/annon.api)
- [Rackla -- Open Source API Gateway in Elixir](https://github.com/AntonFagerberg/rackla)
- [Plug.Router -- HexDocs](https://hexdocs.pm/plug/Plug.Router.html)

---

## 4. Safe Code Execution and Sandboxing

This is the **most critical** component. User-generated code runs on the same BEAM VM, so it must be heavily restricted.

### Strategy: AST Allowlisting + Process Isolation

The approach is multi-layered:

1. **AST Analysis**: Parse user code into AST, walk it, reject dangerous calls
2. **Module Namespacing**: All user modules are compiled under a unique namespace
3. **Process Isolation**: Execute in a spawned process with timeout and memory limits
4. **Restricted Imports**: Only allow a curated set of modules

### Dune: Sandbox for Elixir

The [Dune](https://github.com/functional-rewire/dune) library provides exactly this. It is a sandbox for Elixir to safely evaluate untrusted code from user input with:

- **Allowlist mechanism**: Only permits safe modules and functions
- **No environment access**: No access to env vars, file system, or network
- **No atom leaks**: Handles atoms safely to prevent atom table exhaustion
- **No actual module creation**: Simulates module behavior through maps of anonymous functions

```elixir
# Using Dune for safe evaluation
Dune.eval_string("1 + 1")
# {:ok, %Dune.Success{value: 2, inspected: "2"}}

Dune.eval_string("System.halt()")
# {:error, %Dune.Failure{type: :restricted, message: "** (DuneRestrictedError) ..."}}

Dune.eval_string("File.read!(\"/etc/passwd\")")
# {:error, %Dune.Failure{type: :restricted, message: "** (DuneRestrictedError) ..."}}
```

### Custom Sandbox for BlackBoex

For production, we need more control than Dune alone provides. A custom sandbox wraps the execution:

```elixir
defmodule Blackboex.Sandbox do
  @max_execution_time_ms 5_000
  @max_memory_bytes 50_000_000  # 50MB
  @max_reductions 1_000_000

  @spec execute(map(), map(), keyword()) :: {:ok, map()} | {:error, atom()}
  def execute(api, request_data, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, @max_execution_time_ms)
    caller = self()

    {pid, ref} =
      spawn_monitor(fn ->
        # Set process flags for resource limiting
        Process.flag(:max_heap_size, %{size: div(@max_memory_bytes, 8), kill: true, error_logger: true})

        try do
          result = invoke_handler(api.compiled_module, api.handler_function, request_data)
          send(caller, {:sandbox_result, self(), {:ok, result}})
        rescue
          e ->
            send(caller, {:sandbox_result, self(), {:error, Exception.message(e)}})
        end
      end)

    receive do
      {:sandbox_result, ^pid, result} ->
        Process.demonitor(ref, [:flush])
        result

      {:DOWN, ^ref, :process, ^pid, :killed} ->
        {:error, :resource_limit_exceeded}

      {:DOWN, ^ref, :process, ^pid, reason} ->
        {:error, {:crashed, reason}}
    after
      timeout ->
        Process.exit(pid, :kill)
        Process.demonitor(ref, [:flush])

        receive do
          {:sandbox_result, ^pid, _} -> :ok
          {:DOWN, ^ref, :process, ^pid, _} -> :ok
        after
          0 -> :ok
        end

        {:error, :timeout}
    end
  end

  defp invoke_handler(module, function, request_data) do
    apply(module, function, [request_data])
  end
end
```

### Dynamic Module Compilation

When a user publishes an API, the LLM-generated code is compiled into a namespaced module:

```elixir
defmodule Blackboex.Compiler do
  @spec compile_api(String.t(), String.t(), String.t()) ::
          {:ok, module()} | {:error, String.t()}
  def compile_api(user_id, api_slug, source_code) do
    module_name = module_name_for(user_id, api_slug)

    # Wrap user code in a namespaced module with restricted imports
    wrapped_code = """
    defmodule #{module_name} do
      @moduledoc false

      # Only allow safe standard library modules
      alias Blackboex.Sandbox.SafeModules, as: Safe

      #{source_code}
    end
    """

    # First pass: AST validation
    with {:ok, ast} <- Code.string_to_quoted(wrapped_code),
         :ok <- validate_ast(ast) do
      # Second pass: compilation
      try do
        [{module, _binary}] = Code.compile_string(wrapped_code)
        {:ok, module}
      rescue
        e in [CompileError, SyntaxError, TokenMissingError] ->
          {:error, Exception.message(e)}
      end
    end
  end

  @spec module_name_for(String.t(), String.t()) :: String.t()
  defp module_name_for(user_id, api_slug) do
    safe_user = String.replace(user_id, ~r/[^a-zA-Z0-9]/, "")
    safe_slug = api_slug |> String.replace(~r/[^a-zA-Z0-9_]/, "") |> Macro.camelize()
    "Blackboex.UserApis.U#{safe_user}.#{safe_slug}"
  end

  @spec validate_ast(Macro.t()) :: :ok | {:error, String.t()}
  defp validate_ast(ast) do
    # Walk the AST and reject dangerous patterns
    dangerous_modules = [
      System, File, IO, Port, :os, :erlang, Node,
      Code, Module, Application, Process,
      :gen_tcp, :gen_udp, :ssl, :httpc, :inet
    ]

    case Macro.prewalk(ast, :ok, fn
      # Block dangerous module references
      {:__aliases__, _, parts} = node, :ok ->
        module = Module.concat(parts)
        if module in dangerous_modules do
          {node, {:error, "Access to #{inspect(module)} is not allowed"}}
        else
          {node, :ok}
        end

      # Block :erlang and other atom-based module calls
      {{:., _, [module, _func]}, _, _args} = node, :ok when is_atom(module) ->
        if module in dangerous_modules do
          {node, {:error, "Access to #{inspect(module)} is not allowed"}}
        else
          {node, :ok}
        end

      node, acc ->
        {node, acc}
    end) do
      {_ast, :ok} -> :ok
      {_ast, error} -> error
    end
  end
end
```

**Important**: `Code.compile_string/1` produces modules that exist globally in the BEAM VM. Each user API module must have a unique name. Modules defined at runtime do not produce `.beam` files unless explicitly written. To prevent memory leaks from accumulated modules, implement a cleanup mechanism using `:code.purge/1` and `:code.delete/1` when APIs are unpublished.

References:
- [Dune -- Sandbox for Elixir](https://github.com/functional-rewire/dune)
- [Exbox -- Configurable sandbox library](https://github.com/christhekeele/exbox)
- [Code module -- Elixir v1.19.5](https://hexdocs.pm/elixir/Code.html)
- [Elixir Forum -- Compiling and loading modules dynamically](https://elixirforum.com/t/compiling-and-loading-modules-dynamically/32170)

---

## 5. Authentication for Published APIs

### Two Layers of Authentication

1. **Platform Authentication**: Users log into BlackBoex to manage their APIs (handled by `phx.gen.auth`)
2. **API Key Authentication**: Consumers of published APIs authenticate with API keys

### API Key Design

Each published API gets one or more API keys. Keys are hashed before storage (like passwords):

```elixir
defmodule Blackboex.ApiKeys do
  @prefix "bb_"
  @key_length 32

  @spec create_key(integer()) :: {:ok, String.t(), map()} | {:error, Ecto.Changeset.t()}
  def create_key(api_id) do
    raw_key = @prefix <> Base.url_encode64(:crypto.strong_rand_bytes(@key_length), padding: false)
    hashed_key = :crypto.hash(:sha256, raw_key)

    case Repo.insert(%ApiKey{
      api_id: api_id,
      key_hash: hashed_key,
      key_prefix: String.slice(raw_key, 0, 8),
      status: :active
    }) do
      {:ok, api_key} -> {:ok, raw_key, api_key}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec verify_key(String.t()) :: {:ok, map()} | {:error, atom()}
  def verify_key(raw_key) do
    hashed = :crypto.hash(:sha256, raw_key)

    case Repo.get_by(ApiKey, key_hash: hashed, status: :active) do
      nil -> {:error, :invalid_key}
      api_key -> {:ok, Repo.preload(api_key, :api)}
    end
  end
end
```

### Authentication Plug

```elixir
defmodule BlackboexWeb.Plugs.ApiKeyAuth do
  import Plug.Conn

  @behaviour Plug

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with {:ok, key} <- extract_key(conn),
         {:ok, api_key} <- Blackboex.ApiKeys.verify_key(key) do
      conn
      |> assign(:api_key, api_key)
      |> assign(:authenticated_api, api_key.api)
    else
      {:error, :missing_key} ->
        conn
        |> put_status(401)
        |> Phoenix.Controller.json(%{error: "API key required", hint: "Pass via Authorization: Bearer bb_... header"})
        |> halt()

      {:error, :invalid_key} ->
        conn
        |> put_status(403)
        |> Phoenix.Controller.json(%{error: "Invalid API key"})
        |> halt()
    end
  end

  defp extract_key(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> key] -> {:ok, String.trim(key)}
      _ ->
        case conn.query_params do
          %{"api_key" => key} -> {:ok, key}
          _ -> {:error, :missing_key}
        end
    end
  end
end
```

### Public vs Private APIs

Some APIs may be public (no key required). This is controlled by a flag on the API definition:

```elixir
defmodule BlackboexWeb.Plugs.ApiKeyAuth do
  # Modified call/2 to support public APIs
  def call(conn, _opts) do
    api = conn.assigns[:resolved_api]

    if api && api.visibility == :public do
      conn
    else
      # ... normal key verification
    end
  end
end
```

### Phoenix Built-In Token Support

Phoenix 1.8+ includes `Phoenix.Token` for lightweight token generation and verification without external dependencies:

```elixir
# Generate a token
token = Phoenix.Token.sign(BlackboexWeb.Endpoint, "api-access", %{api_id: 123, user_id: 456})

# Verify (with max_age of 90 days)
{:ok, data} = Phoenix.Token.verify(BlackboexWeb.Endpoint, "api-access", token, max_age: 7_776_000)
```

For more complex JWT needs, **Guardian** (using Joken under the hood) is the standard choice:
- Supports token refresh, revocation, permissions
- Battle-tested in production

References:
- [API Authentication -- Phoenix v1.8.5](https://hexdocs.pm/phoenix/api_authentication.html)
- [Phoenix.Token -- HexDocs](https://hexdocs.pm/phoenix/Phoenix.Token.html)
- [Guardian -- Elixir Authentication](https://github.com/ueberauth/guardian)
- [JWT Auth in Elixir with Joken -- Elixir School](https://elixirschool.com/blog/jwt-auth-with-joken)

---

## 6. Rate Limiting and Throttling

### Hammer: The Recommended Library

[Hammer](https://github.com/ExHammer/hammer) is the most mature Elixir rate limiter with pluggable backends. As of v7.x:

| Backend | Distribution | Persistence | Best For |
|---|---|---|---|
| `Hammer.ETS` | Single node (can be distributed) | In-memory only | Development, single-node prod |
| `Hammer.Atomic` | Single node | In-memory only | Highest performance single-node |
| `Hammer.Redis` | Multi-node | Persistent | Multi-node production |
| `Hammer.Mnesia` | Multi-node (beta) | Persistent | BEAM-native distribution |

Hammer supports both **fixed window** and **sliding window** algorithms.

### Integration with Plug

Using `hammer_plug` for seamless integration:

```elixir
# In mix.exs
defp deps do
  [
    {:hammer, "~> 7.0"},
    {:hammer_plug, "~> 3.0"}
  ]
end
```

```elixir
# config/config.exs
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60, cleanup_interval_ms: 60_000 * 10]}
```

### Multi-Tier Rate Limiting

BlackBoex needs rate limits at multiple levels:

```elixir
defmodule BlackboexWeb.Plugs.RateLimiter do
  import Plug.Conn

  @behaviour Plug

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    with :ok <- check_global_limit(conn),
         :ok <- check_ip_limit(conn),
         :ok <- check_api_key_limit(conn),
         :ok <- check_api_endpoint_limit(conn) do
      conn
    else
      {:error, :rate_limited, retry_after} ->
        conn
        |> put_resp_header("retry-after", to_string(retry_after))
        |> put_status(429)
        |> Phoenix.Controller.json(%{
          error: "Rate limit exceeded",
          retry_after: retry_after
        })
        |> halt()
    end
  end

  # Global: 10,000 req/min across all APIs
  defp check_global_limit(_conn) do
    case Hammer.check_rate("global", 60_000, 10_000) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited, 60}
    end
  end

  # Per IP: 100 req/min
  defp check_ip_limit(conn) do
    ip = conn.remote_ip |> :inet.ntoa() |> to_string()
    case Hammer.check_rate("ip:#{ip}", 60_000, 100) do
      {:allow, _count} -> :ok
      {:deny, _limit} -> {:error, :rate_limited, 60}
    end
  end

  # Per API key: configurable, default 60 req/min
  defp check_api_key_limit(conn) do
    case conn.assigns[:api_key] do
      nil -> :ok
      api_key ->
        limit = api_key.rate_limit || 60
        case Hammer.check_rate("key:#{api_key.id}", 60_000, limit) do
          {:allow, _count} -> :ok
          {:deny, _limit} -> {:error, :rate_limited, 60}
        end
    end
  end

  # Per API endpoint: configurable by API owner
  defp check_api_endpoint_limit(conn) do
    case conn.assigns[:resolved_api] do
      nil -> :ok
      api ->
        limit = api.rate_limit || 120
        case Hammer.check_rate("api:#{api.id}", 60_000, limit) do
          {:allow, _count} -> :ok
          {:deny, _limit} -> {:error, :rate_limited, 60}
        end
    end
  end
end
```

### PlugAttack Alternative

`PlugAttack` offers a more declarative DSL for defining rate limiting rules, supporting both throttling and blocking. It is a good alternative if the rule set becomes complex.

### Rate Limit Headers

Always return standard rate limit headers so consumers can self-regulate:

```
X-RateLimit-Limit: 60
X-RateLimit-Remaining: 45
X-RateLimit-Reset: 1679000000
```

References:
- [Hammer -- Elixir rate-limiter with pluggable backends](https://github.com/ExHammer/hammer)
- [Hammer Plug -- GitHub](https://github.com/ExHammer/hammer-plug)
- [Hammer v7.2.0 -- HexDocs](https://hexdocs.pm/hammer/Hammer.html)
- [Rate-limiting a Phoenix API with Hammer -- ElixirCasts](https://elixircasts.io/rate-limiting-a-phoenix-api-with-hammer)

---

## 7. API Documentation Auto-Generation

### OpenApiSpex: The Standard

[OpenApiSpex](https://github.com/open-api-spex/open_api_spex) is the standard Elixir library for generating OpenAPI 3.x specifications from Phoenix code. It can:

- Generate and serve a JSON OpenAPI spec document
- Cast request params to well-defined schema structs
- Validate params against schemas (reject bad requests before they hit handlers)
- Validate responses in tests
- Serve Swagger UI and RapiDoc

### Auto-Generating Specs for User APIs

Since user APIs are dynamically generated, we cannot use OpenApiSpex's compile-time macros. Instead, we build OpenAPI specs programmatically at publish time:

```elixir
defmodule Blackboex.ApiDocs do
  @spec generate_spec(map()) :: map()
  def generate_spec(api) do
    %{
      "openapi" => "3.1.0",
      "info" => %{
        "title" => api.name,
        "description" => api.description,
        "version" => api.version || "1.0.0"
      },
      "servers" => [
        %{"url" => "https://api.blackboex.com/u/#{api.username}/#{api.slug}"}
      ],
      "paths" => build_paths(api),
      "components" => %{
        "securitySchemes" => %{
          "apiKey" => %{
            "type" => "apiKey",
            "in" => "header",
            "name" => "Authorization",
            "description" => "Bearer token: `Authorization: Bearer bb_...`"
          }
        },
        "schemas" => build_schemas(api)
      },
      "security" => if(api.visibility == :public, do: [], else: [%{"apiKey" => []}])
    }
  end

  defp build_paths(api) do
    methods = api.supported_methods || ["GET", "POST"]

    path_item =
      methods
      |> Enum.map(fn method ->
        {String.downcase(method), build_operation(api, method)}
      end)
      |> Map.new()

    %{"/" => path_item}
  end

  defp build_operation(api, method) do
    base = %{
      "summary" => api.name,
      "description" => api.description,
      "operationId" => "#{api.slug}_#{String.downcase(method)}",
      "responses" => %{
        "200" => %{
          "description" => "Successful response",
          "content" => %{
            "application/json" => %{
              "schema" => api.response_schema || %{"type" => "object"}
            }
          }
        },
        "429" => %{"description" => "Rate limit exceeded"},
        "401" => %{"description" => "Authentication required"},
        "500" => %{"description" => "Internal API error"}
      }
    }

    if method == "POST" do
      Map.put(base, "requestBody", %{
        "required" => true,
        "content" => %{
          "application/json" => %{
            "schema" => api.request_schema || %{"type" => "object"}
          }
        }
      })
    else
      Map.put(base, "parameters", build_query_params(api))
    end
  end

  defp build_query_params(api) do
    (api.query_params || [])
    |> Enum.map(fn param ->
      %{
        "name" => param.name,
        "in" => "query",
        "required" => param.required || false,
        "schema" => %{"type" => param.type || "string"},
        "description" => param.description || ""
      }
    end)
  end

  defp build_schemas(api) do
    %{
      "Request" => api.request_schema || %{"type" => "object"},
      "Response" => api.response_schema || %{"type" => "object"}
    }
  end
end
```

### Serving Documentation

```elixir
# Router
scope "/u/:username/:api_slug" do
  get "/docs", ApiDocsController, :swagger_ui
  get "/openapi.json", ApiDocsController, :spec
end
```

```elixir
defmodule BlackboexWeb.ApiDocsController do
  use BlackboexWeb, :controller

  @spec spec(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def spec(conn, %{"username" => username, "api_slug" => slug}) do
    case Blackboex.ApiRegistry.lookup(username, slug) do
      {:ok, api} ->
        spec = Blackboex.ApiDocs.generate_spec(api)
        json(conn, spec)

      {:error, _} ->
        conn |> put_status(404) |> json(%{error: "API not found"})
    end
  end

  @spec swagger_ui(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def swagger_ui(conn, params) do
    spec_url = "/u/#{params["username"]}/#{params["api_slug"]}/openapi.json"

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, swagger_html(spec_url))
  end

  defp swagger_html(spec_url) do
    """
    <!DOCTYPE html>
    <html>
    <head>
      <title>API Documentation</title>
      <link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist/swagger-ui.css">
    </head>
    <body>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist/swagger-ui-bundle.js"></script>
      <script>
        SwaggerUIBundle({ url: "#{spec_url}", dom_id: '#swagger-ui' });
      </script>
    </body>
    </html>
    """
  end
end
```

### LLM-Assisted Documentation

Since the LLM generates the API code, it can also generate:
- Request/response JSON schemas
- Parameter descriptions
- Example requests and responses
- Error code documentation

These should be generated at the same time as the code and stored alongside the API definition.

References:
- [OpenApiSpex -- GitHub](https://github.com/open-api-spex/open_api_spex)
- [OpenApiSpex v3.16.0 -- HexDocs](https://hexdocs.pm/open_api_spex/3.16.0/readme.html)

---

## 8. Deployment Pipeline and Zero-Downtime Updates

### The BlackBoex Advantage: No Traditional Deployment Needed

Because user APIs are compiled and loaded at runtime within the BEAM VM, "deploying" an API means:

1. Compile new module version with `Code.compile_string/1`
2. The BEAM automatically uses the new version for new calls
3. Purge the old module version with `:code.purge/1`

This is effectively **hot code loading** -- a first-class BEAM capability.

### API Update Flow

```elixir
defmodule Blackboex.ApiDeployer do
  alias Blackboex.{Compiler, ApiRegistry, Repo}

  @spec deploy(map(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def deploy(api, new_source_code) do
    # 1. Compile new version (does not affect current running version)
    case Compiler.compile_api(api.user_id, api.slug, new_source_code) do
      {:ok, new_module} ->
        # 2. Run smoke tests against the new module
        case run_smoke_tests(new_module, api.test_cases) do
          :ok ->
            # 3. Update the registry atomically
            old_module = api.compiled_module

            updated_api = %{api |
              compiled_module: new_module,
              source_code: new_source_code,
              version: increment_version(api.version),
              updated_at: DateTime.utc_now()
            }

            # 4. Persist to database
            {:ok, _} = Repo.update(Api.changeset(api, updated_api))

            # 5. Update ETS cache
            ApiRegistry.register(updated_api)

            # 6. Purge old module (after a grace period for in-flight requests)
            schedule_purge(old_module, delay_ms: 5_000)

            {:ok, updated_api}

          {:error, test_failures} ->
            # Rollback: purge the new module
            :code.purge(new_module)
            :code.delete(new_module)
            {:error, "Smoke tests failed: #{inspect(test_failures)}"}
        end

      {:error, compile_error} ->
        {:error, "Compilation failed: #{compile_error}"}
    end
  end

  defp run_smoke_tests(module, test_cases) do
    results =
      Enum.map(test_cases || [], fn test ->
        try do
          result = apply(module, :handle, [test.input])
          if result == test.expected_output, do: :pass, else: {:fail, result}
        rescue
          e -> {:error, Exception.message(e)}
        end
      end)

    if Enum.all?(results, &(&1 == :pass)) do
      :ok
    else
      {:error, results}
    end
  end

  defp schedule_purge(module, opts) do
    delay = Keyword.get(opts, :delay_ms, 5_000)
    Process.send_after(self(), {:purge_module, module}, delay)
  end

  defp increment_version(nil), do: "1.0.1"
  defp increment_version(version) do
    case Version.parse(version) do
      {:ok, v} -> "#{v.major}.#{v.minor}.#{v.patch + 1}"
      :error -> "1.0.1"
    end
  end
end
```

### Platform-Level Deployment (the BlackBoex app itself)

For deploying the BlackBoex platform, use standard Elixir release practices:

| Strategy | How | When |
|---|---|---|
| **Rolling update** | Kubernetes rolls pods one at a time | Standard releases |
| **Blue-green** | Two full environments, switch traffic at load balancer | Major versions |
| **Hot code upgrade** | OTP appup/relup | Rare; complex, not recommended for most teams |

**Recommendation**: Use **rolling Kubernetes deployments** for the platform itself. Hot code upgrades are a BEAM capability but complex to manage -- they require appups, relups, and careful state migration. Rolling deployments are simpler and equally effective for stateless web servers.

For user APIs specifically, runtime compilation already provides zero-downtime updates without any deployment infrastructure.

References:
- [Elixir/Erlang Hot Swapping Code](https://kennyballou.com/blog/2016/12/elixir-hot-swapping/index.html)
- [Elixir and Kubernetes: A love story](https://david-delassus.medium.com/elixir-and-kubernetes-a-love-story-721cc6a5c7d5)
- [How does Elixir compile/execute code?](https://medium.com/@fxn/how-does-elixir-compile-execute-code-c1b36c9ec8cf)

---

## 9. Custom Domains

### Architecture

Custom domains allow users to serve their APIs from their own domain (e.g., `api.acme.com` instead of `api.blackboex.com/u/acme/...`).

### Implementation Layers

1. **DNS**: User creates a CNAME record pointing `api.acme.com` -> `custom.blackboex.com`
2. **TLS**: BlackBoex obtains an SSL certificate for the custom domain
3. **Routing**: Incoming requests to the custom domain are mapped to the correct user/API

### SiteEncrypt: Automatic Let's Encrypt for Elixir

[SiteEncrypt](https://github.com/sasa1977/site_encrypt) by Sasa Juric provides integrated Let's Encrypt certification directly within Elixir applications. It handles:

- Automatic certificate issuance via ACME protocol
- Automatic renewal before expiration
- HTTP-01 challenge response
- Works with both Cowboy and Bandit

```elixir
# For the platform's own domain and wildcard
defmodule BlackboexWeb.Endpoint do
  # SiteEncrypt integration for automatic HTTPS
  use SiteEncrypt.Phoenix

  @impl SiteEncrypt
  def certification do
    SiteEncrypt.configure(
      client: :native,
      domains: ["blackboex.com", "*.blackboex.com"],
      emails: ["admin@blackboex.com"],
      db_folder: Application.app_dir(:blackboex_web, "priv/cert_db"),
      directory_url:
        case config_env() do
          :prod -> "https://acme-v02.api.letsencrypt.org/directory"
          _ -> {:internal, port: 4002}
        end
    )
  end
end
```

### Custom Domain TLS with Caddy or Reverse Proxy

For custom domains at scale, a reverse proxy layer (Caddy, nginx, or Traefik) in front of the Phoenix app is more practical:

```
                                  +-----------------+
 api.acme.com ---CNAME--> custom.blackboex.com ---> | Caddy / Traefik | ---> Phoenix App
                                  |  (auto TLS)    |
                                  +-----------------+
```

**Caddy** is particularly well-suited because it automates HTTPS for any domain pointed at it, including on-demand TLS:

```
# Caddyfile for on-demand TLS
{
    on_demand_tls {
        ask http://localhost:4000/api/internal/verify-domain
    }
}

:443 {
    tls {
        on_demand
    }
    reverse_proxy localhost:4000
}
```

The `/api/internal/verify-domain` endpoint checks the database to confirm the domain belongs to a registered user before Caddy issues a certificate.

### Domain Verification Plug

```elixir
defmodule BlackboexWeb.Plugs.CustomDomainResolver do
  @behaviour Plug

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    host = conn.host

    case Blackboex.CustomDomains.lookup(host) do
      {:ok, domain_config} ->
        conn
        |> Plug.Conn.assign(:custom_domain, domain_config)
        |> Plug.Conn.assign(:user_id, domain_config.user_id)

      {:error, :not_found} ->
        # Not a custom domain, continue normal routing
        conn
    end
  end
end
```

### Let's Encrypt Challenge Types

| Challenge | How | Wildcard Support | Automation |
|---|---|---|---|
| **HTTP-01** | Serve a file at `/.well-known/acme-challenge/` | No | Easy |
| **DNS-01** | Create a TXT DNS record | Yes | Requires DNS API |
| **TLS-ALPN-01** | Respond during TLS handshake | No | Moderate |

For custom user domains, **HTTP-01** is simplest (Caddy handles this automatically). For the platform's wildcard cert (`*.blackboex.com`), **DNS-01** is required.

References:
- [SiteEncrypt -- Integrated Let's Encrypt for Elixir](https://github.com/sasa1977/site_encrypt)
- [ACME client for Elixir](https://github.com/sikanhe/acme)
- [Let's Encrypt Challenge Types](https://letsencrypt.org/docs/challenge-types/)

---

## 10. API Versioning

### Versioning Strategy

Since each published API is a discrete unit (not a traditional Phoenix controller), versioning is simpler than in typical REST APIs. Each API has an explicit version stored in the database.

### Recommended: URL Path Versioning

The simplest and most explicit approach:

```
https://api.blackboex.com/u/user123/my-api/v1
https://api.blackboex.com/u/user123/my-api/v2
```

```elixir
# Router
scope "/u/:username/:api_slug" do
  pipe_through [:api, :api_auth, :rate_limit]

  match :get, "/v:version", ApiGatewayController, :handle
  match :post, "/v:version", ApiGatewayController, :handle
  match :get, "/v:version/*path", ApiGatewayController, :handle
  match :post, "/v:version/*path", ApiGatewayController, :handle

  # Default to latest version
  match :get, "/", ApiGatewayController, :handle_latest
  match :post, "/", ApiGatewayController, :handle_latest
end
```

### Version Management

```elixir
defmodule Blackboex.ApiVersions do
  @spec get_version(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, atom()}
  def get_version(username, slug, version) do
    Repo.get_by(ApiVersion,
      username: username,
      slug: slug,
      version: version,
      status: :active
    )
    |> case do
      nil -> {:error, :version_not_found}
      api_version -> {:ok, api_version}
    end
  end

  @spec get_latest(String.t(), String.t()) :: {:ok, map()} | {:error, atom()}
  def get_latest(username, slug) do
    from(av in ApiVersion,
      where: av.username == ^username and av.slug == ^slug and av.status == :active,
      order_by: [desc: av.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      api_version -> {:ok, api_version}
    end
  end

  @spec deprecate(integer()) :: {:ok, map()} | {:error, Ecto.Changeset.t()}
  def deprecate(version_id) do
    ApiVersion
    |> Repo.get!(version_id)
    |> ApiVersion.changeset(%{status: :deprecated, deprecated_at: DateTime.utc_now()})
    |> Repo.update()
  end
end
```

### Alternative: Header-Based Versioning

For APIs where URL changes are undesirable, support an `X-Api-Version` header:

```elixir
defmodule BlackboexWeb.Plugs.ApiVersionResolver do
  @behaviour Plug

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    version =
      case Plug.Conn.get_req_header(conn, "x-api-version") do
        [v] -> v
        _ -> conn.params["version"] || "latest"
      end

    Plug.Conn.assign(conn, :api_version, version)
  end
end
```

### Deprecation Notices

When a version is deprecated, include headers in the response:

```
Deprecation: true
Sunset: Sat, 01 Jun 2026 00:00:00 GMT
Link: <https://api.blackboex.com/u/user123/my-api/v2>; rel="successor-version"
```

References:
- [Versioned API with Phoenix -- ElixirCasts](https://elixircasts.io/versioned-api-with-phoenix)
- [PhoenixApiVersions -- HexDocs](https://hexdocs.pm/phoenix_api_versions/PhoenixApiVersions.html)
- [Versionary -- Plug for API versioning](https://github.com/sticksnleaves/versionary)
- [API Versioning with The Phoenix Framework](https://medium.com/@michael.oauth/api-versioning-with-the-phoenix-framework-d38a3eb05026)

---

## 11. Data Model

### Core Schemas

```elixir
# Published API
defmodule Blackboex.Apis.Api do
  use Ecto.Schema

  schema "apis" do
    belongs_to :user, Blackboex.Accounts.User

    field :name, :string
    field :slug, :string
    field :description, :string
    field :status, Ecto.Enum, values: [:draft, :active, :disabled, :archived]
    field :visibility, Ecto.Enum, values: [:public, :private], default: :private
    field :supported_methods, {:array, :string}, default: ["GET", "POST"]
    field :timeout_ms, :integer, default: 5_000
    field :rate_limit, :integer, default: 60  # per minute

    field :source_code, :string
    field :compiled_module_name, :string

    field :request_schema, :map
    field :response_schema, :map
    field :query_params, {:array, :map}

    has_many :versions, Blackboex.Apis.ApiVersion
    has_many :api_keys, Blackboex.Apis.ApiKey

    timestamps()
  end
end

# API Version (immutable snapshot)
defmodule Blackboex.Apis.ApiVersion do
  use Ecto.Schema

  schema "api_versions" do
    belongs_to :api, Blackboex.Apis.Api

    field :version, :string
    field :source_code, :string
    field :compiled_module_name, :string
    field :status, Ecto.Enum, values: [:active, :deprecated, :retired]
    field :deprecated_at, :utc_datetime
    field :changelog, :string

    field :request_schema, :map
    field :response_schema, :map

    timestamps()
  end
end

# API Key
defmodule Blackboex.Apis.ApiKey do
  use Ecto.Schema

  schema "api_keys" do
    belongs_to :api, Blackboex.Apis.Api

    field :key_hash, :binary
    field :key_prefix, :string       # First 8 chars for identification
    field :label, :string            # User-friendly name
    field :status, Ecto.Enum, values: [:active, :revoked]
    field :rate_limit, :integer      # Override per-key limit
    field :last_used_at, :utc_datetime
    field :expires_at, :utc_datetime

    timestamps()
  end
end

# Custom Domain
defmodule Blackboex.Apis.CustomDomain do
  use Ecto.Schema

  schema "custom_domains" do
    belongs_to :user, Blackboex.Accounts.User

    field :domain, :string
    field :verified, :boolean, default: false
    field :verification_token, :string
    field :ssl_status, Ecto.Enum, values: [:pending, :active, :expired, :error]

    timestamps()
  end
end

# API Invocation Log (for analytics and debugging)
defmodule Blackboex.Apis.InvocationLog do
  use Ecto.Schema

  schema "api_invocation_logs" do
    belongs_to :api, Blackboex.Apis.Api
    belongs_to :api_key, Blackboex.Apis.ApiKey

    field :method, :string
    field :path, :string
    field :status_code, :integer
    field :response_time_ms, :integer
    field :ip_address, :string
    field :error, :string

    timestamps(updated_at: false)
  end
end
```

### Migration Example

```elixir
defmodule Blackboex.Repo.Migrations.CreateApis do
  use Ecto.Migration

  def change do
    create table(:apis) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :slug, :string, null: false
      add :description, :text
      add :status, :string, null: false, default: "draft"
      add :visibility, :string, null: false, default: "private"
      add :supported_methods, {:array, :string}, default: ["GET", "POST"]
      add :timeout_ms, :integer, default: 5_000
      add :rate_limit, :integer, default: 60
      add :source_code, :text
      add :compiled_module_name, :string
      add :request_schema, :map
      add :response_schema, :map
      add :query_params, {:array, :map}

      timestamps()
    end

    create unique_index(:apis, [:user_id, :slug])
    create index(:apis, [:status])

    create table(:api_versions) do
      add :api_id, references(:apis, on_delete: :delete_all), null: false
      add :version, :string, null: false
      add :source_code, :text, null: false
      add :compiled_module_name, :string
      add :status, :string, null: false, default: "active"
      add :deprecated_at, :utc_datetime
      add :changelog, :text
      add :request_schema, :map
      add :response_schema, :map

      timestamps()
    end

    create unique_index(:api_versions, [:api_id, :version])

    create table(:api_keys) do
      add :api_id, references(:apis, on_delete: :delete_all), null: false
      add :key_hash, :binary, null: false
      add :key_prefix, :string, null: false
      add :label, :string
      add :status, :string, null: false, default: "active"
      add :rate_limit, :integer
      add :last_used_at, :utc_datetime
      add :expires_at, :utc_datetime

      timestamps()
    end

    create unique_index(:api_keys, [:key_hash])
    create index(:api_keys, [:api_id])

    create table(:custom_domains) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :domain, :string, null: false
      add :verified, :boolean, default: false
      add :verification_token, :string
      add :ssl_status, :string, default: "pending"

      timestamps()
    end

    create unique_index(:custom_domains, [:domain])

    create table(:api_invocation_logs) do
      add :api_id, references(:apis, on_delete: :delete_all), null: false
      add :api_key_id, references(:api_keys, on_delete: :nilify_all)
      add :method, :string
      add :path, :string
      add :status_code, :integer
      add :response_time_ms, :integer
      add :ip_address, :string
      add :error, :text

      timestamps(updated_at: false)
    end

    create index(:api_invocation_logs, [:api_id, :inserted_at])
  end
end
```

---

## 12. Security Considerations

### Threat Model

| Threat | Impact | Mitigation |
|---|---|---|
| **Code injection** | Full VM compromise | AST allowlisting, Dune sandbox, no dangerous modules |
| **Resource exhaustion (CPU)** | DoS for all users | Process-level reduction limits, timeouts |
| **Resource exhaustion (memory)** | VM crash | `Process.flag(:max_heap_size, ...)` per execution |
| **Atom table exhaustion** | VM crash (atoms are not GC'd) | Dune handles this; also `String.to_existing_atom/1` only |
| **Module accumulation** | Memory leak | Scheduled purge of old modules via `:code.purge/1` |
| **API key theft** | Unauthorized access | Hash keys before storage, support rotation, expiration |
| **Excessive invocations** | Cost, DoS | Multi-tier rate limiting with Hammer |
| **Data exfiltration** | User data leak | No network/file access in sandbox, no env var access |
| **Malicious API responses** | XSS on docs page | Sanitize response bodies, CSP headers on docs |

### Defense in Depth

```
Layer 1: AST Validation     -- Reject code with dangerous module references
Layer 2: Dune Sandbox        -- Allowlist-based execution (no File, System, IO, etc.)
Layer 3: Process Isolation   -- Spawned process with max_heap_size and timeout
Layer 4: Rate Limiting       -- Hammer at IP, key, and API levels
Layer 5: Authentication      -- API keys with hashing, rotation, expiration
Layer 6: Monitoring          -- Log all invocations, alert on anomalies
Layer 7: Circuit Breaker     -- Disable APIs that consistently fail/timeout
```

### What User Code CAN Access

- Standard library: `Enum`, `Map`, `List`, `String`, `Integer`, `Float`, `Tuple`, `Keyword`, `Regex`, `Date`, `DateTime`, `NaiveDateTime`, `Time`, `URI`, `Base`, `Bitwise`
- The request data passed as argument (method, params, body, headers)
- JSON encoding/decoding (via a safe wrapper)
- Math operations

### What User Code CANNOT Access

- File system (`File`, `Path`, `IO`)
- Network (`HTTPoison`, `Req`, `:httpc`, `:gen_tcp`, `:ssl`)
- System (`System`, `:os`, `Port`)
- Code loading (`Code`, `Module`, `Application`)
- Process management (`Process`, `GenServer`, `Supervisor`, `Task`, `Agent`)
- Database (`Ecto`, `Repo`)
- Node/distribution (`Node`, `:rpc`, `:global`)
- Erlang internals (`:erlang`, `:ets`, `:mnesia`)

### Future: Network Access with Proxy

If user APIs need to make external HTTP calls (a common use case), this can be enabled via a controlled proxy module that enforces:
- Allowlisted domains only
- Request timeouts
- Response size limits
- Rate limiting on outbound requests

---

## 13. Architecture Recommendation for BlackBoex

### Phase 1: MVP (Launch)

| Component | Choice | Rationale |
|---|---|---|
| **URL scheme** | Path-based: `/u/:username/:api_slug` | Simplest, no DNS config needed |
| **Routing** | Phoenix Router catch-all + ETS registry | Fast lookups, simple implementation |
| **Code execution** | AST validation + process isolation | Good security without external deps |
| **Authentication** | API key (SHA-256 hashed) | Simple, well-understood |
| **Rate limiting** | Hammer with ETS backend | Single-node, fast, zero config |
| **Documentation** | Programmatic OpenAPI 3.1 + Swagger UI | Auto-generated from API metadata |
| **Versioning** | URL path (`/v1`, `/v2`) | Explicit, cacheable |
| **Deployment** | Runtime `Code.compile_string` | Zero-downtime by default |

### Phase 2: Growth

| Component | Upgrade | Trigger |
|---|---|---|
| **URL scheme** | Add subdomain-per-user option | Paid tier demand |
| **Code execution** | Integrate Dune library | First security audit |
| **Rate limiting** | Hammer + Redis backend | Multi-node deployment |
| **Custom domains** | Caddy with on-demand TLS | Enterprise customers |
| **Analytics** | Invocation logs + dashboard | User demand for metrics |
| **Outbound HTTP** | Controlled proxy module | User APIs need external data |

### Phase 3: Scale

| Component | Upgrade | Trigger |
|---|---|---|
| **Execution** | Separate BEAM nodes for user code | Isolation requirements |
| **Rate limiting** | Hammer + Mnesia | Full BEAM-native distribution |
| **Documentation** | Custom doc portal per user | Enterprise tier |
| **Versioning** | Header-based + content negotiation | API maturity |
| **Monitoring** | OpenTelemetry + Prometheus | SLA requirements |

### Key Dependencies

```elixir
# mix.exs additions for the API publishing system
defp deps do
  [
    # Rate limiting
    {:hammer, "~> 7.0"},
    {:hammer_plug, "~> 3.0"},

    # API documentation
    {:open_api_spex, "~> 3.16"},

    # Sandbox (Phase 2)
    # {:dune, "~> 0.3"},

    # SSL automation (Phase 2)
    # {:site_encrypt, "~> 0.6"},

    # Reverse proxy (Phase 3)
    # {:reverse_proxy_plug, "~> 3.0"},
  ]
end
```

### Request Lifecycle (Complete)

```
1. HTTP Request arrives at Phoenix endpoint
2. [Plug.Parsers]         -- Parse JSON body
3. [SubdomainRouter]      -- Check for custom domain or subdomain
4. [Phoenix.Router]       -- Match /u/:username/:api_slug route
5. [ApiVersionResolver]   -- Extract version from URL or header
6. [ApiResolver]          -- Look up API in ETS registry
7. [ApiKeyAuth]           -- Verify API key (skip if public)
8. [RateLimiter]          -- Check rate limits (IP, key, API)
9. [RequestValidator]     -- Validate against request schema
10. [ApiGatewayController] -- Orchestrate execution
11. [Sandbox.execute]      -- Spawn isolated process, run user code
12. [ResponseFormatter]    -- Normalize response, add headers
13. [InvocationLogger]     -- Async log to database
14. HTTP Response returned
```

---

## Appendix: Library Summary

| Library | Purpose | Hex | Status |
|---|---|---|---|
| **Hammer** | Rate limiting | `{:hammer, "~> 7.0"}` | Mature, active |
| **Hammer Plug** | Plug integration for Hammer | `{:hammer_plug, "~> 3.0"}` | Mature |
| **OpenApiSpex** | OpenAPI spec generation | `{:open_api_spex, "~> 3.16"}` | Mature, active |
| **Dune** | Code sandbox | `{:dune, "~> 0.3"}` | Active, small community |
| **Guardian** | JWT authentication | `{:guardian, "~> 2.0"}` | Mature, active |
| **Joken** | Lightweight JWT | `{:joken, "~> 2.6"}` | Mature |
| **SiteEncrypt** | Automatic Let's Encrypt | `{:site_encrypt, "~> 0.6"}` | Active |
| **ReverseProxyPlug** | Reverse proxy | `{:reverse_proxy_plug, "~> 3.0"}` | Mature |
| **Versionary** | API versioning plug | `{:versionary, "~> 0.4"}` | Stable, low activity |
| **PhoenixApiVersions** | Phoenix API versioning | `{:phoenix_api_versions, "~> 1.1"}` | Stable |
