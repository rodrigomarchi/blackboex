# Fase 09 - Billing & Painel Admin

> **Entregavel testavel:** Plataforma monetizavel com Stripe integration,
> planos free/pro/enterprise, painel admin para operadores, audit logging completo,
> e feature flags para rollout gradual.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - `backpex`, `ex_audit`, `fun_with_flags`, `oban`, `stripity_stripe` — TODAS usam macros/DSL. Adicionar cada uma a `import_deps` no `.formatter.exs` do app correspondente
> - Stripe webhooks usam IDs externos — nunca `Repo.get!` com dados de webhook, sempre `Repo.get` + pattern match
> - Rodar todos os linters apos cada bloco de implementacao
> - Atualizar `.dialyzer_ignore.exs` para falsos positivos se necessario
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 02):**
> - Versoes de deps no discovery podem estar desatualizadas — sempre `mix hex.search <pkg>` antes de adicionar
> - Deps que usam `defdelegate` com default args geram `unknown_function` no Dialyzer — adicionar ao `.dialyzer_ignore.exs`
> - Nao usar `%__MODULE__{}` em module attributes — usar keyword lists + `struct!/2` em runtime
> - Trabalho async em LiveView DEVE usar `Task.async` + `handle_info({ref, result})` + `handle_info({:DOWN, ...})`. NUNCA `send(self(), :do_work)`
> - Rate limiting, autorizacao e tracking de uso DEVEM ser chamados no fluxo real, nao apenas implementados como modulos soltos
> - Filtrar opts internos antes de passar a libs externas — `Keyword.drop([:user_id])`
> - `%{@module_attr | key: val}` falha se `key` nao existe no map — usar `Map.put/3`
> - `defp` entre clausulas `def` do mesmo nome gera warning — agrupar clausulas publicas primeiro, helpers privados depois
> - `@module_attr` em HEEx resolve para `assigns`, NAO module attribute
> - Testes LiveView com `Task.async` + Mox precisam `async: false`
> - Discovery docs tem exemplos de API ERRADOS — NUNCA confiar nos exemplos. Sempre verificar a API real em `deps/<pkg>/lib/`
> - Deps OTP que precisam de supervision tree (ex: ExRated) devem ser listados em `extra_applications` no `mix.exs`
> - Erros de libs externas NAO devem ser engolidos — sempre logar o erro original e propagar mensagem legivel ao usuario
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 03):**
> - Prompts do LLM DEVEM instruir funções puras (`def handle(params)` retornando maps). NUNCA `conn`, `json/2`, `put_status/2` — o template Plug.Router controla HTTP
> - Validar estilo do handler ANTES da compilação: detectar `conn`, `json()`, `put_status()`, `send_resp()` no source_code e rejeitar com erro claro
> - `Plug.Conn` é tied ao processo dono do socket — NUNCA executar módulos Plug em processo separado (Task/Sandbox). Usar try/rescue + max_heap_size no mesmo processo
> - Módulos compilados dinamicamente (Code.compile_quoted) se perdem no restart do servidor — Registry DEVE recompilar do DB no init, e rotas DEVEM ter fallback compile-from-DB
> - `static_atoms_encoder` no Code.string_to_quoted: limite de 100 átomos é MUITO baixo para código real (~95 átomos num handler simples). Usar 500+
> - ETS tables morrem com o GenServer owner — lookup DEVE ter rescue ArgumentError para não crashar se table não existir
> - `handle_continue(:reload)` é assíncrono — requests podem chegar ANTES do reload completar. Usar reload síncrono no init para dados críticos
> - Segurança AST: bloquear Kernel functions (spawn, exit, throw, send, apply), String.to_atom (bypass de blocklist via construção runtime de módulos), Kernel.send/apply (bypass via chamada qualificada), require de módulos perigosos
> - DataStore upsert com read-then-write tem race condition — usar `Repo.insert` com `on_conflict` para true upsert atômico
> - Authorization em LiveView: SEMPRE verificar membership do usuário na org quando org_id vem de query params — nunca confiar no input do cliente
> - Geração de código pelo LLM com prompts antigos produz código incompatível — Compiler deve dar mensagens claras sobre o que está errado (não apenas "compilation failed")
> - HEEx templates: `{` literal (ex: JSON em exemplos) é interpretado como interpolação — usar assigns ou evitar JSON literal em templates
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 04):**
> - `live_monaco_editor` — import path no esbuild umbrella: usar `"live_monaco_editor/priv/static/live_monaco_editor.esm"` (via NODE_PATH), NAO path relativo com `../../deps/`
> - Monaco Editor NAO reage a mudancas de `value` assign apos mount — usar `LiveMonacoEditor.set_value(socket, code, to: path)` para atualizar conteudo programaticamente
> - Version number race condition: NUNCA calcular next version_number fora da transacao. Usar `Ecto.Multi.run` com `SELECT MAX` dentro do Multi
> - `compilation_status` deve ser atualizado na versao apos compilacao — nao deixar como "pending" permanentemente
> - `compile_success` badge deve ser limpo quando o codigo muda — senao usuario ve badge verde com codigo nao-compilado
> - Save sem mudanca: detectar e mostrar "No changes to save" em vez de criar versao duplicada
> - LetMe Policy API: action names sao compostas como `:{object}_{action}` (ex: `:api_update`), NAO `:{action}` separado
> - Dialyzer nao resolve funcoes de deps HEEx (LiveMonacoEditor) — adicionar ao `.dialyzer_ignore.exs` proativamente
> - Codigo duplicado entre LiveViews (resolve_organization, status_color, etc.) — extrair para modulos shared quando atingir 3+ usos
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
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 08):**
> - `Code.compile_string` com `use ExUnit.Case` auto-registra modulos no ExUnit.Server — NUNCA compilar modulos ExUnit dinamicamente sem substituir por macro customizado que NAO registra
> - UUID binary IDs NAO ordenam por tempo de criacao — testes que dependem de ordenacao por ID sao flakey. Testar contagem/membros, nao posicao
> - Campos de usuario (`source_code`, `description`, `name`) interpolados em prompts LLM podem conter ``` que quebra code fences — SEMPRE sanitizar com `sanitize_code_fence/1` e `sanitize_field/1`
> - `TestRunner` retornando `{:ok, []}` (zero testes) e falso positivo perigoso — validar que pelo menos 1 teste foi encontrado antes de retornar sucesso
> - Clausulas `handle_event`/`handle_info` com mesmo nome DEVEM ser agrupadas adjacentes — separar em blocos diferentes gera warning de compilacao
> - Opts de timeout/heap_size que vem de keyword args DEVEM ter cap rigido: `min(user_value, @hard_cap)` — previne DoS via `timeout: :infinity`
> - `Exception.message(e)` pode retornar strings arbitrariamente longas expondo internals — SEMPRE truncar antes de retornar ao usuario (max ~500 bytes)
> - `ContractValidator` e qualquer funcao que navega maps aninhados de specs OpenAPI DEVE checar nil em cada nivel — specs de APIs geradas podem ter paths/methods vazios
> - Deps de um app umbrella usados em outro geram warnings "module not available" no Dialyzer — adicionar a `.dialyzer_ignore.exs` proativamente
> - Helpers de teste DEVEM usar as assinaturas reais das funcoes — SEMPRE `grep` por uso existente nos testes antes de escrever novos helpers
> - Antes de adicionar branch a `cond`/`case` com 3+ branches, extrair para function clauses separados — previne cyclomatic complexity do Credo
> - Regex que parseia code blocks de LLM DEVE usar `[\r\n]` (nao apenas `\n`) e catch-all `_ ->` defensivo

## Fontes de Discovery
- `docs/discovery/02-backoffice-config.md` (Backpex, billing, audit, feature flags)

## Pre-requisitos
- Fases 01-07 concluidas (plataforma funcional)

## Dependencias deste plano

```elixir
# apps/blackboex/mix.exs
{:stripity_stripe, "~> 3.2"},
{:ex_audit, "~> 0.10"},
{:fun_with_flags, "~> 1.0"},
{:oban, "~> 2.18"}

# apps/blackboex_web/mix.exs
{:backpex, "~> 0.17"}
```

---

## 1. Stripe Integration

Ref: discovery/02 secao Billing/Stripe

- [x] Adicionar `{:stripity_stripe, "~> 3.2"}` ao `mix.exs` de `blackboex`
- [x] Adicionar `{:oban, "~> 2.18"}` ao `mix.exs` de `blackboex` (necessario para usage aggregation workers)
- [x] Configurar Oban no `application.ex` e `runtime.exs` (fila `:billing` com intervalo de polling)
- [x] Configurar Stripe via env vars: `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`
- [x] Escrever testes para schema `Blackboex.Billing.Subscription`:
  - Changeset valido com org_id, stripe_customer_id, plan, status
  - Plans validos: "free", "pro", "enterprise"
  - Status validos: "active", "past_due", "canceled", "trialing"
- [x] Criar migration para tabela `subscriptions`:
  - `id` (UUID), `organization_id` (unique), `stripe_customer_id`,
    `stripe_subscription_id`, `plan`, `status`, `current_period_start`,
    `current_period_end`, `cancel_at_period_end`
- [x] Implementar schema `Blackboex.Billing.Subscription`
- [x] Verificar: `mix test` passa com testes do schema

## 2. Checkout & Portal

Ref: discovery/02 secao Billing/Checkout

- [x] Escrever testes para contexto `Blackboex.Billing`:
  - `create_checkout_session/2` chama Stripe e retorna URL (mock Stripe)
  - `create_portal_session/1` retorna URL do portal (mock Stripe)
  - `get_subscription/1` retorna subscription da org
  - `sync_subscription/1` atualiza banco com dados do Stripe
- [x] Implementar contexto `Blackboex.Billing` (com Mox para Stripe em testes)
- [x] Escrever testes LiveView para `BlackboexWeb.BillingLive.Plans`:
  - Mostra 3 cards de planos com features
  - Plano atual destacado
  - Botao "Escolher plano" presente
- [x] Implementar LiveView `BlackboexWeb.BillingLive.Plans`
- [x] Escrever testes LiveView para `BlackboexWeb.BillingLive.Manage`:
  - Mostra status da assinatura
  - Botao "Gerenciar" presente
- [x] Implementar LiveView `BlackboexWeb.BillingLive.Manage`
- [x] Verificar: checkout e portal funcionam (Stripe test mode)

## 3. Webhooks Stripe

Ref: discovery/02 secao Webhooks

- [x] Criar migration para tabela `processed_stripe_events`:
  - `id` (UUID), `event_id` (string, unique), `event_type`, `processed_at`
  - Unique index em `event_id` para idempotencia
- [x] Escrever testes para `BlackboexWeb.WebhookController`:
  - Assinatura invalida retorna 400
  - Evento delegado ao handler correto
  - Evento duplicado (mesmo event_id em `processed_stripe_events`) e idempotente
- [x] Escrever testes para `Blackboex.Billing.WebhookHandler`:
  - `handle_event("checkout.session.completed", payload)` cria/atualiza subscription
  - `handle_event("customer.subscription.updated", payload)` sync plan/status
  - `handle_event("customer.subscription.deleted", payload)` marca canceled
  - `handle_event("invoice.payment_failed", payload)` marca past_due
- [x] Implementar `BlackboexWeb.WebhookController` com verificacao de assinatura e lookup em `processed_stripe_events`
- [x] Implementar `Blackboex.Billing.WebhookHandler` — modulo dedicado com funcoes `handle_event/2` para cada tipo
- [x] Verificar: webhooks processam corretamente

## 4. Usage Tracking

Ref: discovery/02 secao Usage/Metering

- [x] Escrever testes para schema `Blackboex.Billing.UsageEvent`:
  - Changeset valido com org_id, event_type, metadata, timestamp
  - event_type validos: "api_invocation", "llm_generation"
- [x] Criar migration para tabela `usage_events`:
  - `id` (UUID), `organization_id`, `event_type`, `metadata` (jsonb), `inserted_at`
  - Index em `[:organization_id, :inserted_at]`
  - Fonte granular de dados por request (dados brutos para agregar em DailyUsage)
- [x] Implementar schema `Blackboex.Billing.UsageEvent`
- [x] Escrever testes para schema `Blackboex.Billing.DailyUsage`:
  - Changeset valido com org_id, date, contadores
  - Unique org_id + date
- [x] Criar migration para tabela `daily_usage`:
  - `id` (UUID), `organization_id`, `date`, `api_invocations`,
    `llm_generations`, `tokens_input`, `tokens_output`, `llm_cost_cents`
  - unique index `[:organization_id, :date]`
  - Nota: `apis_count` NAO incluido — total de APIs e cumulativo, consultar diretamente da tabela `apis`
- [x] Implementar schema `Blackboex.Billing.DailyUsage`
- [x] Escrever testes para Oban worker `Blackboex.Billing.UsageAggregationWorker`:
  - Agrega `usage_events` do dia anterior em `daily_usage`
  - Idempotente (re-executar nao duplica)
- [x] Implementar worker Oban para agregacao diaria
- [x] Verificar: `mix test` passa com testes de usage tracking

## 5. Enforcement

Ref: discovery/02 secao Enforcement/Limites

> **Pre-requisito:** Depende de modulos das Fases 02, 03 e 07 — `Blackboex.CodeGen.Pipeline` (LLM),
> `Blackboex.Apis` (criacao de APIs), `BlackboexWeb.Plugs.DynamicApiRouter` (invocacoes).
> Implementar enforcement APOS esses modulos existirem.

- [x] Escrever testes para `Blackboex.Billing.Enforcement`:
  - Free: 10 APIs, 1000 invocacoes/dia, 50 geracoes LLM/mes
  - Pro: 50 APIs, 50k invocacoes/dia, 500 geracoes/mes
  - Enterprise: ilimitado
  - `check_limit/2` retorna `{:ok, remaining}` dentro do limite
  - `check_limit/2` retorna `{:error, :limit_exceeded, details}` acima do limite
  - Contagem de APIs consulta `Blackboex.Apis` (nao `daily_usage`)
- [x] Implementar `Blackboex.Billing.Enforcement`
- [x] Integrar enforcement nos pontos de controle especificos:
  - [x] `Blackboex.CodeGen.Pipeline` — antes de gerar codigo LLM
  - [x] `Blackboex.Apis` — antes de criar API
  - [x] `BlackboexWeb.Plugs.DynamicApiRouter` — no gateway (invocacoes)
- [x] Resposta 402 com link para upgrade
- [x] Verificar: limites enforced por plano

## 6. Rotas

Ref: discovery/02 secao Rotas/Router

- [x] Configurar rotas no router para todos os novos escopos:
  - [x] `/billing/*` — LiveViews de planos e gerenciamento (autenticado)
  - [x] `/admin/*` — Backpex admin (requer `is_platform_admin`)
  - [x] `/webhooks/stripe` — WebhookController (sem auth, com verificacao de assinatura)
- [x] Verificar: todas as rotas respondem corretamente

## 7. Admin - Platform Admin Flag

Ref: discovery/02 secao Admin/Autorizacao

- [x] Escrever testes para migration `is_platform_admin`:
  - Campo booleano default false na tabela `users`
  - Platform admin e diferente de org owner (admin da plataforma, nao da organizacao)
- [x] Criar migration: `add :is_platform_admin, :boolean, default: false` na tabela `users`
- [x] Atualizar schema `Blackboex.Accounts.User` com campo `is_platform_admin`
- [x] Escrever testes para plug `BlackboexWeb.Plugs.RequirePlatformAdmin`:
  - Admin (`is_platform_admin: true`) acessa `/admin`
  - Org owner sem flag admin e redirecionado
  - Usuario normal redirecionado
- [x] Implementar plug `BlackboexWeb.Plugs.RequirePlatformAdmin`

## 8. Painel Admin com Backpex

Ref: discovery/02 secao Backpex/Admin

- [x] Adicionar `{:backpex, "~> 0.17"}` ao `mix.exs` de `blackboex_web`
- [x] Configurar DaisyUI com escopo limitado ao `/admin` (Backpex requer DaisyUI, mas o projeto usa SaladUI/Tailwind). Opcoes:
  - CSS com escopo: DaisyUI carregado apenas dentro do layout admin
  - Alternativa: Backpex admin tera seu proprio escopo de estilo separado do app principal
- [x] Criar layout `{BlackboexWeb.Layouts, :admin}` — layout dedicado para Backpex
- [x] Configurar Backpex no router: `/admin` (com plug `RequirePlatformAdmin`)
- [x] Criar LiveResource `BlackboexWeb.Admin.UserLive`:
  - Campos: email, name, is_platform_admin, org count, inserted_at
  - `can?/3`: somente platform admin pode editar/desativar
- [x] Criar LiveResource `BlackboexWeb.Admin.OrganizationLive`:
  - Campos: name, slug, member_count, subscription_plan, inserted_at
  - `can?/3`: platform admin pode editar, ninguem pode deletar
- [x] Criar LiveResource `BlackboexWeb.Admin.ApiLive`:
  - Campos: name, organization, status, invocation_count, inserted_at
  - `can?/3`: platform admin pode desativar
- [x] Criar LiveResource `BlackboexWeb.Admin.SubscriptionLive`:
  - Campos: organization, plan, status, stripe_customer_id, current_period_end
  - `can?/3`: somente leitura
- [x] Criar LiveResource `BlackboexWeb.Admin.InvocationLogLive` (data viewable via dashboard stats):
  - Campos: api_name, status_code, duration_ms, inserted_at
  - `can?/3`: somente leitura, com filtros por data e API
- [x] Criar LiveResource `BlackboexWeb.Admin.LlmUsageLive` (data viewable via dashboard stats):
  - Campos: organization, model, tokens_input, tokens_output, cost_cents, inserted_at
  - `can?/3`: somente leitura
- [x] Dashboard admin com stats (usuarios, APIs, invocacoes)
- [x] Verificar: admin navega e gerencia recursos

## 9. Audit Logging - ExAudit (Row-Level)

Ref: discovery/02 secao Audit/ExAudit

ExAudit rastreia mudancas em nivel de row automaticamente (quem mudou o que, quando).

- [x] Adicionar `{:ex_audit, "~> 0.10"}` ao `mix.exs` de `blackboex`
- [x] Configurar ExAudit no Repo (`use ExAudit.Repo`)
- [x] Gerar migration do ExAudit: `mix audit.gen` (cria tabelas de versioning)
- [x] Implementar plug `BlackboexWeb.Plugs.AuditContext`:
  - Injeta `current_user` no Repo metadata para ExAudit rastrear o actor
  - Adicionar ao pipeline autenticado no router
- [x] Configurar schemas que devem ser rastreados pelo ExAudit (subscriptions, apis, api_keys, organizations)
- [x] Verificar: ExAudit registra versoes de mudancas com actor

## 10. Audit Logging - Custom Audit Logs (Operation-Level)

Ref: discovery/02 secao Audit/OperationLog

Audit logs customizados para operacoes de negocio (acoes explicitas do usuario).

- [x] Escrever testes para `Blackboex.Audit`:
  - Publicar API gera audit log
  - Criar API key gera audit log
  - Revogar key gera audit log
  - Mudar plano gera audit log
  - Log contem: user_id, action, resource_type, resource_id, metadata
- [x] Criar migration para tabela `audit_logs`:
  - `id` (UUID), `user_id`, `organization_id`, `action`, `resource_type`,
    `resource_id`, `metadata` (jsonb), `ip_address`
- [x] Implementar schema e contexto `Blackboex.Audit` para registro de operacoes criticas
- [x] Exibir audit log no admin (Backpex) e na pagina de settings
- [x] Verificar: todas operacoes criticas geram log

## 11. Feature Flags

Ref: discovery/02 secao FeatureFlags

- [x] Adicionar `{:fun_with_flags, "~> 1.0"}` ao `mix.exs` de `blackboex`
- [x] Escrever testes para `Blackboex.Features`:
  - `enabled?/2` retorna true/false conforme flag
  - `enable/2` ativa flag
  - `disable/2` desativa flag
- [x] Implementar `Blackboex.Features` com FunWithFlags (backend Ecto)
- [x] Implementar protocols `FunWithFlags.Actor` e `FunWithFlags.Group`:
  - `FunWithFlags.Actor` para `Blackboex.Accounts.User` — avaliacao de flags por usuario
  - `FunWithFlags.Group` para avaliacao por plano (free/pro/enterprise) — flags habilitadas por tier
- [x] Flags iniciais: `:custom_domains`, `:collaborative_editing`, `:load_testing`
- [x] Integrar flags na UI (esconder features inativas)
- [x] Interface de flags no admin
- [x] Verificar: flags controlam visibilidade

## 12. Settings do Usuario

Ref: discovery/02 secao Settings/UI

- [x] Escrever testes LiveView para `SettingsLive`:
  - Abas renderizam: Perfil, Organizacao, Chaves API, Billing, Seguranca
  - Editar nome funciona
  - Editar nome da org funciona
  - Membros listados com roles
- [x] Implementar LiveView `SettingsLive` com abas SaladUI
- [x] Verificar: todas as abas funcionais

## 13. Qualidade

- [x] `mix format --check-formatted` passa
- [x] `mix credo --strict` passa
- [x] `mix dialyzer` passa
- [x] `make precommit` passa
- [x] `@spec` em todas as funcoes publicas

---

## Criterios de Aceitacao

- [x] Pagina de planos com Stripe checkout
- [x] Webhooks processam corretamente (test mode)
- [x] Limites enforced por plano
- [x] 402 com link para upgrade ao exceder limite
- [x] Admin funcional com CRUD de recursos (somente platform admins)
- [x] ExAudit rastreia mudancas row-level com actor
- [x] Audit logs customizados registram operacoes criticas
- [x] Feature flags controlam features (com Actor/Group protocols)
- [x] Settings do usuario com abas: Perfil, Organizacao, Chaves API, Billing, Seguranca
- [x] `make precommit` passa
- [x] 100% TDD
