# Fase 07 - Publicacao de APIs

> **Entregavel testavel:** Usuario publica API com um clique, recebe URL publica,
> configura API keys para autenticacao, rate limiting protege contra abuso,
> e consumidores externos conseguem usar a API.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - Slugs em URLs publicas: validar formato, comprimento, edge cases (unicode, vazio, especiais)
> - API keys/tokens: nunca usar `Repo.get!` para lookup — entidade pode ter sido revogada/deletada
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

## Fontes de Discovery
- `docs/discovery/06-api-publishing.md` (gateway, auth, rate limiting, deploy)

## Pre-requisitos
- Fase 03 concluida (APIs compiladas e respondendo)
- Fase 01 concluida (auth, organizacoes)

> **Nota:** Custom domains e API versioning estao diferidos para fases futuras.
> Ref: discovery/06 secoes 9 e 10.

---

## 1. Migration: campos de publicacao na tabela `apis`

Ref: discovery/06 secao 5 (publish flow, visibility)

- [ ] Criar migration para adicionar campos na tabela `apis`:
  - `visibility` enum `:api_visibility` (`:private`, `:public`), default `:private`
  - `requires_auth` boolean, default `true`
- [ ] Escrever testes para os novos campos no schema `Blackboex.Apis.Api`:
  - Changeset valido com `visibility` e `requires_auth`
  - Default de `visibility` e `:private`
  - Default de `requires_auth` e `true`
- [ ] Atualizar schema `Blackboex.Apis.Api` com os novos campos
- [ ] Verificar: migration roda e schema reflete novos campos

## 2. API Keys

Ref: discovery/06 secao 6.3 (key hashing, storage, prefix)

- [ ] Escrever testes para schema `Blackboex.Apis.ApiKey`:
  - Changeset valido com api_id, key_hash, key_prefix, label
  - key_prefix formato: `bb_live_` + primeiros 8 chars hex da key gerada
  - expires_at opcional
  - revoked_at nullable
- [ ] Criar migration para tabela `api_keys`:
  - `id` (UUID), `api_id`, `organization_id`, `key_hash`, `key_prefix`,
    `label`, `last_used_at` (nullable), `expires_at` (nullable),
    `revoked_at` (nullable), `rate_limit` (nullable)
- [ ] Implementar schema `Blackboex.Apis.ApiKey`
- [ ] Escrever testes para contexto `Blackboex.Apis.Keys`:
  - `create_key/2` gera key aleatoria no formato `bb_live_{32 hex chars}`, salva hash SHA-256 via `:crypto.hash(:sha256, key)`, retorna plain UMA VEZ
  - `verify_key/1` com key valida retorna `{:ok, api_key}` (compara hash SHA-256)
  - `verify_key/1` com key invalida retorna `{:error, :invalid}`
  - `verify_key/1` com key revogada retorna `{:error, :revoked}`
  - `verify_key/1` com key expirada retorna `{:error, :expired}`
  - `list_keys/1` retorna keys sem valor plain (so prefix)
  - `revoke_key/1` marca revoked_at
  - `rotate_key/1` revoga antiga e cria nova
- [ ] Implementar contexto `Blackboex.Apis.Keys`:
  - Hash one-way com `:crypto.hash(:sha256, key)` — keys nunca precisam ser decifradas
  - Prefix armazena `bb_live_` + primeiros 8 chars hex para identificacao visual
- [ ] Verificar: lifecycle completo de API keys funciona

> **Nota:** NAO usar Cloak/Cloak.Ecto — sao bibliotecas de ENCRIPTACAO (AES-GCM),
> nao de hashing. API keys precisam apenas de hash one-way (SHA-256).
> Ref: discovery/06 secao 6.3.

## 3. Autenticacao de Requests

Ref: discovery/06 secao 6 (API auth, header/query param)

- [ ] Escrever testes para plug `BlackboexWeb.Plugs.ApiAuth`:
  - Request com header `Authorization: Bearer bb_live_xxx` valido -> 200
  - Request com query param `?api_key=bb_live_xxx` valido -> 200
  - API que requer auth sem key -> 401 JSON
  - Key invalida -> 401 JSON
  - Key revogada -> 401 JSON com "revoked"
  - Key expirada -> 401 JSON com "expired"
  - API com `requires_auth: false` -> passa sem key
  - `last_used_at` atualizado apos uso
- [ ] Implementar plug `BlackboexWeb.Plugs.ApiAuth`
- [ ] Integrar no pipeline do `DynamicApiRouter`
- [ ] Verificar: auth funciona para todos os cenarios

## 4. Rate Limiting

Ref: discovery/06 secao 7.3 (rate tiers, Hammer config)

- [ ] Adicionar `hammer ~> 7.0` ao `mix.exs`
- [ ] Configurar backend explicitamente: `Hammer.Backend.ETS` no config
  (Hammer 7.x exige backend explicito)
- [ ] Escrever testes para plug `BlackboexWeb.Plugs.RateLimiter`:
  - Request dentro do limite -> passa com headers X-RateLimit-*
  - Request alem do limite por IP -> 429 com retry_after
  - Request alem do limite por API key -> 429
  - Request alem do limite global da API -> 429
  - Request alem do limite por endpoint -> 429
  - Headers corretos: X-RateLimit-Limit, X-RateLimit-Remaining, X-RateLimit-Reset
- [ ] Implementar plug com Hammer (4 camadas):
  - Camada 1: IP (100 req/min)
  - Camada 2: API key (60 req/min default, configuravel por key)
  - Camada 3: API global (1000 req/min)
  - Camada 4: Por endpoint (configuravel por rota da API)
- [ ] Integrar no pipeline do `DynamicApiRouter`
- [ ] Verificar: rate limiting funciona em todas as camadas

## 5. Fluxo de Publicacao

Ref: discovery/06 secoes 5, 8 (publish/unpublish, ETS Registry)

- [ ] Escrever testes unitarios para funcoes de dominio:
  - `Blackboex.Apis.publish/1` com API compilada -> `{:ok, api}` com status "published"
  - `Blackboex.Apis.publish/1` com API draft -> `{:error, changeset}`
  - `Blackboex.Apis.unpublish/1` com API publicada -> `{:ok, api}` com status "compiled"
  - `Blackboex.Apis.unpublish/1` com API nao publicada -> `{:error, changeset}`
- [ ] Implementar `Blackboex.Apis.publish/1` e `Blackboex.Apis.unpublish/1`
- [ ] Escrever testes LiveView:
  - Botao "Publicar" visivel quando status = "compiled"
  - Botao nao visivel quando status = "draft"
  - Dialog de confirmacao mostra URL e opcoes (visibility, requires_auth)
  - Apos publicar: status = "published", URL ativa, API key gerada
  - "Despublicar" muda status para "compiled"
- [ ] Implementar fluxo de publicacao:
  - Dialog: URL, toggle "requer auth", visibilidade, gerar API key auto
  - Publicar: status -> "published", registrar no ETS Registry via `Registry.register/1`, gerar key
  - Despublicar: status -> "compiled", remover do ETS Registry via `Registry.unregister/1`, executar `:code.purge/1` para liberar memoria do modulo
- [ ] Verificar: publicar/despublicar funciona end-to-end

## 6. Gerenciamento de API Keys na UI

Ref: discovery/06 secao 6 (key management UI)

- [ ] Escrever testes LiveView para `ApiKeyManager`:
  - Lista keys com prefix, label, ultimo uso, status
  - "Criar nova key" mostra dialog com key plain + aviso
  - "Revogar" marca como revogada (com confirmacao)
  - "Rotacionar" revoga antiga e cria nova
- [ ] Implementar componente `BlackboexWeb.Components.ApiKeyManager`
- [ ] Adicionar aba "Keys" no editor da API
- [ ] Verificar: CRUD de keys funciona na UI

## 7. Pagina Publica da API

Ref: discovery/06 secao 5 (public landing page, URL scheme)

> **URL:** Pagina publica em `/p/:username/:slug` (landing page HTML).
> A rota `/api/:username/:slug` e reservada para invocacoes da API (JSON).
> Isso evita conflito entre servir HTML e JSON na mesma rota.

- [ ] Escrever testes:
  - GET `/p/:username/:slug` retorna pagina publica HTML
  - Pagina mostra nome, descricao, status, exemplo cURL
  - API nao publicada retorna 404
  - GET `/api/:username/:slug` retorna resposta JSON (invocacao)
- [ ] Implementar pagina publica em `/p/:username/:slug`:
  - Nome, descricao, status
  - Exemplo de uso (cURL)
  - "Criada por {username}"
  - Link para docs (placeholder — Fase 08)
- [ ] Verificar: pagina publica acessivel sem auth

## 8. Invocation Logging & Metricas Basicas

Ref: discovery/06 secao 8 (logging, analytics, async persistence)

- [ ] Escrever testes para schema `Blackboex.Apis.InvocationLog`:
  - Changeset valido com api_id, method, status_code, duration
  - `timestamps(updated_at: false)` — log nunca e atualizado
- [ ] Criar migration para tabela `invocation_logs`:
  - `id` (UUID), `api_id`, `api_key_id` (nullable), `method`, `path`,
    `status_code`, `duration_ms`, `request_body_size`, `response_body_size`,
    `ip_address`, `inserted_at` (sem `updated_at`)
  - Indice composto `[:api_id, :inserted_at]` para performance de queries analiticas
- [ ] Implementar schema `Blackboex.Apis.InvocationLog` com `timestamps(updated_at: false)`
- [ ] Implementar logging async via Task.Supervisor:
  - `Task.Supervisor.start_child(Blackboex.LoggingSupervisor, fn -> persist_log(data) end)`
  - Nao bloqueia o request — log e fire-and-forget
  - Adicionar `Blackboex.LoggingSupervisor` a supervision tree
- [ ] Escrever testes para `Blackboex.Apis.Analytics`:
  - `invocations_count/2` retorna contagem por periodo
  - `success_rate/2` retorna porcentagem de 2xx
  - `avg_latency/2` retorna media de duration_ms
- [ ] Implementar queries de analytics
- [ ] Escrever testes LiveView para dashboard de metricas na pagina da API:
  - Mostra invocacoes 24h/7d/30d
  - Mostra taxa de sucesso
  - Mostra latencia media
- [ ] Implementar dashboard basico de metricas
- [ ] Verificar: metricas atualizadas apos invocacoes

## 9. DynamicApiRouter Pipeline

Ref: discovery/06 secao 7 (pipeline order, plug chain)

- [ ] Escrever testes para o pipeline completo do `DynamicApiRouter`:
  - Ordem dos plugs: RateLimiter -> ApiAuth -> execute -> log
  - Request valido passa por todas as etapas na ordem correta
  - Rate limit bloqueado antes de autenticacao
  - Logging ocorre mesmo em caso de erro
- [ ] Implementar/atualizar pipeline do `DynamicApiRouter` com ordem:
  1. `BlackboexWeb.Plugs.RateLimiter`
  2. `BlackboexWeb.Plugs.ApiAuth`
  3. Execucao da API (invoke handler)
  4. Logging async (via Task.Supervisor)
- [ ] Verificar: pipeline executa na ordem correta

## 10. Deploy Zero-Downtime

Ref: discovery/06 secao 8 (deploy, smoke test, rollback)

- [ ] Escrever testes para `Blackboex.Apis.Deployer`:
  - `deploy/2` compila e registra nova versao
  - `deploy/2` executa smoke test antes de ativar
  - Smoke test: cria request de teste com dados de exemplo e verifica resposta 2xx
  - Se smoke test falha, versao anterior mantida
  - `rollback_deploy/1` volta para versao anterior
- [ ] Implementar `Blackboex.Apis.Deployer`:
  - Smoke test cria HTTP request com sample data para o endpoint recem-compilado
  - Verifica que resposta e 2xx antes de promover a versao
  - Em caso de falha, mantem versao anterior ativa
- [ ] Escrever testes LiveView:
  - "Publicando v{N}..." loading
  - "v{N} publicada" verde no sucesso
  - "Deploy falhou — v{N-1} mantida" vermelho no erro
- [ ] Implementar UI de deploy com feedback visual
- [ ] Verificar: deploy sem downtime funciona

## 11. Qualidade

Ref: discovery/06 (boas praticas gerais)

- [ ] `mix format --check-formatted` passa
- [ ] `mix credo --strict` passa
- [ ] `mix dialyzer` passa
- [ ] `make precommit` passa
- [ ] `@spec` em todas as funcoes publicas

---

## Criterios de Aceitacao

- [ ] Publicar torna API acessivel em URL publica
- [ ] `visibility` e `requires_auth` configuraveis por API
- [ ] API keys: criar, listar, revogar, rotacionar (hash SHA-256, sem encriptacao)
- [ ] Requests sem auth valida retornam 401
- [ ] Rate limiting funciona com 4 camadas e headers + 429
- [ ] Pagina publica em `/p/:username/:slug` acessivel sem auth
- [ ] Invocacoes da API em `/api/:username/:slug` retornam JSON
- [ ] Metricas basicas (invocacoes, sucesso, latencia)
- [ ] Pipeline do DynamicApiRouter: RateLimiter -> ApiAuth -> execute -> log
- [ ] ETS Registry atualizado no publish/unpublish
- [ ] Deploy de nova versao sem downtime com smoke test
- [ ] `make precommit` passa
- [ ] 100% TDD
