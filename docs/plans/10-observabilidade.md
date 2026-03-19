# Fase 10 - Observabilidade Plena

> **Entregavel testavel:** Telemetria completa com traces distribuidos, metricas
> Prometheus, logs estruturados, dashboards Grafana, alertas configurados,
> analytics por API visivel para usuarios, e monitoramento BEAM.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - `prom_ex`, `opentelemetry`, `logger_json`, `sentry` — verificar `.formatter.exs` e `import_deps` para cada dep com macros
> - Rodar todos os linters apos cada bloco de implementacao
> - Atualizar `.dialyzer_ignore.exs` para falsos positivos se necessario
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 02):**
> - Versoes de deps no discovery podem estar desatualizadas — sempre `mix hex.search <pkg>` antes de adicionar
> - Deps que usam `defdelegate` com default args geram `unknown_function` no Dialyzer — adicionar ao `.dialyzer_ignore.exs`
> - Trabalho async em LiveView DEVE usar `Task.async` + `handle_info({ref, result})` + `handle_info({:DOWN, ...})`. NUNCA `send(self(), :do_work)`
> - Rate limiting, autorizacao e tracking de uso DEVEM ser chamados no fluxo real, nao apenas implementados como modulos soltos
> - Filtrar opts internos antes de passar a libs externas — `Keyword.drop([:user_id])`
> - `defp` entre clausulas `def` do mesmo nome gera warning — agrupar clausulas publicas primeiro, helpers privados depois
> - `@module_attr` em HEEx resolve para `assigns`, NAO module attribute
> - Testes LiveView com `Task.async` + Mox precisam `async: false`
> - Discovery docs tem exemplos de API ERRADOS — NUNCA confiar nos exemplos. Sempre verificar a API real em `deps/<pkg>/lib/`
> - Deps OTP que precisam de supervision tree (ex: ExRated) devem ser listados em `extra_applications` no `mix.exs`
> - Erros de libs externas NAO devem ser engolidos — sempre logar o erro original e propagar mensagem legivel ao usuario
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 05):**
> - JSONB array read-modify-write tem race condition TOCTOU — usar `Ecto.Multi` com `SELECT ... FOR UPDATE` para serializar writes concorrentes. Testar com `Task.async`
> - JSONB `{:array, :map}` nao tem validacao de schema — adicionar validacao custom no changeset para estrutura dos maps (enum de valores, campos obrigatorios)
> - JSONB arrays crescem sem limite — adicionar validacao `max_items` no changeset (ex: `@max_messages 500`)
> - Pin operator `^` nao funciona em `Repo.update_all` com `fragment` — usar `Ecto.Multi` com lock + `Repo.update`
> - LiveComponent em testes: usar `render(lv)`, NAO o `html` de `live/3` — HTML estatico nao inclui conteudo de LiveComponents
> - LiveComponent NAO herda assigns do parent — passar todo assign necessario explicitamente via atributos no template
> - Erros de LLM/libs devem ser mapeados para mensagens amigaveis via helper `friendly_error/1` — SEMPRE `Logger.warning` o erro original
> - Erros de changeset devem ser logados antes de mostrar mensagem generica ao usuario
> - XSS em conteudo dinamico: Phoenix HEEx escapa por padrao, mas DEVE ser testado explicitamente com payload `<script>`
> - Cascade delete (`on_delete: :delete_all`) deve ser testado — criar filho, deletar pai, verificar remocao
> - Auditar apos implementacao: validacao de input, race conditions, erros silenciados, XSS, cascade delete, limites de crescimento
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 06):**
> - Valores do usuario interpolados em strings de codigo sao INJECTION — usar funcoes de escaping por linguagem-alvo (shell, Python, JS, Go, Ruby). Testar com payloads maliciosos (`'`, `"`, backtick, `$(...)`)
> - Buscar por ID externo sem verificar ownership e IDOR — SEMPRE pin match: `%{api_id: ^api_id}` ou `%{org_id: ^org_id}`. Context modules NAO tem auth built-in; verificacao no LiveView/Controller
> - `URI.parse("//evil.com")` retorna `scheme: nil` mas `host: "evil.com"` — checar `scheme` E `host` para SSRF protection
> - Eventos LiveView vem do cliente — validar TODOS os params com guard clauses (`when method in @valid_methods`). Definir whitelists em module attrs
> - Task.async concorrente: guardar contra double-submit com `%{loading: true}` pattern match. Limpar refs em TODOS os paths de saida (sucesso, erro, `:DOWN`)
> - `String.to_existing_atom(user_input)` pode crashar — preferir whitelist guard + `String.to_atom` (seguro porque whitelist impede atom exhaustion)
> - `inspect(reason)` em mensagens ao usuario expoe internals — usar mensagens amigaveis fixas, logar erro real com `Logger.warning`
> - Todo campo string em schemas DEVE ter `validate_length` com max (path: 2048, body: 1MB)
> - Lista de headers sensiveis deve incluir: Authorization, Cookie, X-Api-Key, X-Auth-Token, X-Access-Token, X-Csrf-Token, Proxy-Authorization, Set-Cookie
> - Phoenix HEEx `{}` auto-escapa HTML — NAO gastar tempo com XSS a menos que use `raw()`. MAS: sempre testar com payload `<script>` para confirmar
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 07):**
> - Comparacao de segredos (API keys, tokens, hashes) DEVE usar `Plug.Crypto.secure_compare/2` — NUNCA comparacao direta. Buscar por campo nao-secreto (prefix), depois comparar hash constant-time
> - LiveView event handlers que recebem IDs do cliente DEVEM verificar ownership: `Enum.find(list, &(&1.id == id and &1.api_id == api.id))`. Assigns podem estar stale; DOM pode ser manipulado
> - Toda acao pareada (publish/unpublish, activate/deactivate) precisa de AMBAS entradas no Policy — nao assumir que uma cobre a outra
> - Funcoes de dominio com dois structs relacionados DEVEM pin match FK no function head: `def f(%Child{parent_id: pid}, %Parent{id: pid})` — previne IDOR
> - `Plug.Conn.fetch_query_params/1` DEVE ser chamado antes de acessar `conn.query_params` fora do pipeline padrao
> - `Task.Supervisor` DEVE ter `max_children` configurado — default e `:infinity`, causa OOM sob carga
> - Retorno de `Task.Supervisor.start_child/2` DEVE ser verificado — pode falhar silenciosamente se supervisor esta down ou max_children atingido
> - Todo campo numerico em schemas DEVE ter `validate_number` com range — nunca confiar que caller passa valores validos
> - Smoke test de deploy deve aceitar APENAS 2xx (200-299) — 4xx/5xx nao e deploy bem-sucedido
> - Antes de chamar `module.init/1` em modulos dinamicos, validar `function_exported?(module, :init, 1)`
> - Hammer 7.x `use Hammer` gera defdelegate — Dialyzer precisa de DOIS ignores: `:unknown_function` E `:callback_info_missing`
> - `Ecto.Multi.run` callback DEVE retornar 2-tupla `{:ok, value}` — nunca 3-tupla. Wrap: `{:ok, {a, b}}`
> - Auditoria pos-implementacao: timing attacks, IDOR em eventos LiveView, Policy actions completas, ownership validation, Task.Supervisor limites, XSS tests explicitos

## Fontes de Discovery
- `docs/discovery/07-observability.md` (OpenTelemetry, PromEx, Loki, Grafana, Sentry)

## Pre-requisitos
- Fases 01-09 concluidas (plataforma funcional com Oban ja configurado na Fase 09)

## O que ja existe
- `telemetry_metrics` e `telemetry_poller` no `mix.exs` do app web
- `BlackboexWeb.Telemetry` com metricas base do Phoenix
- `{:oban, "~> 2.18"}` ja adicionado na Fase 09 (necessario para MetricRollup worker)

## Notas sobre dependencias entre fases
> Algumas tarefas de instrumentacao (spans customizados, emissao de eventos) referenciam
> modulos de codegen/LLM/sandbox que devem existir de fases anteriores. As tarefas estao
> marcadas como **[infra]** (pode ser feito agora) ou **[instr]** (depende de modulos anteriores).

---

## 1. OpenTelemetry - Traces

Ref: discovery/07 secao OpenTelemetry/Traces

- [ ] **[infra]** Adicionar ao `mix.exs` de AMBOS os apps (`blackboex` e `blackboex_web`):
  - `opentelemetry ~> 1.5`, `opentelemetry_api ~> 1.4`, `opentelemetry_exporter ~> 1.8`
  - `opentelemetry_semantic_conventions ~> 0.2`
- [ ] **[infra]** Adicionar ao `mix.exs` de `blackboex_web`:
  - `opentelemetry_phoenix ~> 2.0`, `opentelemetry_bandit ~> 0.3`
- [ ] **[infra]** Adicionar ao `mix.exs` de `blackboex`:
  - `opentelemetry_ecto ~> 1.2`
- [ ] **[infra]** Escrever testes:
  - Request HTTP gera span com attrs corretos
  - Query Ecto gera span
  - Spans customizados emitidos para: codegen, llm request, compile, sandbox execute
- [ ] **[infra]** Configurar exporter em `runtime.exs` (OTLP para Tempo)
- [ ] **[infra]** Configurar trace sampler: `:parentbased_traceidratio` com `0.1` para prod, `1.0` para dev/test
- [ ] **[infra]** Registrar OTel handlers em `BlackboexWeb.Application.start/2` ANTES da supervision tree iniciar
- [ ] **[infra]** Criar modulo central de emissao de eventos: `Blackboex.Telemetry.Events`
  - `emit_llm_call/1` — emite evento telemetry para chamadas LLM
  - `emit_api_invocation/1` — emite evento telemetry para invocacoes de API
  - Todas as funcoes com `@spec`
- [ ] **[instr]** Implementar spans customizados (prefixo `blackboex.`):
  - `blackboex.codegen.generate` com attrs: template_type, description_length
  - `blackboex.llm.request` com attrs: provider, model, input_tokens, output_tokens
  - `blackboex.codegen.compile` com attrs: api_id, success
  - `blackboex.sandbox.execute` com attrs: api_id, duration_ms
  - `blackboex.registry.lookup` com attrs: api_id, found
- [ ] **[instr]** Propagar trace context nos requests dinamicos
- [ ] Verificar: traces aparecem no Tempo com spans corretos

## 2. PromEx - Metricas Prometheus

Ref: discovery/07 secao PromEx/Metricas

- [ ] **[infra]** Adicionar `{:prom_ex, "~> 1.11"}` ao `mix.exs` de `blackboex_web`
- [ ] **[infra]** Escrever testes:
  - Endpoint `/metrics` retorna metricas Prometheus
  - Metricas de API incrementam apos invocacao
  - Metricas de LLM incrementam apos geracao
- [ ] **[infra]** Implementar `BlackboexWeb.PromEx` com plugins:
  - `PromEx.Plugins.Beam`, `Phoenix`, `Ecto`, `Oban`, `Application`
  - Nota: modulo em `BlackboexWeb.PromEx` (app web) pois depende de Phoenix Endpoint/Router
- [ ] **[infra]** Adicionar `BlackboexWeb.PromEx` como PRIMEIRO child na supervision tree (antes de Telemetry e Endpoint)
- [ ] **[instr]** Implementar plugin `BlackboexWeb.PromEx.Plugins.ApiMetrics`:
  - `blackboex_api_invocation_duration_milliseconds` (histogram)
  - `blackboex_api_invocations_total` (counter)
  - `blackboex_api_active_count` (gauge)
- [ ] **[instr]** Implementar plugin `BlackboexWeb.PromEx.Plugins.LlmMetrics`:
  - `blackboex_llm_request_duration_milliseconds` (histogram)
  - `blackboex_llm_tokens_total` (counter)
  - `blackboex_llm_cost_cents_total` (counter)
  - `blackboex_llm_errors_total` (counter)
- [ ] **[infra]** Expor `/metrics` endpoint: adicionar `PromEx.Plug` no `endpoint.ex` ANTES do router
- [ ] Verificar: metricas acessiveis e incrementando

## 3. LoggerJSON - Logs Estruturados

Ref: discovery/07 secao Logs/LoggerJSON

- [ ] **[infra]** Adicionar `{:logger_json, "~> 7.0"}` ao `mix.exs` root ou de `blackboex`
- [ ] **[infra]** Escrever testes:
  - Log output e JSON valido
  - Log contem request_id
  - Log contem trace_id e span_id quando disponivel
  - Log contem user_id e api_id quando no contexto
- [ ] **[infra]** Configurar LoggerJSON como formatter em `runtime.exs`:
  ```elixir
  config :logger, :default_handler,
    formatter: {LoggerJSON.Formatters.GoogleCloud, metadata: :all}
  ```
- [ ] **[infra]** Adicionar `config :phoenix, :logger, false` em prod `runtime.exs` para evitar logs duplicados com structured logging
- [ ] **[infra]** Implementar `Blackboex.Logging`:
  - `with_api_context/2` — adiciona api_id ao Logger metadata
  - `with_user_context/2` — adiciona user_id
- [ ] Verificar: logs em JSON com correlacao

## 4. Sentry - Error Tracking

Ref: discovery/07 secao Sentry/ErrorTracking

- [ ] **[infra]** Adicionar `{:sentry, "~> 12.0"}` ao `mix.exs` de `blackboex_web`
- [ ] **[infra]** Escrever testes:
  - Erro 500 e reportado ao Sentry (mock)
  - Erro 404 NAO e reportado
  - Ecto.NoResultsError NAO e reportado
  - Contexto (user_id, api_id) incluido nos reports
- [ ] **[infra]** Configurar Sentry com DSN via env var
- [ ] **[infra]** Integrar no `endpoint.ex`:
  - `Sentry.PlugCapture` ANTES de `use Phoenix.Endpoint`
  - `Sentry.PlugContext` DEPOIS de `Plug.Parsers`
- [ ] **[infra]** Adicionar LiveView hook: `on_mount Sentry.LiveViewHook` no router
- [ ] **[infra]** Filtrar erros esperados
- [ ] Verificar: apenas erros reais reportados

## 5. Stack Docker Compose

Ref: discovery/07 secao Infraestrutura/Docker

> **Nota:** Esta secao deve ser implementada ANTES dos Dashboards (secao 6), pois
> dashboards precisam de infraestrutura rodando.

- [ ] Criar `docker-compose.observability.yml`:
  - Prometheus (scraping `/metrics`)
  - Grafana (porta 3000)
  - Loki (recebe logs)
  - Promtail (coleta logs do stdout)
  - Tempo (recebe traces OTLP)
- [ ] Criar arquivos de configuracao:
  - `infra/prometheus.yml` — scrape config apontando para app
  - `infra/tempo.yaml` — configuracao do Tempo receiver/storage
  - `infra/loki-config.yaml` — configuracao do Loki
  - `infra/promtail-config.yaml` — configuracao do Promtail para coletar logs
  - `infra/grafana/provisioning/datasources/datasources.yaml` — provisionar Prometheus, Loki, Tempo automaticamente
- [ ] Provisionar datasources no Grafana (Prometheus, Loki, Tempo)
- [ ] Adicionar `make observability` no Makefile
- [ ] Verificar: `make observability` sobe stack e Grafana acessivel

## 6. Dashboards Grafana

Ref: discovery/07 secao Dashboards/Grafana

> **Pre-requisito:** Stack Docker Compose (secao 5) deve estar rodando.

- [ ] Criar dashboard "BlackBoex Overview":
  - Request rate, latencia P50/P95/P99, error rate, APIs ativas
- [ ] Criar dashboard "API Gateway":
  - Invocacoes por API (top 10), latencia por API, erros, rate limit hits
- [ ] Criar dashboard "LLM":
  - Requests por provider, latencia, tokens, custo acumulado, erros
- [ ] Criar dashboard "BEAM VM":
  - Memoria, processos, schedulers, run queue, message queue
- [ ] Exportar dashboards como JSON (versionamento)
- [ ] Verificar: dashboards mostram dados reais

## 7. Per-API Analytics (User-Facing)

Ref: discovery/07 secao Analytics/PerAPI

- [ ] Escrever testes para schema `Blackboex.Apis.MetricRollup`:
  - Changeset valido com api_id, date, invocations, errors, durations
  - Unique api_id + date + hour
- [ ] Criar migration para tabela `api_metric_rollups`:
  - `id` (UUID), `api_id`, `date`, `hour` (nullable), `invocations`,
    `errors`, `avg_duration_ms`, `p95_duration_ms`, `unique_consumers`
  - unique index `[:api_id, :date, :hour]`
- [ ] Verificar que `{:oban, "~> 2.18"}` esta disponivel (adicionado na Fase 09). Caso contrario, alternativa: usar GenServer + `:timer` para agendamento.
- [ ] Escrever testes para Oban worker `Blackboex.Apis.MetricRollupWorker`:
  - Agrega invocation_logs corretamente
  - Idempotente (re-executar nao duplica)
- [ ] Implementar worker
- [ ] Escrever testes LiveView para `ApiLive.Analytics`:
  - Grafico de invocacoes por dia
  - Grafico de latencia P95
  - Taxa de erro
  - Seletor de periodo: 24h, 7d, 30d
- [ ] Implementar LiveView com charts em SVG inline (sem dependencia JS)
- [ ] Verificar: analytics mostram dados reais

## 8. Health Checks

Ref: discovery/07 secao HealthCheck/Kubernetes

- [ ] Escrever testes para `BlackboexWeb.Plugs.HealthCheck`:
  - GET `/health/live` retorna 200 sempre
  - GET `/health/ready` retorna 200 se DB acessivel
  - GET `/health/ready` retorna 503 se DB indisponivel
  - GET `/health/startup` retorna 200 se app iniciou
  - Resposta JSON com status e checks
- [ ] Implementar como Plug no `endpoint.ex` (PRIMEIRO plug, antes de qualquer outro):
  - Garante que `/health` funciona mesmo se o router tiver erros
  - DB: `Blackboex.Repo.query("SELECT 1")`
  - Registry inicializado
  - Vault inicializado
- [ ] Verificar: health checks corretos

## 9. BEAM Monitoring & Alertas

Ref: discovery/07 secao 10.2 (BEAM Monitoring)

- [ ] **[infra]** Adicionar `{:recon, "~> 2.5"}` e `{:observer_cli, "~> 1.8"}` ao `mix.exs` root (only `:dev`)
- [ ] **[infra]** Implementar `Blackboex.Monitoring.BeamMonitor` usando `:telemetry_poller` com measurement functions diretamente:
  - Emite telemetry events para processos com maior message queue
  - Emite telemetry para memoria e run queue
  - Nota: usar `:telemetry_poller` com `:measurements` — nao precisa de GenServer separado. Ref: discovery/07 secao 10.2
- [ ] Configurar alertas no Grafana:
  - Critico: error rate > 10% por 5min, BEAM memory > 80%
  - Warning: P95 latencia > 2s, LLM cost > $100/dia, process count > 100k
- [ ] Verificar: alertas disparam com dados simulados

## 10. Qualidade

- [ ] `mix format --check-formatted` passa
- [ ] `mix credo --strict` passa
- [ ] `mix dialyzer` passa
- [ ] `make precommit` passa
- [ ] `@spec` em todas as funcoes publicas

---

## Criterios de Aceitacao

- [ ] Traces distribuidos no Grafana Tempo
- [ ] Metricas Prometheus em `/metrics`
- [ ] Logs JSON com trace correlation
- [ ] Sentry captura erros 500, ignora 4xx
- [ ] `make observability` sobe stack completa
- [ ] 4 dashboards Grafana com dados reais
- [ ] Analytics por API visivel para o dono (charts SVG)
- [ ] Health checks como Plug no endpoint (funciona independente do router)
- [ ] Alertas configurados e testados
- [ ] `make precommit` passa
- [ ] 100% TDD
