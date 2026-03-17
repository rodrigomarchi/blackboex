# Discovery: Calling LLMs from Elixir

> **Date**: 2026-03-17
> **Context**: BlackBoex -- platform where users describe APIs in natural language, an LLM generates Elixir code, and users publish it as a REST endpoint.
> **Goal**: Choose the right library/architecture for LLM integration in an Elixir/Phoenix umbrella app.

---

## Table of Contents

1. [Ecosystem Overview](#1-ecosystem-overview)
2. [Library Comparison](#2-library-comparison)
3. [Multi-Provider Abstraction](#3-multi-provider-abstraction)
4. [Structured Output / Function Calling](#4-structured-output--function-calling)
5. [Streaming LLM Responses](#5-streaming-llm-responses)
6. [Token Management and Rate Limiting](#6-token-management-and-rate-limiting)
7. [Cost Tracking](#7-cost-tracking)
8. [Prompt Engineering for Elixir Code Generation](#8-prompt-engineering-for-elixir-code-generation)
9. [Architecture Recommendation for BlackBoex](#9-architecture-recommendation-for-blackboex)

---

## 1. Ecosystem Overview

The Elixir LLM ecosystem matured significantly in 2025-2026. There are now several production-quality options, ranging from thin HTTP wrappers to full-featured frameworks. The main contenders fall into three categories:

| Category | Libraries |
|---|---|
| **Unified multi-provider clients** | ReqLLM, LangChain, ExLLM (archived) |
| **Provider-specific clients** | openai_ex, anthropix, anthropic_community, gemini_ex, ollama, mistral |
| **Structured output** | instructor_ex, instructor_lite |

### Popularity Snapshot (March 2026)

| Library | GitHub Stars | Hex Downloads/week | Latest Version | Last Updated |
|---|---|---|---|---|
| **req_llm** | 473 | 45.9K | v1.7.1 | 2 days ago |
| **openai_ex** | 212 | 42.7K | v0.9.19 | 2 days ago |
| **langchain** | ~1.5K | moderate | v0.6.1 | active |
| **ollama** | 139 | 2.2K | v0.9.0 | 1 month ago |
| **anthropix** | 54 | 88.5K | v0.6.2 | 8 months ago |
| **ex_llm** | 50 | 316 | v0.8.1 | archived |
| **gemini_ex** | 28 | 3.2K | v0.11.0 | 11 days ago |
| **instructor_lite** | ~100 | moderate | active | active |
| **mistral** | 9 | 210 | v0.5.0 | 15 days ago |

---

## 2. Library Comparison

### 2.1 ReqLLM (Recommended Primary Client)

**GitHub**: https://github.com/agentjido/req_llm
**Hex**: https://hex.pm/packages/req_llm

ReqLLM is the most actively maintained and feature-complete multi-provider client. Built on top of Req (Elixir's modern HTTP client) and Finch, it provides a two-layer architecture:

- **High-level API** -- Vercel AI SDK-inspired functions: `generate_text/3`, `stream_text/3`, `generate_object/4`
- **Low-level Req plugin** -- Direct HTTP manipulation via provider callbacks

**Supported Providers (18):**
Anthropic, OpenAI, Google Gemini, Google Vertex AI, Amazon Bedrock, Azure OpenAI, Groq, xAI, OpenRouter, Cerebras, Meta Llama, Mistral, vLLM, Ollama, and more.

**Key Features:**
- Typed data structures (`Context`, `Message`, `Response`) -- proper structs, not nested maps
- Model registry with 665+ models via `llm_db` dependency (cost, context length, modality metadata)
- Built-in cost tracking with telemetry events
- Streaming via Finch with HTTP/2 multiplexing
- Tool/function calling
- Structured object generation with schema validation
- Multi-modal content (text, images, tool calls)
- API key management with layered precedence (per-request > in-memory > app config > env vars > .env)

**Installation:**

```elixir
# mix.exs
def deps do
  [{:req_llm, "~> 1.7"}]
end
```

**Usage Examples:**

```elixir
# Simple text generation
model = "anthropic:claude-sonnet-4-20250514"
{:ok, response} = ReqLLM.generate_text(model, "Explain pattern matching in Elixir")
IO.puts(response.content)

# Streaming
{:ok, stream_response} = ReqLLM.stream_text(
  model,
  ReqLLM.Context.new([
    ReqLLM.Context.system("You are an Elixir expert."),
    ReqLLM.Context.user("Write a Phoenix controller for user CRUD")
  ]),
  temperature: 0.2,
  max_tokens: 4096
)

# Consume tokens
stream_response
|> ReqLLM.StreamResponse.tokens()
|> Stream.each(&IO.write/1)
|> Stream.run()

# Get usage after streaming
usage = ReqLLM.StreamResponse.usage(stream_response)
# => %{input_tokens: 42, output_tokens: 380, total_cost: 0.0012}

# Structured object generation
schema = [
  module_name: [type: :string, required: true],
  functions: [type: {:list, :map}, required: true],
  dependencies: [type: {:list, :string}]
]
{:ok, spec} = ReqLLM.generate_object(model, "Generate a user authentication module", schema)

# Tool use
{:ok, response} = ReqLLM.generate_text(
  model,
  "What tables exist in the database?",
  tools: [
    ReqLLM.tool(
      name: "list_tables",
      description: "List all database tables",
      parameter_schema: [schema: [type: :string, required: true]],
      callback: {MyApp.DB, :list_tables, []}
    )
  ]
)

# API key management
ReqLLM.put_key(:anthropic_api_key, "sk-ant-...")
ReqLLM.put_key(:openai_api_key, "sk-...")

# Per-request override (useful for BYOK)
ReqLLM.generate_text(model, "Hello", api_key: "sk-user-provided-key")
```

**Why ReqLLM for BlackBoex:**
- Jose Valim endorsed it as "fantastic"
- Composable Req plugin architecture fits Elixir idioms
- Built-in cost tracking is critical for a platform billing users
- 130+ models pass fixture-based test suites
- Active maintenance with v1.7.1 released days ago
- Telemetry event `[:req_llm, :token_usage]` publishes metrics on every request

---

### 2.2 LangChain for Elixir

**GitHub**: https://github.com/brainlid/langchain
**Hex**: https://hex.pm/packages/langchain

LangChain is a higher-level framework (not just a client) that provides chains, function calling, and message management.

**Supported Providers:**
OpenAI, Anthropic Claude, xAI Grok, Google Gemini/Vertex AI, Mistral, Perplexity, Ollama, Bumblebee (local), LMStudio.

**Key Features:**
- `LLMChain` -- central orchestration module for multi-step LLM workflows
- `LangChain.Function` -- expose Elixir functions to LLMs with context-aware execution
- Multi-modal messages (text, images, files, thinking blocks via `ContentPart`)
- Prompt caching (automatic for GPT; configurable for Claude)
- `LangChain.Trajectory` -- captures tool call sequences for evaluating agent reasoning
- Streaming responses

**Usage Example:**

```elixir
alias LangChain.ChatModels.ChatAnthropic
alias LangChain.Chains.LLMChain
alias LangChain.Message
alias LangChain.Function

# Define a tool the LLM can call
get_schema = Function.new!(%{
  name: "get_db_schema",
  description: "Returns the database schema as SQL DDL",
  function: fn _args, _context ->
    {:ok, Jason.encode!(MyApp.Schema.to_ddl())}
  end
})

# Run a chain with tool use
{:ok, chain} =
  %{llm: ChatAnthropic.new!(%{model: "claude-sonnet-4-20250514"})}
  |> LLMChain.new!()
  |> LLMChain.add_message(Message.new_system!("You generate Elixir Phoenix code."))
  |> LLMChain.add_message(Message.new_user!("Create a REST endpoint for user registration"))
  |> LLMChain.add_tools([get_schema])
  |> LLMChain.run(mode: :while_needs_response)

IO.puts(chain.last_message.content)
```

**When to consider LangChain over ReqLLM:**
- You need chain-of-thought orchestration or multi-step agents
- You need built-in OpenTelemetry tracing
- You want a higher-level abstraction that manages conversation state

**When NOT to use LangChain:**
- For simple generate-text / generate-object calls (too heavy)
- When you need fine-grained control over HTTP requests
- When you want to avoid framework lock-in

---

### 2.3 Provider-Specific Clients

These are useful if you want maximum control or only need one provider.

#### Anthropix (Anthropic/Claude)

```elixir
# mix.exs
{:anthropix, "~> 0.6"}

# Usage
client = Anthropix.init("sk-ant-...")
{:ok, response} = Anthropix.chat(client, [
  model: "claude-sonnet-4-20250514",
  messages: [%{role: "user", content: "Hello"}]
])

# Streaming
{:ok, stream} = Anthropix.chat(client, [
  model: "claude-sonnet-4-20250514",
  messages: messages,
  stream: true
])
stream |> Stream.each(&handle_chunk/1) |> Stream.run()
```

Features: full Anthropic API, tool use, extended thinking, prompt caching, batch processing, streaming.

#### anthropic_community

```elixir
{:anthropic_community, "~> 0.4"}

{:ok, response, _req} =
  Anthropic.new(max_tokens: 500, api_key: "API_KEY")
  |> Anthropic.add_user_message("Hello!")
  |> Anthropic.request_next_message()
```

Features: tool invocation via `ToolBehaviour`, telemetry integration, image content support.

#### openai_ex

```elixir
{:openai_ex, "~> 0.9"}
```

Community-maintained, 212 stars, 42.7K downloads/week. Solid choice for OpenAI-only usage.

#### gemini_ex

```elixir
{:gemini_ex, "~> 0.11"}
```

Google Gemini client with streaming and telemetry. 28 stars, actively maintained.

#### ollama (local models)

```elixir
{:ollama, "~> 0.9"}
```

Client for Ollama local LLM server. 139 stars. Useful for development/testing without API costs.

---

## 3. Multi-Provider Abstraction

### 3.1 The Problem

BlackBoex needs to support multiple LLM providers because:
- Different models have different strengths for code generation
- Users may want to choose their provider
- Provider outages require fallback capability
- Cost optimization requires routing to cheaper models for simple tasks

### 3.2 Abstraction Approaches

#### Approach A: ReqLLM as Unified Client (Recommended)

ReqLLM already provides a unified interface across 18 providers. The model string format `"provider:model-name"` makes switching trivial:

```elixir
defmodule Blackboex.LLM do
  @doc "Generate code from a natural language description."
  @spec generate_code(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def generate_code(prompt, opts \\ []) do
    model = Keyword.get(opts, :model, default_model())

    ReqLLM.generate_text(
      model,
      ReqLLM.Context.new([
        ReqLLM.Context.system(system_prompt()),
        ReqLLM.Context.user(prompt)
      ]),
      temperature: 0.2,
      max_tokens: 8192
    )
  end

  defp default_model do
    Application.get_env(:blackboex, :default_llm_model, "anthropic:claude-sonnet-4-20250514")
  end
end
```

Switching providers is just changing the model string -- no code changes needed.

#### Approach B: Custom Behaviour-Based Abstraction

If you want full control without depending on ReqLLM's abstraction:

```elixir
defmodule Blackboex.LLM.Provider do
  @callback chat(messages :: list(), opts :: keyword()) ::
    {:ok, Blackboex.LLM.Response.t()} | {:error, term()}

  @callback stream(messages :: list(), opts :: keyword()) ::
    {:ok, Enumerable.t()} | {:error, term()}

  @callback models() :: [String.t()]
end

defmodule Blackboex.LLM.Provider.Anthropic do
  @behaviour Blackboex.LLM.Provider
  # Implement using anthropix or raw Req calls
end

defmodule Blackboex.LLM.Provider.OpenAI do
  @behaviour Blackboex.LLM.Provider
  # Implement using openai_ex or raw Req calls
end
```

#### Approach C: LangChain as Orchestrator

Use LangChain when you need multi-step workflows (e.g., generate code -> validate -> fix errors -> return):

```elixir
# LangChain abstracts provider differences at the ChatModel level
llm = case provider do
  :anthropic -> ChatAnthropic.new!(%{model: "claude-sonnet-4-20250514"})
  :openai    -> ChatOpenAI.new!(%{model: "gpt-4o"})
  :gemini    -> ChatGoogleAI.new!(%{model: "gemini-pro"})
end

{:ok, chain} =
  %{llm: llm}
  |> LLMChain.new!()
  |> LLMChain.add_messages(messages)
  |> LLMChain.run()
```

### 3.3 Provider Fallback Pattern

```elixir
defmodule Blackboex.LLM.Router do
  @providers [
    "anthropic:claude-sonnet-4-20250514",
    "openai:gpt-4o",
    "google:gemini-2.0-flash"
  ]

  @spec generate_with_fallback(String.t(), keyword()) :: {:ok, term()} | {:error, term()}
  def generate_with_fallback(prompt, opts \\ []) do
    models = Keyword.get(opts, :models, @providers)

    Enum.reduce_while(models, {:error, :all_providers_failed}, fn model, _acc ->
      case Blackboex.LLM.generate_code(prompt, Keyword.put(opts, :model, model)) do
        {:ok, response} -> {:halt, {:ok, response}}
        {:error, reason} ->
          Logger.warning("Provider #{model} failed: #{inspect(reason)}")
          {:cont, {:error, :all_providers_failed}}
      end
    end)
  end
end
```

---

## 4. Structured Output / Function Calling

### 4.1 Why Structured Output Matters for BlackBoex

BlackBoex generates Elixir code from natural language. We need the LLM to return:
- Valid Elixir module code
- Metadata (module name, dependencies, route definitions)
- Structured error information when generation fails

Raw text output is fragile. Structured output with validation dramatically improves reliability.

### 4.2 instructor_lite (Recommended for Structured Output)

**GitHub**: https://github.com/martosaur/instructor_lite

InstructorLite is a "lean, composable, magic-free" rewrite of instructor_ex. It uses Ecto schemas for defining expected output structures and validates responses with changesets.

**Tested compatibility:** OpenAI, Anthropic, Google Gemini, Grok, Llamacpp.

**How it works:**
1. Define an Ecto embedded schema with field descriptions
2. InstructorLite generates a JSON schema from the Ecto schema
3. The LLM is prompted to return JSON matching the schema
4. The response is validated through Ecto changesets
5. On validation failure, the error is sent back to the LLM for retry

```elixir
defmodule Blackboex.LLM.Schemas.GeneratedEndpoint do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :module_name, :string
    field :module_code, :string
    field :route_path, :string
    field :http_method, Ecto.Enum, values: [:get, :post, :put, :patch, :delete]
    field :description, :string
    field :dependencies, {:array, :string}, default: []
    field :confidence_score, :float
  end

  def changeset(schema, params) do
    schema
    |> cast(params, [:module_name, :module_code, :route_path, :http_method,
                     :description, :dependencies, :confidence_score])
    |> validate_required([:module_name, :module_code, :route_path, :http_method])
    |> validate_format(:module_name, ~r/^[A-Z][A-Za-z0-9.]+$/)
    |> validate_format(:route_path, ~r/^\//)
    |> validate_number(:confidence_score,
        greater_than_or_equal_to: 0.0,
        less_than_or_equal_to: 1.0)
    |> validate_elixir_syntax(:module_code)
  end

  defp validate_elixir_syntax(changeset, field) do
    case get_change(changeset, field) do
      nil -> changeset
      code ->
        case Code.string_to_quoted(code) do
          {:ok, _ast} -> changeset
          {:error, _} -> add_error(changeset, field, "contains invalid Elixir syntax")
        end
    end
  end
end
```

**Key design choice:** InstructorLite intentionally does NOT provide a unified provider interface or streaming support. It focuses solely on getting structured data out of LLMs. This is a feature, not a limitation -- it composes well with ReqLLM or any HTTP client.

### 4.3 instructor_ex (Original)

**GitHub**: https://github.com/thmsmlr/instructor_ex

The original Instructor for Elixir. Supports OpenAI, Anthropic, Groq, Ollama, Gemini, vLLM, llama.cpp.

```elixir
defmodule SpamPrediction do
  use Ecto.Schema
  use Instructor

  @llm_doc """
  ## Field Descriptions:
  - class: Whether or not the email is spam.
  - reason: A short, less than 10 word rationalization.
  - score: A confidence score between 0.0 and 1.0.
  """

  @primary_key false
  embedded_schema do
    field :class, Ecto.Enum, values: [:spam, :not_spam]
    field :reason, :string
    field :score, :float
  end

  def validate_changeset(changeset) do
    changeset
    |> Ecto.Changeset.validate_number(:score,
        greater_than_or_equal_to: 0.0,
        less_than_or_equal_to: 1.0)
  end
end

# Usage
Instructor.chat_completion(%{
  model: "gpt-4o",
  response_model: SpamPrediction,
  messages: [%{role: "user", content: "Classify: 'You won a free iPhone!'"}],
  max_retries: 3
})
# => {:ok, %SpamPrediction{class: :spam, reason: "Prize scam pattern", score: 0.95}}
```

### 4.4 ReqLLM's Built-in generate_object

ReqLLM has its own structured output support via `generate_object/4`:

```elixir
schema = [
  module_name: [type: :string, required: true],
  route_path: [type: :string, required: true],
  http_method: [type: :string, required: true, enum: ["get", "post", "put", "delete"]],
  code: [type: :string, required: true]
]

{:ok, result} = ReqLLM.generate_object(
  "anthropic:claude-sonnet-4-20250514",
  "Generate a user registration endpoint",
  schema
)
# => %{module_name: "UserRegistration", route_path: "/api/register", ...}
```

This is simpler than Instructor but lacks Ecto changeset validation. For BlackBoex, combining ReqLLM for the HTTP layer with InstructorLite for validation may be the best approach.

### 4.5 Comparison: Structured Output Options

| Feature | instructor_lite | instructor_ex | ReqLLM generate_object |
|---|---|---|---|
| Ecto schema validation | Yes | Yes | No (plain maps) |
| Custom changeset rules | Yes | Yes | No |
| Auto-retry on validation fail | Yes | Yes | No |
| Syntax validation | Via changeset | Via changeset | Manual |
| Provider agnostic | Yes (adapters) | Yes | Yes (built-in) |
| Streaming | No (by design) | No | N/A |
| Magic-free / composable | Yes | Moderate | Yes |

**Recommendation:** Use InstructorLite for the code generation pipeline where validation is critical. Use ReqLLM's `generate_object` for simpler structured outputs (metadata, classifications).

---

## 5. Streaming LLM Responses

### 5.1 Why Streaming Matters for BlackBoex

Code generation can take 5-30 seconds. Without streaming, users stare at a spinner. With streaming, they see the code appear token-by-token, dramatically improving perceived performance.

### 5.2 Streaming with ReqLLM

ReqLLM provides first-class streaming via Finch:

```elixir
{:ok, stream_response} = ReqLLM.stream_text(
  "anthropic:claude-sonnet-4-20250514",
  context,
  temperature: 0.2,
  max_tokens: 8192
)

# Consume as a stream
stream_response
|> ReqLLM.StreamResponse.tokens()
|> Stream.each(fn token -> send(liveview_pid, {:llm_token, token}) end)
|> Stream.run()

# Usage data available after stream completes
usage = ReqLLM.StreamResponse.usage(stream_response)
```

### 5.3 Streaming in Phoenix LiveView

The canonical pattern uses two processes: the LiveView process and an async Task that handles the HTTP streaming.

```elixir
defmodule BlackboexWeb.GenerateLive do
  use BlackboexWeb, :live_view

  def mount(_params, _session, socket) do
    {:ok, assign(socket, generated_code: "", generating: false, error: nil)}
  end

  def handle_event("generate", %{"prompt" => prompt}, socket) do
    # Spawn an async task to stream from the LLM
    liveview_pid = self()

    Task.start(fn ->
      case ReqLLM.stream_text(
        "anthropic:claude-sonnet-4-20250514",
        ReqLLM.Context.new([
          ReqLLM.Context.system(Blackboex.LLM.Prompts.code_generation()),
          ReqLLM.Context.user(prompt)
        ]),
        temperature: 0.2,
        max_tokens: 8192
      ) do
        {:ok, stream_response} ->
          stream_response
          |> ReqLLM.StreamResponse.tokens()
          |> Stream.each(fn token ->
            send(liveview_pid, {:llm_token, token})
          end)
          |> Stream.run()

          usage = ReqLLM.StreamResponse.usage(stream_response)
          send(liveview_pid, {:llm_done, usage})

        {:error, reason} ->
          send(liveview_pid, {:llm_error, reason})
      end
    end)

    {:noreply, assign(socket, generating: true, generated_code: "")}
  end

  def handle_info({:llm_token, token}, socket) do
    {:noreply, update(socket, :generated_code, &(&1 <> token))}
  end

  def handle_info({:llm_done, usage}, socket) do
    # Track usage/costs
    Blackboex.Usage.track(socket.assigns.current_user, usage)
    {:noreply, assign(socket, generating: false)}
  end

  def handle_info({:llm_error, reason}, socket) do
    {:noreply, assign(socket, generating: false, error: inspect(reason))}
  end
end
```

### 5.4 Streaming with Anthropix

```elixir
client = Anthropix.init(api_key)

{:ok, stream} = Anthropix.chat(client, [
  model: "claude-sonnet-4-20250514",
  messages: [%{role: "user", content: prompt}],
  stream: true
])

stream
|> Stream.each(fn chunk ->
  send(liveview_pid, {:llm_token, extract_text(chunk)})
end)
|> Stream.run()
```

### 5.5 SSE for External REST Consumers

If BlackBoex also exposes generated code streaming to external clients (not just LiveView), use Server-Sent Events:

```elixir
defmodule BlackboexWeb.API.GenerateController do
  use BlackboexWeb, :controller

  def stream_generate(conn, %{"prompt" => prompt}) do
    conn =
      conn
      |> put_resp_content_type("text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> send_chunked(200)

    {:ok, stream_response} = ReqLLM.stream_text(model(), build_context(prompt))

    stream_response
    |> ReqLLM.StreamResponse.tokens()
    |> Enum.reduce_while(conn, fn token, conn ->
      case chunk(conn, "data: #{Jason.encode!(%{token: token})}\n\n") do
        {:ok, conn} -> {:cont, conn}
        {:error, _} -> {:halt, conn}
      end
    end)
  end
end
```

---

## 6. Token Management and Rate Limiting

### 6.1 API Key Management

ReqLLM provides layered key resolution: per-request > in-memory > app config > env vars > .env files.

```elixir
# config/runtime.exs
config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  google_api_key: System.get_env("GOOGLE_API_KEY")
```

For BYOK (Bring Your Own Key) scenarios where users provide their own API keys:

```elixir
ReqLLM.generate_text(model, prompt, api_key: user.encrypted_api_key |> decrypt())
```

### 6.2 Rate Limiting with GenServer

LLM APIs have strict rate limits (requests/minute, tokens/minute). Elixir's GenServer + token bucket pattern is ideal:

**Option A: Use ExRated (battle-tested library)**

```elixir
# mix.exs
{:ex_rated, "~> 2.1"}

# Rate limit per provider
defmodule Blackboex.LLM.RateLimiter do
  @limits %{
    anthropic: {60, 60_000},    # 60 requests per 60 seconds
    openai: {500, 60_000},       # 500 requests per 60 seconds
    google: {360, 60_000}        # 360 requests per 60 seconds
  }

  @spec check_rate(atom()) :: :ok | {:error, :rate_limited}
  def check_rate(provider) do
    {limit, window} = Map.fetch!(@limits, provider)
    bucket = "llm:#{provider}"

    case ExRated.check_rate(bucket, window, limit) do
      {:ok, _count} -> :ok
      {:error, _limit} -> {:error, :rate_limited}
    end
  end
end
```

**Option B: Custom GenServer with queue (for token-level limiting)**

```elixir
defmodule Blackboex.LLM.TokenBudget do
  use GenServer

  defstruct [:provider, :tokens_remaining, :reset_at, :queue]

  def start_link(opts) do
    provider = Keyword.fetch!(opts, :provider)
    GenServer.start_link(__MODULE__, opts, name: via(provider))
  end

  def request_tokens(provider, estimated_tokens) do
    GenServer.call(via(provider), {:request, estimated_tokens}, 30_000)
  end

  def report_usage(provider, actual_tokens) do
    GenServer.cast(via(provider), {:usage, actual_tokens})
  end

  @impl true
  def init(opts) do
    provider = Keyword.fetch!(opts, :provider)
    budget = Keyword.get(opts, :tokens_per_minute, 1_000_000)
    schedule_reset()
    {:ok, %__MODULE__{
      provider: provider,
      tokens_remaining: budget,
      reset_at: DateTime.utc_now() |> DateTime.add(60, :second),
      queue: :queue.new()
    }}
  end

  @impl true
  def handle_call({:request, estimated}, from, state) do
    if estimated <= state.tokens_remaining do
      {:reply, :ok, %{state | tokens_remaining: state.tokens_remaining - estimated}}
    else
      queue = :queue.in({from, estimated}, state.queue)
      {:noreply, %{state | queue: queue}}
    end
  end

  @impl true
  def handle_info(:reset, state) do
    schedule_reset()
    new_state = %{state |
      tokens_remaining: initial_budget(state.provider),
      reset_at: DateTime.utc_now() |> DateTime.add(60, :second)
    }
    drain_queue(new_state)
  end

  defp schedule_reset, do: Process.send_after(self(), :reset, 60_000)
  defp via(provider), do: {:via, Registry, {Blackboex.LLM.Registry, provider}}
end
```

### 6.3 Per-User Rate Limiting

Beyond provider limits, BlackBoex should limit per-user to prevent abuse:

```elixir
defmodule Blackboex.LLM.UserLimiter do
  @user_limits %{
    free: {10, 3_600_000},      # 10 requests per hour
    pro: {100, 3_600_000},       # 100 requests per hour
    enterprise: {1000, 3_600_000} # 1000 requests per hour
  }

  @spec check_user_rate(User.t()) :: :ok | {:error, :rate_limited}
  def check_user_rate(user) do
    {limit, window} = Map.fetch!(@user_limits, user.plan)
    bucket = "user:#{user.id}:llm"

    case ExRated.check_rate(bucket, window, limit) do
      {:ok, _} -> :ok
      {:error, _} -> {:error, :rate_limited}
    end
  end
end
```

---

## 7. Cost Tracking

### 7.1 ReqLLM Built-in Cost Tracking

Every ReqLLM response includes usage metadata:

```elixir
{:ok, response} = ReqLLM.generate_text(model, prompt)

response.usage
# => %{
#   input_tokens: 150,
#   output_tokens: 2048,
#   total_tokens: 2198,
#   input_cost: 0.00045,    # USD
#   output_cost: 0.03072,   # USD
#   total_cost: 0.03117     # USD
# }
```

ReqLLM emits a telemetry event `[:req_llm, :token_usage]` on every request, which can be hooked into for centralized tracking.

### 7.2 Persisting Usage Data

```elixir
# Migration
defmodule Blackboex.Repo.Migrations.CreateLlmUsage do
  use Ecto.Migration

  def change do
    create table(:llm_usage) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :provider, :string, null: false
      add :model, :string, null: false
      add :input_tokens, :integer, null: false
      add :output_tokens, :integer, null: false
      add :total_cost_cents, :integer, null: false  # stored as integer cents to avoid float issues
      add :request_type, :string  # "code_generation", "code_fix", "description"
      add :endpoint_id, references(:endpoints, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:llm_usage, [:user_id])
    create index(:llm_usage, [:provider, :model])
    create index(:llm_usage, [:inserted_at])
  end
end

# Schema
defmodule Blackboex.Billing.LlmUsage do
  use Ecto.Schema

  schema "llm_usage" do
    belongs_to :user, Blackboex.Accounts.User
    belongs_to :endpoint, Blackboex.Endpoints.Endpoint

    field :provider, :string
    field :model, :string
    field :input_tokens, :integer
    field :output_tokens, :integer
    field :total_cost_cents, :integer
    field :request_type, :string

    timestamps(type: :utc_datetime)
  end
end

# Telemetry handler
defmodule Blackboex.Billing.TelemetryHandler do
  def handle_event([:req_llm, :token_usage], measurements, metadata, _config) do
    %{
      user_id: metadata[:user_id],
      provider: metadata[:provider],
      model: metadata[:model],
      input_tokens: measurements.input_tokens,
      output_tokens: measurements.output_tokens,
      total_cost_cents: round(measurements.total_cost * 100),
      request_type: metadata[:request_type]
    }
    |> Blackboex.Billing.create_llm_usage()
  end
end
```

### 7.3 Cost Dashboard Queries

```elixir
defmodule Blackboex.Billing do
  import Ecto.Query

  @spec monthly_cost(User.t()) :: float()
  def monthly_cost(user) do
    from(u in LlmUsage,
      where: u.user_id == ^user.id,
      where: u.inserted_at >= ^beginning_of_month(),
      select: sum(u.total_cost_cents)
    )
    |> Repo.one()
    |> Kernel.||(0)
    |> Kernel./(100)
  end

  @spec cost_by_provider(User.t()) :: [%{provider: String.t(), cost: float()}]
  def cost_by_provider(user) do
    from(u in LlmUsage,
      where: u.user_id == ^user.id,
      where: u.inserted_at >= ^beginning_of_month(),
      group_by: u.provider,
      select: %{provider: u.provider, cost: sum(u.total_cost_cents)}
    )
    |> Repo.all()
  end
end
```

### 7.4 Model Pricing Reference (as of March 2026)

| Provider | Model | Input ($/1M tokens) | Output ($/1M tokens) |
|---|---|---|---|
| Anthropic | Claude Sonnet 4 | $3.00 | $15.00 |
| Anthropic | Claude Haiku 3.5 | $0.80 | $4.00 |
| OpenAI | GPT-4o | $2.50 | $10.00 |
| OpenAI | GPT-4o-mini | $0.15 | $0.60 |
| Google | Gemini 2.0 Flash | $0.075 | $0.30 |
| Google | Gemini 2.0 Pro | $1.25 | $5.00 |
| Groq | Llama 3 70B | $0.59 | $0.79 |

> Note: Prices change frequently. ReqLLM's `llm_db` dependency maintains up-to-date pricing metadata for 665+ models.

---

## 8. Prompt Engineering for Elixir Code Generation

### 8.1 System Prompt Design

The system prompt is the most critical piece for BlackBoex. It must instruct the LLM to generate valid, idiomatic Elixir code.

```elixir
defmodule Blackboex.LLM.Prompts do
  @spec code_generation() :: String.t()
  def code_generation do
    """
    You are an expert Elixir developer specializing in Phoenix Framework.
    You generate production-quality Elixir modules that implement REST API endpoints.

    ## Rules

    1. Generate a single Elixir module that implements a Phoenix controller.
    2. Use Phoenix 1.8+ conventions (verified routes, Bandit server).
    3. All public functions MUST have @spec type annotations.
    4. Use pattern matching extensively.
    5. Handle errors with {:ok, _} / {:error, _} tuples.
    6. Never use external dependencies beyond what Phoenix provides (Ecto, Jason, Plug).
    7. Include @moduledoc and @doc annotations.
    8. Follow `mix format` conventions.

    ## Output Format

    Return ONLY the Elixir module code, wrapped in a single ```elixir code block.
    Do not include explanations, comments outside the module, or multiple files.

    ## Module Structure

    The module must:
    - Be namespaced under BlackboexWeb.Generated.*
    - Define a single `call/2` function that takes `conn` and `params`
    - Return a JSON response using `json(conn, result)`
    - Handle errors gracefully and return appropriate HTTP status codes

    ## Example

    ```elixir
    defmodule BlackboexWeb.Generated.WeatherForecast do
      @moduledoc "Returns a weather forecast for the given city."

      use BlackboexWeb, :controller

      @spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
      def call(conn, %{"city" => city}) do
        forecast = generate_forecast(city)
        json(conn, %{city: city, forecast: forecast})
      end

      def call(conn, _params) do
        conn
        |> put_status(:bad_request)
        |> json(%{error: "Missing required parameter: city"})
      end

      defp generate_forecast(city) do
        # Implementation here
        %{temperature: 22, condition: "sunny", city: city}
      end
    end
    ```
    """
  end
end
```

### 8.2 Few-Shot Prompting Strategy

Include 2-3 examples in the prompt that match the complexity level of the request:

```elixir
defmodule Blackboex.LLM.Prompts.Examples do
  @spec for_complexity(:simple | :moderate | :complex) :: String.t()
  def for_complexity(:simple) do
    """
    ## Example: Simple endpoint
    User: "An endpoint that returns the current server time"
    Generated:
    ```elixir
    defmodule BlackboexWeb.Generated.ServerTime do
      use BlackboexWeb, :controller

      @spec call(Plug.Conn.t(), map()) :: Plug.Conn.t()
      def call(conn, _params) do
        now = DateTime.utc_now()
        json(conn, %{utc: DateTime.to_iso8601(now), unix: DateTime.to_unix(now)})
      end
    end
    ```
    """
  end

  def for_complexity(:moderate) do
    # Example with query params, validation, error handling
  end

  def for_complexity(:complex) do
    # Example with Ecto queries, multi-step logic
  end
end
```

### 8.3 Prompt Chaining for Reliable Code Generation

For BlackBoex, a single LLM call is often not enough. A chain approach improves quality:

```
Step 1: Understand  -> LLM analyzes the user's description, outputs structured spec
Step 2: Generate    -> LLM generates code based on the spec
Step 3: Validate    -> Code.string_to_quoted() checks syntax; optionally compile in sandbox
Step 4: Fix (if needed) -> Send errors back to LLM for correction (max 3 retries)
```

```elixir
defmodule Blackboex.LLM.Pipeline do
  @max_retries 3

  @spec generate_endpoint(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def generate_endpoint(description, opts \\ []) do
    model = Keyword.get(opts, :model, "anthropic:claude-sonnet-4-20250514")

    with {:ok, spec} <- understand(description, model),
         {:ok, code} <- generate(spec, model),
         {:ok, validated} <- validate_and_fix(code, spec, model, 0) do
      {:ok, %{spec: spec, code: validated}}
    end
  end

  defp understand(description, model) do
    ReqLLM.generate_object(model, """
    Analyze this API endpoint description and extract a structured specification:
    #{description}
    """, [
      endpoint_name: [type: :string, required: true],
      http_method: [type: :string, required: true],
      route_path: [type: :string, required: true],
      parameters: [type: {:list, :map}],
      description: [type: :string, required: true]
    ])
  end

  defp generate(spec, model) do
    ReqLLM.generate_text(model, """
    #{Blackboex.LLM.Prompts.code_generation()}

    Generate an endpoint based on this specification:
    #{Jason.encode!(spec, pretty: true)}
    """)
  end

  defp validate_and_fix(_code, _spec, _model, @max_retries) do
    {:error, :max_retries_exceeded}
  end

  defp validate_and_fix(code, spec, model, attempt) do
    extracted = extract_code_block(code)

    case Code.string_to_quoted(extracted) do
      {:ok, _ast} ->
        {:ok, extracted}

      {:error, {line, message, token}} ->
        error_msg = "Syntax error at line #{line}: #{message} (near #{token})"

        {:ok, fixed} = ReqLLM.generate_text(model, """
        The following Elixir code has a syntax error:
        ```elixir
        #{extracted}
        ```

        Error: #{error_msg}

        Fix the error and return the corrected complete module.
        """)

        validate_and_fix(fixed, spec, model, attempt + 1)
    end
  end

  defp extract_code_block(text) do
    case Regex.run(~r/```elixir\n(.*?)```/s, text) do
      [_, code] -> String.trim(code)
      nil -> String.trim(text)
    end
  end
end
```

### 8.4 Model Selection for Code Generation

Based on community benchmarks for Elixir code generation:

| Model | Quality | Speed | Cost | Best For |
|---|---|---|---|---|
| Claude Sonnet 4 | Excellent | Moderate | $$ | Primary code generation |
| Claude Haiku 3.5 | Good | Fast | $ | Simple endpoints, validation |
| GPT-4o | Excellent | Moderate | $$ | Alternative primary |
| GPT-4o-mini | Good | Fast | $ | Simple tasks, classification |
| Gemini 2.0 Flash | Good | Very Fast | $ | High-throughput, simple tasks |
| Llama 3 70B (Groq) | Good | Very Fast | $ | Cost-sensitive, privacy |

**Recommendation:** Default to Claude Sonnet 4 for code generation (best Elixir understanding), fall back to GPT-4o, and use Haiku/Flash for metadata extraction and simple tasks.

---

## 9. Architecture Recommendation for BlackBoex

### 9.1 Recommended Stack

| Layer | Choice | Rationale |
|---|---|---|
| **HTTP Client** | ReqLLM v1.7+ | Unified multi-provider, cost tracking, streaming, active maintenance |
| **Structured Output** | InstructorLite | Ecto-native validation, composable, magic-free |
| **Rate Limiting** | ExRated + custom GenServer | Provider-level + user-level rate limiting |
| **Streaming** | ReqLLM.stream_text + LiveView | Token-by-token streaming to LiveView |
| **Cost Tracking** | ReqLLM telemetry + Ecto | Persist per-request usage for billing |
| **Orchestration** | Custom pipeline (not LangChain) | BlackBoex's flow is specific; LangChain adds unnecessary complexity |

### 9.2 Module Architecture

```
apps/blackboex/lib/blackboex/
  llm/
    llm.ex                    # Public API facade
    pipeline.ex               # Multi-step code generation pipeline
    prompts.ex                # System prompts and examples
    prompts/
      code_generation.ex      # Code gen system prompt
      examples.ex             # Few-shot examples
    schemas/
      generated_endpoint.ex   # Ecto schema for structured output
      endpoint_spec.ex        # Specification schema
    router.ex                 # Provider fallback and routing
    rate_limiter.ex           # Per-provider rate limiting
    user_limiter.ex           # Per-user rate limiting
    config.ex                 # Provider configuration
  billing/
    llm_usage.ex              # Usage tracking schema
    telemetry_handler.ex      # Telemetry event handler
    billing.ex                # Cost queries and billing logic
```

### 9.3 Dependencies to Add

```elixir
# apps/blackboex/mix.exs
defp deps do
  [
    {:req_llm, "~> 1.7"},            # Multi-provider LLM client
    {:instructor_lite, "~> 0.4"},     # Structured output with Ecto validation
    {:ex_rated, "~> 2.1"},           # Rate limiting
    # ... existing deps
  ]
end
```

### 9.4 Configuration

```elixir
# config/runtime.exs
config :req_llm,
  anthropic_api_key: System.get_env("ANTHROPIC_API_KEY"),
  openai_api_key: System.get_env("OPENAI_API_KEY"),
  google_api_key: System.get_env("GOOGLE_API_KEY")

config :blackboex, Blackboex.LLM,
  default_model: "anthropic:claude-sonnet-4-20250514",
  fallback_models: [
    "openai:gpt-4o",
    "google:gemini-2.0-flash"
  ],
  max_retries: 3,
  max_tokens: 8192
```

### 9.5 Decision Log

| Decision | Choice | Alternatives Considered | Rationale |
|---|---|---|---|
| Primary LLM client | ReqLLM | LangChain, raw Req, ExLLM | Best balance of features, composability, and active maintenance. Jose Valim endorsed. |
| Structured output | InstructorLite | instructor_ex, ReqLLM generate_object | Lean, composable, Ecto-native. instructor_ex has more magic; ReqLLM's generate_object lacks validation. |
| NOT using LangChain | -- | LangChain | BlackBoex's pipeline is specific. LangChain's chain abstraction adds complexity without clear benefit. Could revisit if we need agentic workflows later. |
| NOT using ExLLM | -- | ExLLM | Archived; maintainer recommends ReqLLM instead. |
| Rate limiting | ExRated | Custom GenServer, Hammer | ExRated is battle-tested, simple API, GenServer-based. |

---

## Sources

- [ReqLLM GitHub](https://github.com/agentjido/req_llm)
- [ReqLLM Hex.pm](https://hex.pm/packages/req_llm)
- [ReqLLM v1.7.1 Documentation](https://hexdocs.pm/req_llm/)
- [ReqLLM Forum Discussion](https://elixirforum.com/t/reqllm-composable-llm-client-built-on-req/72514)
- [LangChain for Elixir GitHub](https://github.com/brainlid/langchain)
- [LangChain Hex.pm](https://hex.pm/packages/langchain)
- [LangChain Custom Functions](https://hexdocs.pm/langchain/custom_functions.html)
- [Announcing LangChain for Elixir (Fly.io)](https://fly.io/phoenix-files/announcing-langchain-for-elixir/)
- [instructor_ex GitHub](https://github.com/thmsmlr/instructor_ex)
- [InstructorLite GitHub](https://github.com/martosaur/instructor_lite)
- [InstructorLite Forum](https://elixirforum.com/t/instructorlite-structured-outputs-for-llms-a-tinkering-friendly-fork-of-instructor/65898)
- [Anthropix GitHub](https://github.com/lebrunel/anthropix)
- [Anthropix Hex Docs](https://hexdocs.pm/anthropix/Anthropix.html)
- [anthropic_community Hex Docs](https://hexdocs.pm/anthropic_community/Anthropic.html)
- [ExLLM GitHub](https://github.com/azmaveth/ex_llm)
- [Elixir LLM Toolbox Comparison](https://elixir-toolbox.dev/projects/ai/llm_clients)
- [Streaming OpenAI in Phoenix (Fly.io)](https://fly.io/phoenix-files/streaming-openai-responses/)
- [Streaming OpenAI in Phoenix (Ben Reinhart)](https://benreinhart.com/blog/openai-streaming-elixir-phoenix/)
- [AI-powered App with Phoenix LiveView (Dev.to)](https://dev.to/azyzz/ai-powered-app-with-llms-with-elixir-phoenix-liveview-and-togetherai-4ei1)
- [Phoenix SSE Blog](https://blog.jebelev.com/posts/phoenix-pubsub-sse/)
- [ExRated Hex Docs](https://hexdocs.pm/ex_rated/ExRated.html)
- [Rate Limiting with GenServers (Alex Koutmos)](https://akoutmos.com/post/rate-limiting-with-genservers/)
- [GenServer Rate Limiting for LLM APIs (Dev.to)](https://dev.to/darnahsan/leveraging-genserver-and-queueing-techniques-handling-api-rate-limits-to-ai-inference-services-3i68)
- [Awesome ML/Gen-AI Elixir](https://github.com/georgeguimaraes/awesome-ml-gen-ai-elixir)
