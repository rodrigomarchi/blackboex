# 07 - Observability: Plena Observabilidade para BlackBoex

> **Objetivo**: Definir a arquitetura de observabilidade completa (metrics, logs, traces, dashboards) para a plataforma BlackBoex, onde usuarios descrevem APIs em linguagem natural, um LLM gera o codigo Elixir, e publicam como endpoints REST.

---

## Indice

1. [Visao Geral da Arquitetura](#1-visao-geral-da-arquitetura)
2. [OpenTelemetry no Elixir](#2-opentelemetry-no-elixir)
3. [Metricas com PromEx e Telemetry](#3-metricas-com-promex-e-telemetry)
4. [Logging Estruturado](#4-logging-estruturado)
5. [Dashboards e Visualizacao](#5-dashboards-e-visualizacao)
6. [APM e Error Tracking](#6-apm-e-error-tracking)
7. [Observabilidade Per-API (Multi-Tenant)](#7-observabilidade-per-api-multi-tenant)
8. [Health Checks e Alerting](#8-health-checks-e-alerting)
9. [Observabilidade de LLM](#9-observabilidade-de-llm)
10. [Observabilidade da BEAM VM](#10-observabilidade-da-beam-vm)
11. [Stack Recomendada](#11-stack-recomendada)
12. [Plano de Implementacao](#12-plano-de-implementacao)

---

## 1. Visao Geral da Arquitetura

### Os Tres Pilares + Bonus

| Pilar | Ferramenta | Funcao |
|-------|-----------|--------|
| **Traces** | OpenTelemetry -> Grafana Tempo | Tracing distribuido de requests, queries, LLM calls |
| **Metrics** | PromEx -> Prometheus -> Grafana | Metricas de negocio, performance, BEAM VM |
| **Logs** | LoggerJSON -> Promtail/Alloy -> Loki -> Grafana | Logs estruturados em JSON com correlacao |
| **Error Tracking** | Sentry | Crash reporting, stack traces, alertas |
| **LLM Observability** | Custom Telemetry + Langfuse (via OTEL) | Token usage, custos, latencia LLM |

### Diagrama de Fluxo

```
BlackBoex App (Elixir/Phoenix)
  |
  |-- OpenTelemetry SDK -----> OTLP Collector -----> Grafana Tempo (traces)
  |                                    |-----------> Langfuse (LLM traces)
  |
  |-- PromEx (Telemetry) ----> /metrics endpoint --> Prometheus -----> Grafana (dashboards)
  |
  |-- LoggerJSON ------------> stdout (JSON) ------> Promtail/Alloy -> Loki -> Grafana
  |
  |-- Sentry SDK ------------> Sentry Cloud (error tracking + alertas)
  |
  Phoenix LiveDashboard (dev/staging, acesso interno)
```

---

## 2. OpenTelemetry no Elixir

OpenTelemetry e o padrao aberto para tracing distribuido. O ecossistema Elixir tem suporte maduro via pacotes oficiais mantidos pelo OpenTelemetry Erlang SIG.

### 2.1 Dependencias

```elixir
# mix.exs (umbrella root ou app blackboex_web)
defp deps do
  [
    # Core OpenTelemetry
    {:opentelemetry, "~> 1.5"},
    {:opentelemetry_api, "~> 1.4"},
    {:opentelemetry_exporter, "~> 1.8"},

    # Instrumentacao automatica
    {:opentelemetry_phoenix, "~> 2.0"},     # Phoenix controllers + LiveView
    {:opentelemetry_bandit, "~> 0.3"},      # Bandit HTTP server spans
    {:opentelemetry_ecto, "~> 1.2"},        # Ecto query tracing

    # Semantic conventions
    {:opentelemetry_semantic_conventions, "~> 1.27"},
  ]
end
```

**Por que precisamos de `opentelemetry_bandit` E `opentelemetry_phoenix`?**

Phoenix so trata parte do ciclo de vida do request (routing, controllers, LiveView). O servidor HTTP (Bandit) trata o ciclo completo request/response. Ambos sao necessarios para tracing completo: Bandit cria o span "pai" HTTP e Phoenix cria spans filhos para router, controller, LiveView.

### 2.2 Setup no Application

```elixir
defmodule BlackboexWeb.Application do
  use Application

  @impl true
  def start(_type, _args) do
    # IMPORTANTE: setup OpenTelemetry ANTES de iniciar o supervision tree
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup([:blackboex, :repo], db_statement: :enabled)

    children = [
      BlackboexWeb.Telemetry,
      BlackboexWeb.Endpoint,
      # ...
    ]

    opts = [strategy: :one_for_one, name: BlackboexWeb.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

### 2.3 Configuracao do Exporter

```elixir
# config/runtime.exs
config :opentelemetry,
  resource: %{
    "service.name" => "blackboex",
    "service.version" => Application.spec(:blackboex, :vsn) |> to_string(),
    "deployment.environment" => config_env() |> to_string()
  },
  span_processor: :batch,
  traces_exporter: :otlp

config :opentelemetry_exporter,
  otlp_protocol: :http_protobuf,
  otlp_endpoint: System.get_env("OTEL_EXPORTER_OTLP_ENDPOINT", "http://localhost:4318")

# Em dev, desabilitar export se nao houver collector
if config_env() == :dev do
  config :opentelemetry, traces_exporter: :none
end
```

### 2.4 Configuracao Avancada

```elixir
# Samplers - controlar volume de traces
config :opentelemetry,
  sampler: {:parentbased_traceidratio, 0.1}  # 10% em producao

# Span Sweeper - lidar com spans nao fechados (BEAM "let it crash")
config :opentelemetry,
  span_sweeper: %{
    interval: 600_000,     # 10 min
    strategy: :drop,       # ou :end_span, :failed_attribute_and_end_span
    span_ttl: 1_800_000    # 30 min TTL
  }

# Batch processor tuning
config :opentelemetry,
  bsp_scheduled_delay_ms: 5_000,
  bsp_max_queue_size: 2048,
  bsp_exporting_timeout_ms: 30_000
```

### 2.5 Spans Customizados

```elixir
require OpenTelemetry.Tracer, as: Tracer

defmodule Blackboex.CodeGeneration do
  @spec generate(String.t(), map()) :: {:ok, String.t()} | {:error, term()}
  def generate(prompt, opts) do
    Tracer.with_span "blackboex.code_generation" do
      Tracer.set_attributes([
        {"blackboex.prompt.length", String.length(prompt)},
        {"blackboex.llm.provider", opts[:provider] || "anthropic"},
        {"blackboex.llm.model", opts[:model] || "claude-sonnet-4-20250514"}
      ])

      case call_llm(prompt, opts) do
        {:ok, code} ->
          Tracer.set_attributes([
            {"blackboex.generated_code.length", String.length(code)},
            {"blackboex.generation.status", "success"}
          ])
          {:ok, code}

        {:error, reason} ->
          Tracer.set_attribute("blackboex.generation.status", "error")
          Tracer.set_status(:error, inspect(reason))
          {:error, reason}
      end
    end
  end
end
```

### 2.6 LiveView Tracing

O `opentelemetry_phoenix` instrumenta LiveView automaticamente, tracando:

- `mount/3`
- `handle_params/3`
- `handle_event/3`

Para callbacks de LiveComponent tambem. Desativar se necessario:

```elixir
OpentelemetryPhoenix.setup(adapter: :bandit, liveview: false)
```

### 2.7 Propagacao de Contexto

O SDK usa W3C TraceContext por padrao (headers `traceparent` e `tracestate`). Para servicos internos ou chamadas HTTP de saida:

```elixir
# Injecao de headers ao fazer chamadas HTTP externas
require OpenTelemetry.Tracer, as: Tracer

headers = :otel_propagator_text_map.inject([])
# Passar headers na chamada HTTP (Finch, Req, etc.)
Finch.build(:post, url, headers ++ other_headers, body)
```

---

## 3. Metricas com PromEx e Telemetry

### 3.1 O Ecossistema Telemetry do Elixir

O Elixir tem um sistema nativo de telemetria via a biblioteca `:telemetry`. Phoenix, Ecto, LiveView, Oban, e praticamente toda lib do ecossistema emitem eventos Telemetry. PromEx conecta esses eventos a metricas Prometheus com dashboards Grafana pre-construidos.

### 3.2 Dependencias

```elixir
defp deps do
  [
    {:prom_ex, "~> 1.11"},
    {:telemetry_poller, "~> 1.1"},
    {:telemetry_metrics, "~> 1.0"},
  ]
end
```

### 3.3 Modulo PromEx

```elixir
defmodule BlackboexWeb.PromEx do
  use PromEx, otp_app: :blackboex_web

  alias PromEx.Plugins

  @impl true
  def plugins do
    [
      # Built-in plugins
      Plugins.Application,
      Plugins.Beam,
      {Plugins.Phoenix, router: BlackboexWeb.Router, endpoint: BlackboexWeb.Endpoint},
      {Plugins.Ecto, repos: [Blackboex.Repo]},
      {Plugins.PhoenixLiveView, {}},

      # Custom plugin para metricas de negocio
      BlackboexWeb.PromEx.ApiMetricsPlugin,
      BlackboexWeb.PromEx.LlmMetricsPlugin,
    ]
  end

  @impl true
  def dashboard_assigns do
    [
      datasource_id: "prometheus",
      default_selected_interval: "30s"
    ]
  end

  @impl true
  def dashboards do
    [
      # Built-in dashboards de cada plugin
      {:prom_ex, "application.json"},
      {:prom_ex, "beam.json"},
      {:prom_ex, "phoenix.json"},
      {:prom_ex, "ecto.json"},
      {:prom_ex, "phoenix_live_view.json"},

      # Custom dashboards
      {:otp_app, "api_metrics_dashboard.json"},
      {:otp_app, "llm_metrics_dashboard.json"},
    ]
  end
end
```

### 3.4 Custom Plugin: Metricas de API

```elixir
defmodule BlackboexWeb.PromEx.ApiMetricsPlugin do
  use PromEx.Plugin

  @api_request_event [:blackboex, :api, :request]
  @api_publish_event [:blackboex, :api, :publish]

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :blackboex_api_metrics,
      [
        # Requests por API publicada
        counter(
          [:blackboex, :api, :request, :total],
          event_name: @api_request_event,
          measurement: :count,
          description: "Total API requests",
          tags: [:api_id, :user_id, :method, :status]
        ),

        # Latencia de requests por API
        distribution(
          [:blackboex, :api, :request, :duration, :milliseconds],
          event_name: @api_request_event,
          measurement: :duration,
          description: "API request duration in ms",
          tags: [:api_id, :method],
          reporter_options: [buckets: [10, 50, 100, 250, 500, 1000, 2500, 5000]]
        ),

        # APIs publicadas
        counter(
          [:blackboex, :api, :publish, :total],
          event_name: @api_publish_event,
          measurement: :count,
          description: "Total APIs published",
          tags: [:user_id, :status]
        ),
      ]
    )
  end
end
```

### 3.5 Custom Plugin: Metricas de LLM

```elixir
defmodule BlackboexWeb.PromEx.LlmMetricsPlugin do
  use PromEx.Plugin

  @llm_call_event [:blackboex, :llm, :call]

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :blackboex_llm_metrics,
      [
        # Token usage
        counter(
          [:blackboex, :llm, :tokens, :input, :total],
          event_name: @llm_call_event,
          measurement: :input_tokens,
          description: "Total input tokens consumed",
          tags: [:provider, :model]
        ),

        counter(
          [:blackboex, :llm, :tokens, :output, :total],
          event_name: @llm_call_event,
          measurement: :output_tokens,
          description: "Total output tokens generated",
          tags: [:provider, :model]
        ),

        # Custo estimado
        sum(
          [:blackboex, :llm, :cost, :total],
          event_name: @llm_call_event,
          measurement: :estimated_cost_usd,
          description: "Estimated LLM cost in USD",
          tags: [:provider, :model]
        ),

        # Latencia LLM
        distribution(
          [:blackboex, :llm, :call, :duration, :milliseconds],
          event_name: @llm_call_event,
          measurement: :duration,
          description: "LLM call duration",
          tags: [:provider, :model, :status],
          reporter_options: [buckets: [100, 500, 1000, 2000, 5000, 10000, 30000]]
        ),

        # Erros LLM
        counter(
          [:blackboex, :llm, :errors, :total],
          event_name: @llm_call_event,
          measurement: :error_count,
          description: "Total LLM call errors",
          tags: [:provider, :model, :error_type]
        ),
      ]
    )
  end
end
```

### 3.6 Emitindo Eventos Telemetry

```elixir
defmodule Blackboex.LLM.Telemetry do
  @moduledoc "Emissao de eventos Telemetry para chamadas LLM."

  @spec emit_llm_call(map()) :: :ok
  def emit_llm_call(measurements) do
    :telemetry.execute(
      [:blackboex, :llm, :call],
      %{
        duration: measurements.duration_ms,
        input_tokens: measurements.input_tokens,
        output_tokens: measurements.output_tokens,
        estimated_cost_usd: measurements.cost,
        error_count: if(measurements.status == :error, do: 1, else: 0)
      },
      %{
        provider: measurements.provider,
        model: measurements.model,
        status: measurements.status,
        error_type: measurements[:error_type]
      }
    )
  end

  @spec emit_api_request(map()) :: :ok
  def emit_api_request(measurements) do
    :telemetry.execute(
      [:blackboex, :api, :request],
      %{
        duration: measurements.duration_ms,
        count: 1
      },
      %{
        api_id: measurements.api_id,
        user_id: measurements.user_id,
        method: measurements.method,
        status: measurements.status_code
      }
    )
  end
end
```

### 3.7 Exposicao de Metricas no Endpoint

```elixir
# lib/blackboex_web/endpoint.ex
defmodule BlackboexWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :blackboex_web

  # Metricas Prometheus ANTES de tudo
  plug PromEx.Plug, prom_ex_module: BlackboexWeb.PromEx
  # Opcional: restringir caminho
  # plug PromEx.Plug, path: "/internal/metrics", prom_ex_module: BlackboexWeb.PromEx

  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]
  # ... restante do endpoint
end
```

### 3.8 Application Supervision Tree

```elixir
# application.ex
children = [
  BlackboexWeb.PromEx,  # PRIMEIRO - antes de Repo e Endpoint
  Blackboex.Repo,
  {Phoenix.PubSub, name: Blackboex.PubSub},
  BlackboexWeb.Endpoint,
]
```

---

## 4. Logging Estruturado

### 4.1 Por que JSON?

Logs em texto plano sao inuteis para agregacao. Logs em JSON permitem:
- Busca e filtragem por campos (api_id, user_id, trace_id)
- Correlacao com traces (via trace_id e span_id)
- Parsing automatico por Loki, ElasticSearch, Datadog
- Alertas baseados em campos estruturados

### 4.2 Dependencias

```elixir
defp deps do
  [
    {:logger_json, "~> 7.0"},
  ]
end
```

### 4.3 Configuracao

```elixir
# config/prod.exs (ou runtime.exs para producao)
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, []}

# Opcoes de formatadores disponiveis:
# - LoggerJSON.Formatters.Basic       -> generico (ElasticSearch, Logstash, Loki)
# - LoggerJSON.Formatters.GoogleCloud -> Google Cloud Logger
# - LoggerJSON.Formatters.Datadog     -> Datadog
# - LoggerJSON.Formatters.Elastic     -> Elastic Common Schema (ECS)

# Metadata a incluir nos logs
config :logger, :default_handler,
  formatter: {LoggerJSON.Formatters.Basic, []},
  metadata: [:request_id, :trace_id, :span_id, :api_id, :user_id]
```

**Nota**: A partir do Elixir 1.18+, LoggerJSON pode usar o modulo `JSON` built-in em vez do Jason:

```elixir
config :logger_json, :encoder, JSON  # built-in do Elixir 1.18+
```

### 4.4 Correlacao Logs + Traces

Para correlacionar logs com traces do OpenTelemetry:

```elixir
defmodule BlackboexWeb.Plugs.TraceLogger do
  @moduledoc "Adiciona trace_id e span_id ao Logger metadata."
  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    span_ctx = OpenTelemetry.Tracer.current_span_ctx()

    case span_ctx do
      :undefined ->
        conn

      ctx ->
        trace_id = OpenTelemetry.Span.trace_id(ctx) |> format_hex()
        span_id = OpenTelemetry.Span.span_id(ctx) |> format_hex()

        Logger.metadata(trace_id: trace_id, span_id: span_id)
        conn
    end
  end

  defp format_hex(id) when is_integer(id) do
    Integer.to_string(id, 16) |> String.downcase() |> String.pad_leading(32, "0")
  end
end
```

### 4.5 Log Contextual em Domain Modules

```elixir
defmodule Blackboex.APIs.Executor do
  require Logger

  @spec execute(map(), map()) :: {:ok, term()} | {:error, term()}
  def execute(api, request) do
    Logger.metadata(api_id: api.id, user_id: api.user_id)

    Logger.info("Executing published API",
      method: request.method,
      path: request.path,
      api_name: api.name
    )

    case run_sandboxed(api.compiled_code, request) do
      {:ok, result} ->
        Logger.info("API execution completed",
          status: :success,
          duration_ms: result.duration_ms
        )
        {:ok, result}

      {:error, reason} ->
        Logger.error("API execution failed",
          status: :error,
          error: inspect(reason),
          api_name: api.name
        )
        {:error, reason}
    end
  end
end
```

### 4.6 Exemplo de Output JSON

```json
{
  "time": "2026-03-17T14:32:10.123Z",
  "severity": "info",
  "message": "Executing published API",
  "metadata": {
    "api_id": "api_abc123",
    "user_id": "user_xyz789",
    "trace_id": "0af7651916cd43dd8448eb211c80319c",
    "span_id": "b7ad6b7169203331",
    "request_id": "F1234567890",
    "method": "POST",
    "path": "/api/v1/weather",
    "api_name": "Weather API"
  }
}
```

### 4.7 Desabilitando o Logger Padrao do Phoenix

Para evitar logs duplicados em producao:

```elixir
# config/prod.exs
config :phoenix, :logger, false
```

---

## 5. Dashboards e Visualizacao

### 5.1 Grafana (Principal - Producao)

Grafana e o hub central de visualizacao, conectando os tres pilares:

| Data Source | Dados | Uso |
|------------|-------|-----|
| **Prometheus** | Metricas (PromEx) | Graficos de performance, BEAM, Ecto, Phoenix |
| **Tempo** | Traces (OpenTelemetry) | Tracing distribuido, flame graphs |
| **Loki** | Logs (LoggerJSON) | Busca de logs, correlacao com traces |

### 5.2 Dashboards PromEx Pre-Construidos

PromEx inclui dashboards Grafana prontos para cada plugin:

- **BEAM Dashboard**: Memoria, schedulers, processes, atoms, ETS tables, GC
- **Phoenix Dashboard**: Request rate, latencia por rota, error rate, status codes
- **Ecto Dashboard**: Query duration, pool usage, checkout time, queue time
- **LiveView Dashboard**: Mount time, handle_event latencia, connected/disconnected
- **Application Dashboard**: Uptime, dependencias, versoes

Upload automatico via Grafana API:

```elixir
# config/runtime.exs
config :blackboex_web, BlackboexWeb.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: [
    host: System.get_env("GRAFANA_HOST", "http://localhost:3000"),
    auth_token: System.get_env("GRAFANA_AUTH_TOKEN"),
    upload_dashboards_on_start: true,
    folder_name: "BlackBoex",
    annotate_app_lifecycle: true  # marca deploys no Grafana
  ]
```

### 5.3 Custom Dashboards para BlackBoex

Alem dos dashboards built-in, criar dashboards customizados:

1. **API Overview Dashboard**: requests/sec por API, latencia p50/p95/p99, error rate por API, top 10 APIs por volume
2. **LLM Cost Dashboard**: custo acumulado por provider/model, token usage ao longo do tempo, custo por geracao de codigo, budget alerts
3. **User Activity Dashboard**: APIs publicadas por usuario, requests por usuario, erros por usuario
4. **Code Generation Dashboard**: taxa de sucesso de geracao, tempo medio de geracao, compilacao sucesso vs falha

### 5.4 Phoenix LiveDashboard (Dev/Staging)

O LiveDashboard vem embutido e serve para debug em dev/staging:

```elixir
# router.ex
import Phoenix.LiveDashboard.Router

scope "/" do
  pipe_through [:browser, :require_admin]

  live_dashboard "/dashboard",
    metrics: BlackboexWeb.Telemetry,
    additional_pages: [
      api_stats: BlackboexWeb.LiveDashboard.ApiStatsPage,
      llm_usage: BlackboexWeb.LiveDashboard.LlmUsagePage
    ]
end
```

### 5.5 Custom LiveDashboard Page

```elixir
defmodule BlackboexWeb.LiveDashboard.ApiStatsPage do
  @moduledoc "Pagina customizada do LiveDashboard para stats de APIs publicadas."
  use Phoenix.LiveDashboard.PageBuilder

  @impl true
  def menu_link(_, _) do
    {:ok, "API Stats"}
  end

  @impl true
  def mount(_params, session, socket) do
    # Carregar dados de APIs publicadas
    {:ok, socket}
  end

  @impl true
  def render_page(_assigns) do
    # Usar componentes do PageBuilder: card/1, row/1, live_table/1
    # ...
  end
end
```

### 5.6 Docker Compose para Stack de Observabilidade

```yaml
# docker-compose.observability.yml
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./infra/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml
    ports:
      - "9090:9090"

  grafana:
    image: grafana/grafana:latest
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - ./infra/grafana/provisioning:/etc/grafana/provisioning
      - grafana_data:/var/lib/grafana
    ports:
      - "3001:3000"  # 3001 para nao conflitar com Phoenix

  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    volumes:
      - ./infra/loki/config.yml:/etc/loki/local-config.yaml

  tempo:
    image: grafana/tempo:latest
    ports:
      - "4317:4317"   # gRPC OTLP
      - "4318:4318"   # HTTP OTLP
    volumes:
      - ./infra/tempo/config.yml:/etc/tempo/config.yaml

  promtail:
    image: grafana/promtail:latest
    volumes:
      - /var/log:/var/log
      - ./infra/promtail/config.yml:/etc/promtail/config.yml
    depends_on:
      - loki

volumes:
  grafana_data:
```

```yaml
# infra/prometheus/prometheus.yml
global:
  scrape_interval: 15s

scrape_configs:
  - job_name: "blackboex"
    static_configs:
      - targets: ["host.docker.internal:4000"]
    metrics_path: "/metrics"
```

---

## 6. APM e Error Tracking

### 6.1 Sentry (Recomendado)

Sentry e a escolha principal para error tracking por:
- SDK oficial mantido (`sentry ~> 12.0`)
- Integracao nativa com Phoenix, Plug, e LiveView
- Suporte a OpenTelemetry para tracing
- Source code context
- Free tier generoso

#### Dependencias

```elixir
defp deps do
  [
    {:sentry, "~> 12.0"},
    {:jason, "~> 1.4"},    # JSON encoder
    {:hackney, "~> 1.8"},  # HTTP client
  ]
end
```

#### Configuracao

```elixir
# config/config.exs
config :sentry,
  dsn: System.get_env("SENTRY_DSN"),
  environment_name: config_env(),
  enable_source_code_context: true,
  root_source_code_paths: [File.cwd!()]

# config/prod.exs - Logger handler para capturar crashes
config :logger, :default_handler,
  config: [
    type: :standard_error
  ]

# Adicionar Sentry.LoggerHandler
config :logger,
  backends: [:console],
  handle_otp_reports: true,
  handle_sasl_reports: true
```

#### Integracao com Phoenix Endpoint

```elixir
# lib/blackboex_web/endpoint.ex
defmodule BlackboexWeb.Endpoint do
  use Sentry.PlugCapture       # ANTES do use Phoenix.Endpoint
  use Phoenix.Endpoint, otp_app: :blackboex_web

  # ... plugs ...

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Sentry.PlugContext       # DEPOIS do Plug.Parsers

  plug BlackboexWeb.Router
end
```

#### Integracao com LiveView

```elixir
# lib/blackboex_web.ex
def live_view do
  quote do
    use Phoenix.LiveView, layout: {BlackboexWeb.Layouts, :app}
    on_mount Sentry.LiveViewHook   # Adicionar hook de Sentry
    unquote(html_helpers())
  end
end
```

#### Logger Handler para Captura Automatica

```elixir
# config/runtime.exs
:logger.add_handler(:sentry_handler, Sentry.LoggerHandler, %{
  config: %{
    metadata: [:file, :line, :request_id, :api_id, :user_id],
    capture_log_messages: true,
    level: :error
  }
})
```

### 6.2 Comparacao de APMs

| Feature | Sentry | AppSignal | New Relic |
|---------|--------|-----------|-----------|
| **Preco** | Free tier generoso | $23/mo+ | Free tier limitado |
| **Error tracking** | Excelente | Bom | Bom |
| **APM/Perf** | Via OTEL | Nativo, excelente | Excelente |
| **Elixir support** | SDK oficial | Feito para Elixir | Agente generico |
| **Self-hosted** | Sim (open source) | Nao | Nao |
| **BEAM awareness** | Basico | Profundo | Basico |
| **LiveView** | Hook nativo | Suporte nativo | Limitado |
| **Setup effort** | Baixo | Baixo | Medio |
| **Dashboard** | Proprio | Proprio | Proprio |
| **OTEL integration** | Sim (traces) | Limitado | Sim |

**Recomendacao**: Sentry para error tracking (gratis, open source) + PromEx/Grafana para APM. Se budget permitir, AppSignal e excelente para Elixir pois entende profundamente a BEAM.

---

## 7. Observabilidade Per-API (Multi-Tenant)

Este e o requisito mais unico do BlackBoex: cada API publicada por um usuario precisa de metricas, logs e traces isolados e visiveis para o dono.

### 7.1 Estrategia: Labels/Tags com Tenant ID

Nao criar infra separada por tenant. Usar labels dimensionais:

```
api_id  -> identifica a API publicada
user_id -> identifica o dono da API
```

Todas as metricas, logs e traces DEVEM conter esses dois labels.

### 7.2 Metricas Per-API

```elixir
# Cada request a uma API publicada emite telemetry com api_id
:telemetry.execute(
  [:blackboex, :api, :request],
  %{duration: duration_ms, count: 1},
  %{api_id: api.id, user_id: api.user_id, method: method, status: status_code}
)
```

No Prometheus, isso gera metricas como:

```
blackboex_api_request_total{api_id="api_abc", user_id="usr_123", method="GET", status="200"} 1547
blackboex_api_request_duration_milliseconds_bucket{api_id="api_abc", method="GET", le="100"} 1200
```

**Cuidado com cardinalidade**: Se houver milhares de APIs, a cardinalidade das metricas cresce. Estrategias:
- Agregar por user_id em vez de api_id para dashboards globais
- Usar recording rules no Prometheus para pre-agregar
- Considerar VictoriaMetrics se cardinalidade ficar muito alta

### 7.3 Logs Per-API

```elixir
# Plug para injetar api_id e user_id no Logger metadata
defmodule BlackboexWeb.Plugs.ApiContext do
  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case conn.assigns[:published_api] do
      nil -> conn
      api ->
        Logger.metadata(api_id: api.id, user_id: api.user_id, api_name: api.name)
        conn
    end
  end
end
```

No Loki/Grafana, filtrar por `{api_id="api_abc"}`.

### 7.4 Traces Per-API

```elixir
# Adicionar atributos ao span do OpenTelemetry
require OpenTelemetry.Tracer, as: Tracer

def execute_api(api, request) do
  Tracer.with_span "blackboex.api.execute", attributes: [
    {"blackboex.api.id", api.id},
    {"blackboex.api.name", api.name},
    {"blackboex.api.user_id", api.user_id},
    {"blackboex.api.version", api.version}
  ] do
    # ... execucao
  end
end
```

No Tempo/Grafana, filtrar por `blackboex.api.id = "api_abc"`.

### 7.5 Dashboard Per-Tenant no Produto

Para expor metricas ao usuario (dono da API), criar uma LiveView que consulta:

```elixir
defmodule BlackboexWeb.ApiAnalyticsLive do
  use BlackboexWeb, :live_view

  @impl true
  def mount(%{"api_id" => api_id}, _session, socket) do
    # Verificar que o usuario atual e dono da API
    api = Blackboex.APIs.get_api!(api_id)
    authorize!(socket.assigns.current_user, api)

    # Buscar metricas do periodo
    stats = Blackboex.Analytics.get_api_stats(api_id, period: :last_24h)

    {:ok, assign(socket,
      api: api,
      total_requests: stats.total_requests,
      avg_latency_ms: stats.avg_latency_ms,
      error_rate: stats.error_rate,
      requests_by_hour: stats.requests_by_hour
    )}
  end
end
```

### 7.6 Armazenamento de Analytics Per-API

Para analytics user-facing, nao depender apenas do Prometheus (retencao curta). Usar uma tabela Ecto:

```elixir
# Tabela para analytics agregados (rollup a cada minuto/hora)
defmodule Blackboex.Analytics.ApiMetricRollup do
  use Ecto.Schema

  schema "api_metric_rollups" do
    field :api_id, :binary_id
    field :period_start, :utc_datetime
    field :period_granularity, Ecto.Enum, values: [:minute, :hour, :day]
    field :request_count, :integer
    field :error_count, :integer
    field :avg_latency_ms, :float
    field :p95_latency_ms, :float
    field :p99_latency_ms, :float

    timestamps(type: :utc_datetime)
  end
end
```

Um GenServer ou Oban job periodicamente agrega os dados brutos.

---

## 8. Health Checks e Alerting

### 8.1 Health Check Endpoints

Implementar tres endpoints para Kubernetes/load balancer:

```elixir
defmodule BlackboexWeb.HealthPlug do
  @moduledoc """
  Health check plug. Posicionado ANTES de todos os outros plugs
  para evitar overhead desnecessario e poluicao de logs.
  """
  import Plug.Conn

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(%Plug.Conn{request_path: "/health/live"} = conn, _opts) do
    # Liveness: app esta viva?
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "ok"}))
    |> halt()
  end

  def call(%Plug.Conn{request_path: "/health/ready"} = conn, _opts) do
    # Readiness: app pode receber trafego?
    checks = [
      {:database, check_database()},
      {:pubsub, check_pubsub()},
    ]

    {status_code, status} =
      if Enum.all?(checks, fn {_, result} -> result == :ok end) do
        {200, "ready"}
      else
        {503, "not_ready"}
      end

    body = %{
      status: status,
      checks: Map.new(checks, fn {name, result} -> {name, to_string(result)} end)
    }

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status_code, Jason.encode!(body))
    |> halt()
  end

  def call(%Plug.Conn{request_path: "/health/startup"} = conn, _opts) do
    # Startup: app terminou de inicializar?
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(%{status: "started"}))
    |> halt()
  end

  def call(conn, _opts), do: conn

  defp check_database do
    case Ecto.Adapters.SQL.query(Blackboex.Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, _} -> :error
    end
  rescue
    _ -> :error
  end

  defp check_pubsub do
    # Verificar se PubSub esta respondendo
    node = Phoenix.PubSub.node_name(Blackboex.PubSub)
    if node, do: :ok, else: :error
  rescue
    _ -> :error
  end
end
```

Posicionar no endpoint:

```elixir
# endpoint.ex - PRIMEIRO plug
plug BlackboexWeb.HealthPlug

# ... demais plugs
```

### 8.2 Health Checks para APIs Publicadas

Cada API publicada pode ter seu proprio health check:

```elixir
defmodule Blackboex.APIs.HealthMonitor do
  @moduledoc "Monitora a saude de APIs publicadas periodicamente."
  use GenServer

  @check_interval :timer.minutes(5)

  # Verificar se a API responde, se o codigo compila,
  # se as dependencias estao acessiveis
  def check_api_health(api) do
    checks = %{
      code_compilable: check_compilation(api),
      last_error_rate: check_error_rate(api),
      avg_latency_ok: check_latency(api)
    }

    healthy? = Enum.all?(Map.values(checks), & &1)
    %{healthy: healthy?, checks: checks}
  end
end
```

### 8.3 Alertas via Grafana

```yaml
# Exemplo de alerta Grafana (provisioning)
apiVersion: 1
groups:
  - name: blackboex-alerts
    folder: BlackBoex
    interval: 1m
    rules:
      - title: High Error Rate
        condition: C
        data:
          - refId: A
            queryType: instant
            expr: |
              sum(rate(blackboex_api_request_total{status=~"5.."}[5m]))
              / sum(rate(blackboex_api_request_total[5m])) > 0.05

      - title: High LLM Latency
        condition: C
        data:
          - refId: A
            queryType: instant
            expr: |
              histogram_quantile(0.95,
                rate(blackboex_llm_call_duration_milliseconds_bucket[5m])
              ) > 10000

      - title: BEAM Memory High
        condition: C
        data:
          - refId: A
            queryType: instant
            expr: |
              blackboex_beam_vm_memory_total_bytes > 2147483648
```

---

## 9. Observabilidade de LLM

### 9.1 Desafios Unicos

LLM calls sao diferentes de requests HTTP normais:
- Latencia alta e variavel (1-60s)
- Custo por token (input vs output, varia por modelo)
- Nao-determinismo (mesma entrada pode gerar saidas diferentes)
- Necessidade de inspecionar prompts e completions para debug
- Rate limits e retries
- Streaming responses

### 9.2 Telemetry Events para LLM

```elixir
defmodule Blackboex.LLM.Instrumentation do
  @moduledoc "Wrapper instrumentado para chamadas LLM."
  require OpenTelemetry.Tracer, as: Tracer

  @spec call_with_telemetry(module(), String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def call_with_telemetry(provider_module, prompt, opts) do
    start_time = System.monotonic_time(:millisecond)

    Tracer.with_span "blackboex.llm.call",
      attributes: [
        {"gen_ai.system", provider_name(provider_module)},
        {"gen_ai.request.model", opts[:model]},
        {"gen_ai.request.max_tokens", opts[:max_tokens]},
        {"gen_ai.request.temperature", opts[:temperature]},
        {"blackboex.llm.prompt.length", String.length(prompt)}
      ] do

      result = provider_module.complete(prompt, opts)
      duration = System.monotonic_time(:millisecond) - start_time

      case result do
        {:ok, response} ->
          Tracer.set_attributes([
            {"gen_ai.usage.input_tokens", response.input_tokens},
            {"gen_ai.usage.output_tokens", response.output_tokens},
            {"gen_ai.usage.cost", calculate_cost(opts[:model], response)},
            {"gen_ai.response.model", response.model},
            {"blackboex.llm.response.length", String.length(response.content)}
          ])

          emit_telemetry(:success, duration, response, opts)
          {:ok, response}

        {:error, reason} ->
          Tracer.set_status(:error, inspect(reason))
          Tracer.set_attribute("error.type", error_type(reason))

          emit_telemetry(:error, duration, reason, opts)
          {:error, reason}
      end
    end
  end

  defp emit_telemetry(status, duration, data, opts) do
    measurements = %{
      duration_ms: duration,
      input_tokens: if(status == :success, do: data.input_tokens, else: 0),
      output_tokens: if(status == :success, do: data.output_tokens, else: 0),
      cost: if(status == :success, do: calculate_cost(opts[:model], data), else: 0.0),
      error_count: if(status == :error, do: 1, else: 0)
    }

    metadata = %{
      provider: opts[:provider] || "anthropic",
      model: opts[:model],
      status: status,
      error_type: if(status == :error, do: error_type(data), else: nil)
    }

    :telemetry.execute([:blackboex, :llm, :call], measurements, metadata)
  end

  defp calculate_cost(model, response) do
    pricing = Blackboex.LLM.Pricing.get(model)
    input_cost = response.input_tokens * pricing.input_per_token
    output_cost = response.output_tokens * pricing.output_per_token
    Float.round(input_cost + output_cost, 6)
  end
end
```

### 9.3 Langfuse para LLM Observability

Langfuse e uma plataforma open source de observabilidade LLM que pode receber traces via OpenTelemetry. Para o BlackBoex, e ideal porque:

- **Self-hostable**: pode rodar junto com a infra do BlackBoex
- **OpenTelemetry native**: recebe traces via endpoint OTLP padrao
- **LLM-aware**: entende token usage, custos, prompts/completions
- **UI dedicada**: dashboard especifico para LLM com drill-down em cada geracao

#### Configuracao via OpenTelemetry Collector

```yaml
# otel-collector-config.yaml
receivers:
  otlp:
    protocols:
      http:
        endpoint: 0.0.0.0:4318
      grpc:
        endpoint: 0.0.0.0:4317

exporters:
  # Traces gerais -> Tempo
  otlphttp/tempo:
    endpoint: "http://tempo:4318"

  # Traces LLM -> Langfuse
  otlphttp/langfuse:
    endpoint: "http://langfuse:3000/api/public/otel"
    headers:
      Authorization: "Basic <base64(public_key:secret_key)>"
      x-langfuse-ingestion-version: "4"

processors:
  batch:
    timeout: 5s
    send_batch_size: 512

  # Filtrar apenas spans LLM para Langfuse
  filter/llm:
    traces:
      span:
        - 'attributes["gen_ai.system"] != ""'

service:
  pipelines:
    # Todos os traces -> Tempo
    traces/all:
      receivers: [otlp]
      processors: [batch]
      exporters: [otlphttp/tempo]

    # Apenas traces LLM -> Langfuse
    traces/llm:
      receivers: [otlp]
      processors: [filter/llm, batch]
      exporters: [otlphttp/langfuse]
```

### 9.4 Atributos Semanticos para LLM (Gen AI Semantic Conventions)

Seguir as semantic conventions do OpenTelemetry para Gen AI:

| Atributo | Descricao |
|---------|-----------|
| `gen_ai.system` | Provider (e.g., "anthropic", "openai") |
| `gen_ai.request.model` | Modelo solicitado |
| `gen_ai.response.model` | Modelo efetivamente usado |
| `gen_ai.request.max_tokens` | Max tokens configurado |
| `gen_ai.request.temperature` | Temperatura |
| `gen_ai.usage.input_tokens` | Tokens de input consumidos |
| `gen_ai.usage.output_tokens` | Tokens de output gerados |
| `gen_ai.usage.cost` | Custo estimado em USD |
| `gen_ai.prompt` | Prompt enviado (cuidado com PII) |
| `gen_ai.completion` | Resposta recebida |

### 9.5 Metricas LLM para Alerta

Alertar quando:
- Custo diario exceder threshold (budget alert)
- Latencia p95 de LLM calls > 30s
- Taxa de erro de LLM > 5%
- Token usage anomalo (possivel prompt injection ou abuse)
- Rate limit hits > N por minuto

---

## 10. Observabilidade da BEAM VM

### 10.1 Por que Monitorar a BEAM?

A BEAM VM tem caracteristicas unicas que precisam de monitoramento especifico:
- **Processes**: Milhares a milhoes de processos leves
- **Schedulers**: Preemptive scheduling em N cores
- **Memory**: Heap per-process, ETS, binary heap, atom table
- **Message queues**: Bottlenecks aparecem como message queue backlog
- **GC**: Per-process garbage collection

### 10.2 Metricas via PromEx (Automatico)

O plugin `PromEx.Plugins.Beam` captura automaticamente:

| Metrica | Descricao |
|---------|-----------|
| `vm.memory.total` | Memoria total alocada pela VM |
| `vm.memory.processes` | Memoria usada por processos |
| `vm.memory.binary` | Memoria do binary heap |
| `vm.memory.ets` | Memoria de tabelas ETS |
| `vm.memory.atom` | Memoria da atom table |
| `vm.total_run_queue_lengths.total` | Tamanho total da fila de scheduling |
| `vm.total_run_queue_lengths.cpu` | Fila de CPU schedulers |
| `vm.total_run_queue_lengths.io` | Fila de dirty IO |
| `vm.system_counts.process_count` | Numero de processos ativos |
| `vm.system_counts.atom_count` | Numero de atoms |
| `vm.system_counts.port_count` | Numero de ports |

### 10.3 telemetry_poller para Custom VM Metrics

```elixir
# Em Telemetry module
defmodule BlackboexWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    children = [
      {:telemetry_poller,
       measurements: [
         {__MODULE__, :measure_message_queues, []},
         {__MODULE__, :measure_process_info, []},
       ],
       period: :timer.seconds(10)}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # VM metrics
      last_value("vm.memory.total", unit: :byte),
      last_value("vm.memory.processes", unit: :byte),
      last_value("vm.memory.binary", unit: :byte),
      last_value("vm.memory.ets", unit: :byte),
      last_value("vm.total_run_queue_lengths.total"),
      last_value("vm.total_run_queue_lengths.cpu"),
      last_value("vm.system_counts.process_count"),

      # Phoenix metrics
      summary("phoenix.endpoint.start.system_time", unit: {:native, :millisecond}),
      summary("phoenix.endpoint.stop.duration", unit: {:native, :millisecond}),
      summary("phoenix.router_dispatch.stop.duration", unit: {:native, :millisecond}),

      # Ecto metrics
      summary("blackboex.repo.query.total_time", unit: {:native, :millisecond}),
      summary("blackboex.repo.query.queue_time", unit: {:native, :millisecond}),
    ]
  end

  # Custom measurement: encontrar processos com message queues grandes
  def measure_message_queues do
    {top_queue, top_pid} =
      Process.list()
      |> Enum.map(fn pid ->
        case Process.info(pid, :message_queue_len) do
          {:message_queue_len, len} -> {len, pid}
          nil -> {0, pid}
        end
      end)
      |> Enum.max_by(&elem(&1, 0), fn -> {0, nil} end)

    :telemetry.execute(
      [:blackboex, :beam, :max_message_queue],
      %{length: top_queue},
      %{pid: inspect(top_pid)}
    )
  end

  def measure_process_info do
    process_count = :erlang.system_info(:process_count)
    process_limit = :erlang.system_info(:process_limit)

    :telemetry.execute(
      [:blackboex, :beam, :processes],
      %{count: process_count, limit: process_limit, usage_pct: process_count / process_limit * 100},
      %{}
    )
  end
end
```

### 10.4 Ferramentas de Debug em Producao

#### recon (v2.5.6)

```elixir
# mix.exs - adicionar APENAS em releases de producao (ou sempre)
{:recon, "~> 2.5"}
```

Uso via remote console:

```elixir
# Top 10 processos por memoria
:recon.proc_count(:memory, 10)

# Top 10 processos por message queue
:recon.proc_count(:message_queue_len, 10)

# Info detalhado de um processo
:recon.info(pid)

# Memoria por tipo
:recon_alloc.memory(:allocated)

# Tracing seguro em producao (com rate limit)
:recon_trace.calls({MyModule, :my_function, :_}, 10, scope: :local)
```

#### observer_cli (v1.8.7)

```elixir
# mix.exs
{:observer_cli, "~> 1.8"}
```

Uso via remote console:

```elixir
# Iniciar observer no terminal
:observer_cli.start()

# Conectar a node remoto
:observer_cli.start(:"blackboex@production-host", :"cookie_value")
```

Mostra em tempo real:
- Scheduler utilization
- Memoria por tipo (processes, binary, ets, atom)
- Top processos por memoria e reductions
- Network I/O
- System info

### 10.5 Alertas BEAM

```yaml
# Prometheus alerting rules
groups:
  - name: beam-alerts
    rules:
      - alert: HighProcessCount
        expr: blackboex_beam_vm_system_counts_process_count > 100000
        for: 5m
        annotations:
          summary: "BEAM process count above 100k"

      - alert: HighRunQueueLength
        expr: blackboex_beam_vm_total_run_queue_lengths_total > 50
        for: 2m
        annotations:
          summary: "BEAM schedulers overloaded"

      - alert: HighMemoryUsage
        expr: blackboex_beam_vm_memory_total_bytes > 4294967296  # 4GB
        for: 10m
        annotations:
          summary: "BEAM memory usage above 4GB"

      - alert: LargeMessageQueue
        expr: blackboex_beam_max_message_queue_length > 10000
        for: 1m
        annotations:
          summary: "Process with message queue > 10k"
```

---

## 11. Stack Recomendada

### 11.1 Resumo Final

| Camada | Ferramenta | Justificativa |
|--------|-----------|---------------|
| **Traces** | OpenTelemetry -> Grafana Tempo | Padrao aberto, ecossistema Elixir maduro |
| **Metrics** | PromEx -> Prometheus | Dashboards prontos, plugins para todo ecossistema |
| **Logs** | LoggerJSON -> Loki | JSON estruturado, correlacao com traces |
| **Dashboards** | Grafana | Hub unico para metricas, traces, logs |
| **Error Tracking** | Sentry | Open source, SDK Elixir oficial, LiveView hook |
| **LLM Observability** | Custom Telemetry + Langfuse | OTEL-native, self-hostable, LLM-aware |
| **Dev Dashboard** | Phoenix LiveDashboard | Zero config, custom pages |
| **BEAM Debug** | recon + observer_cli | Standard da industria Erlang |
| **Health Checks** | Custom Plug | Liveness/readiness/startup para K8s |

### 11.2 Dependencias Completas

```elixir
# mix.exs
defp deps do
  [
    # --- OpenTelemetry ---
    {:opentelemetry, "~> 1.5"},
    {:opentelemetry_api, "~> 1.4"},
    {:opentelemetry_exporter, "~> 1.8"},
    {:opentelemetry_phoenix, "~> 2.0"},
    {:opentelemetry_bandit, "~> 0.3"},
    {:opentelemetry_ecto, "~> 1.2"},
    {:opentelemetry_semantic_conventions, "~> 1.27"},

    # --- Metrics ---
    {:prom_ex, "~> 1.11"},
    {:telemetry_poller, "~> 1.1"},
    {:telemetry_metrics, "~> 1.0"},

    # --- Logging ---
    {:logger_json, "~> 7.0"},

    # --- Error Tracking ---
    {:sentry, "~> 12.0"},

    # --- BEAM Debugging ---
    {:recon, "~> 2.5"},
    {:observer_cli, "~> 1.8"},
  ]
end
```

### 11.3 Custos Estimados

| Componente | Self-hosted | Managed |
|-----------|-----------|---------|
| Grafana + Prometheus + Loki + Tempo | Infra propria (~$50-100/mo VM) | Grafana Cloud free tier ate 10k metricas |
| Sentry | Self-hosted (gratis) | Free tier: 5k errors/mo |
| Langfuse | Self-hosted (gratis) | Cloud: free tier disponivel |
| **Total minimo** | **~$50-100/mo** | **$0 (free tiers)** |

---

## 12. Plano de Implementacao

### Fase 1: Fundacao (Semana 1-2)

- [ ] Adicionar dependencias OpenTelemetry ao mix.exs
- [ ] Configurar `OpentelemetryBandit.setup()`, `OpentelemetryPhoenix.setup()`, `OpentelemetryEcto.setup()`
- [ ] Configurar LoggerJSON no config de producao
- [ ] Adicionar Sentry com PlugCapture + LiveViewHook
- [ ] Implementar health check plug (`/health/live`, `/health/ready`)
- [ ] Docker Compose com Tempo + Prometheus + Loki + Grafana

### Fase 2: Metricas (Semana 3-4)

- [ ] Configurar PromEx com plugins (BEAM, Phoenix, Ecto, LiveView)
- [ ] Criar custom plugin para metricas de API (`ApiMetricsPlugin`)
- [ ] Criar custom plugin para metricas LLM (`LlmMetricsPlugin`)
- [ ] Upload dashboards Grafana (automatico via PromEx)
- [ ] Configurar Prometheus scraping

### Fase 3: LLM Observability (Semana 5-6)

- [ ] Implementar `LLM.Instrumentation` com Telemetry + OTEL spans
- [ ] Configurar pricing por modelo para cost tracking
- [ ] Setup Langfuse (self-hosted ou cloud)
- [ ] Configurar OTEL Collector com dual export (Tempo + Langfuse)
- [ ] Dashboard Grafana de custos LLM

### Fase 4: Per-API Observability (Semana 7-8)

- [ ] Plug para injetar api_id/user_id em logs e traces
- [ ] Tabela de rollup de metricas por API
- [ ] Oban job para agregacao periodica
- [ ] LiveView de analytics per-API (visivel para o dono)
- [ ] Recording rules no Prometheus para pre-agregacao

### Fase 5: Alerting e Polish (Semana 9-10)

- [ ] Alertas Grafana (error rate, latencia, BEAM, LLM cost)
- [ ] Custom LiveDashboard pages para dev/staging
- [ ] Adicionar recon e observer_cli ao release
- [ ] Documentar runbooks de incidente
- [ ] Load test com observabilidade ativa para validar overhead

---

## Referencias

- [OpenTelemetry Erlang/Elixir SDK](https://opentelemetry.io/docs/languages/erlang/)
- [OpenTelemetry Erlang SDK Hexdocs](https://hexdocs.pm/opentelemetry/)
- [OpenTelemetry Phoenix Integration (Uptrace guide)](https://uptrace.dev/guides/opentelemetry-phoenix)
- [OpenTelemetry Phoenix on Hex](https://hex.pm/packages/opentelemetry_phoenix) (v2.0.1)
- [OpenTelemetry Bandit on Hex](https://hex.pm/packages/opentelemetry_bandit) (v0.3.0)
- [OpenTelemetry Ecto on Hex](https://hex.pm/packages/opentelemetry_ecto) (v1.2.0)
- [PromEx - GitHub](https://github.com/akoutmos/prom_ex)
- [PromEx on Hex](https://hex.pm/packages/prom_ex) (v1.11.0)
- [PromEx Grafana Blog Post](https://grafana.com/blog/2021/04/28/get-instant-grafana-dashboards-for-prometheus-metrics-with-the-elixir-promex-library/)
- [Building Custom Prometheus Metrics with PromEx (DockYard)](https://dockyard.com/blog/2023/09/12/building-your-own-prometheus-metrics-with-promex)
- [LoggerJSON Hexdocs](https://hexdocs.pm/logger_json/LoggerJSON.html) (v7.0.4)
- [LoggerJSON GitHub](https://github.com/Nebo15/logger_json)
- [Structured JSON Logs in Elixir](https://dev.to/aymanosman/structured-json-logs-in-elixir-48gi)
- [Elixir Structured Logging with Loki (Alex Koutmos)](https://akoutmos.com/post/elixir-logging-loki/)
- [Sentry Elixir SDK](https://docs.sentry.io/platforms/elixir/)
- [Sentry Plug and Phoenix Integration](https://docs.sentry.io/platforms/elixir/integrations/plug_and_phoenix/)
- [Sentry Elixir on Hex](https://hex.pm/packages/sentry)
- [Phoenix LiveDashboard PageBuilder](https://hexdocs.pm/phoenix_live_dashboard/Phoenix.LiveDashboard.PageBuilder.html)
- [Custom LiveDashboard Pages (DockYard)](https://dockyard.com/blog/2024/05/07/get-more-from-phoenix-livedashboard-with-pagebuilder)
- [Langfuse LLM Observability](https://langfuse.com/docs/observability/overview)
- [Langfuse OpenTelemetry Integration](https://langfuse.com/integrations/native/opentelemetry)
- [Top Open Source LLM Observability Tools 2025](https://dev.to/practicaldeveloper/comprehensive-guide-top-open-source-llm-observability-tools-in-2025-1kl1)
- [Telemetry Poller: BEAM VM Metrics (Elixir School)](https://elixirschool.com/blog/instrumenting-phoenix-with-telemetry-part-four)
- [recon on Hex](https://hex.pm/packages/recon) (v2.5.6)
- [observer_cli on Hex](https://hexdocs.pm/observer_cli/) (v1.8.7)
- [observer_cli GitHub](https://github.com/zhongwencool/observer_cli)
- [Kubernetes Health Checks for Phoenix](https://shyr.io/blog/kubernetes-health-probes-elixir/)
- [Multi-tenant Observability with Grafana & Loki](https://sollybombe.medium.com/creating-multi-tenant-observability-dashboards-with-grafana-loki-2025-edition-85a673eff596)
- [Monitoring Multi-tenant SaaS with New Relic](https://newrelic.com/blog/how-to-relic/monitoring-multi-tenant-saas-applications)
- [Phoenix Observability with Grafana Stack](https://elixirmerge.com/p/implementing-observability-in-phoenix-applications-with-grafana)
- [Elixir OpenTelemetry and N+1 (Fly.io)](https://fly.io/phoenix-files/opentelemetry-and-the-infamous-n-plus-1/)
- [Sentry Elixir Error Monitoring with Phoenix (Alex Koutmos)](https://akoutmos.com/post/error-monitoring-phoenix-with-sentry/)
