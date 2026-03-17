# Fase 02 - Integracao LLM & Geracao de Codigo

> **Entregavel testavel:** Usuario descreve uma API em linguagem natural,
> o sistema chama um LLM e retorna codigo Elixir gerado com streaming em tempo real.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **PREREQUISITO:** Se Fase 01 NAO estiver implementada, este plano NAO pode ser executado.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - Ao adicionar deps com DSL/macros (ex: `req_llm`, `instructor_lite`, `ex_rated`), verificar se precisam de `import_deps` no `.formatter.exs` do app
> - Usar `@moduletag :unit` (nao `@tag :unit`) para tags de teste no modulo
> - Usar `System.unique_integer([:positive])` em fixtures (negativos geram hyphens em slugs)
> - Slug da API: validar formato, comprimento, e edge cases (unicode, vazio, especiais) — mesma abordagem da Organization
> - Nunca usar `Repo.get!` com dados vindos da sessao ou params do usuario — usar `Repo.get` + pattern match
> - Rodar `mix format`, `mix credo --strict`, `mix dialyzer`, `make test` apos cada bloco de implementacao
> - Atualizar `.dialyzer_ignore.exs` se Ecto.Multi gerar falso positivo `call_without_opaque`

## Fontes de Discovery
- `docs/discovery/01-llm-providers.md` (ReqLLM, InstructorLite, pipeline)
- `docs/discovery/03-api-creation.md` (templates, prompt engineering)

## Pre-requisitos
- Fase 01 concluida

## O que ja existe
- Mox configurado para mocks em testes
- ExMachina para factories

---

## 1. Dependencias & Behaviour LLM

Ref: `docs/discovery/01-llm-providers.md` (ReqLLM, behaviours, rate limiting)

- [x] Adicionar ao `mix.exs` do app dominio:
  - `req_llm ~> 1.7`
  - `instructor_lite ~> 1.2` (corrigido de ~> 0.4)
  - `ex_rated ~> 2.1`
- [x] Escrever teste para behaviour `Blackboex.LLM.ClientBehaviour`:
  - Define callback `generate_text(prompt :: String.t(), opts :: keyword()) :: {:ok, %{content: String.t(), usage: map()}} | {:error, term()}`
  - Define callback `stream_text(prompt :: String.t(), opts :: keyword()) :: {:ok, Enumerable.t()} | {:error, term()}`
- [x] Criar behaviour `Blackboex.LLM.ClientBehaviour`
- [x] Criar implementacao real `Blackboex.LLM.ReqLLMClient`:
  - Delega para `ReqLLM.generate_text/3` usando `ReqLLM.Context.new/1`
  - Formato de modelo: `"provider:model-name"` (ex: `"anthropic:claude-sonnet-4-20250514"`)
- [x] Criar arquivo `apps/blackboex/test/support/mocks.ex` com `Mox.defmock(Blackboex.LLM.ClientMock, for: Blackboex.LLM.ClientBehaviour)`
- [ ] Criar arquivo `apps/blackboex/test/support/factory.ex` com `Blackboex.Factory` usando ExMachina (se nao criado na Fase 01)
- [x] Configurar em `config/test.exs`: usar ClientMock nos testes
- [x] Configurar em `config/dev.exs` e `config/prod.exs`: usar ReqLLMClient
- [x] Verificar: mock funciona nos testes, real funciona em dev

## 2. Configuracao de Providers

Ref: `docs/discovery/01-llm-providers.md` (providers, config, fallback)

- [x] Escrever testes para `Blackboex.LLM.Config`: `@moduletag :unit`
  - `default_provider/0` retorna provider configurado
  - `providers/0` lista providers disponiveis
  - `get_provider/1` retorna config de provider especifico
  - Provider tem: name, model, api_key_env
- [x] Implementar `Blackboex.LLM.Config` lendo de `runtime.exs`
- [x] Configurar em `config/runtime.exs`:
  - Anthropic (Claude Sonnet 4 como default)
  - OpenAI (GPT-4o como fallback)
  - Chaves via env vars: `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`
  - Config `:req_llm`: `config :req_llm, anthropic_api_key: System.get_env("ANTHROPIC_API_KEY")` etc.
- [x] Implementar provider fallback: `Config.fallback_models/0` retorna lista de modelos para fallback
- [x] Verificar: config carrega corretamente

## 3. Sistema de Prompts

Ref: `docs/discovery/03-api-creation.md` (templates, prompt engineering); `docs/discovery/01-llm-providers.md` (InstructorLite)

- [x] Escrever testes para `Blackboex.LLM.Prompts`: `@moduletag :unit`
  - `system_prompt/0` contem instrucoes de seguranca (sem File, System, etc)
  - `system_prompt/0` instrui retornar APENAS corpo da funcao handler (nao modulo completo)
  - `system_prompt/0` contem lista de modulos permitidos e lista de modulos proibidos
  - `build_generation_prompt/2` (description, template_type) inclui descricao do usuario
  - `build_generation_prompt/2` inclui template correto para cada tipo
- [x] Implementar `Blackboex.LLM.Prompts`
- [x] Escrever testes para `Blackboex.LLM.Templates`: `@moduletag :unit`
  - Template `:computation` gera wrapper para funcao pura
  - Template `:crud` gera wrapper com operacoes CRUD
  - Template `:webhook` gera wrapper para processar payload
- [x] Implementar `Blackboex.LLM.Templates`
- [x] Escrever testes para embedded schema `Blackboex.LLM.Schemas.GeneratedEndpoint`: `@moduletag :unit`
  - Campos: handler_code, method, description, example_request, example_response, param_schema
  - Validacao via Ecto changeset
- [x] Implementar `Blackboex.LLM.Schemas.GeneratedEndpoint`
- [x] Verificar: prompts gerados contem instrucoes corretas

## 4. Pipeline de Geracao

Ref: `docs/discovery/03-api-creation.md` (pipeline, classificacao); `docs/discovery/01-llm-providers.md` Section 8.3

- [x] Escrever testes para `Blackboex.CodeGen.Pipeline`: `@moduletag :unit`
  - `generate/2` com mock retorna `{:ok, %GenerationResult{}}`
  - `GenerationResult` tem: code, template, description, provider, tokens_used, duration_ms, method, model, example_request, example_response, param_schema
  - Pipeline classifica tipo corretamente:
    - `:crud` — keywords: CRUD, store, list, database, banco, armazenar, listar
    - `:webhook` — keywords: webhook, receive, callback, receber, notificacao
    - `:computation` — default (quando nenhuma outra categoria)
  - Pipeline extrai codigo do markdown code block da resposta LLM usando regex `~r/```(?:elixir)?\n(.*?)```/s`
  - Pipeline retorna `{:error, reason}` quando LLM falha
  - Pipeline retorna `{:error, reason}` quando resposta nao contem codigo
- [x] Implementar struct `Blackboex.CodeGen.GenerationResult` com campos: code, template, description, provider, tokens_used, duration_ms, method, model, example_request, example_response, param_schema
- [x] Implementar `Blackboex.CodeGen.Pipeline`:
  1. Classificar tipo de API via heuristica na descricao (keywords)
  2. Selecionar template
  3. Montar prompt com template + descricao
  4. Chamar LLM (via behaviour/mock)
  5. Extrair codigo da resposta (regex code block)
  6. Retornar `GenerationResult`
- [x] Verificar: pipeline completo funciona com mock

## 5. Schema da API

Ref: `docs/discovery/03-api-creation.md` (schema Api, campos)

- [x] Escrever testes para schema `Blackboex.Apis.Api`: `@moduletag :unit`
  - Changeset valido com name, slug, description, template_type
  - Slug unique scoped por organization, com `validate_format` e `validate_length` (mesma abordagem de Organization)
  - Status default "draft"
  - template_type valido: "computation", "crud", "webhook"
  - method default "POST"
- [x] Criar migration para tabela `apis`:
  - `id` (UUID), `organization_id`, `user_id`, `name`, `slug`, `description`,
    `source_code`, `template_type`, `status`, `param_schema` (jsonb),
    `method` (string, default "POST"), `example_request` (jsonb), `example_response` (jsonb)
  - unique index `[:organization_id, :slug]`
- [x] Implementar schema `Blackboex.Apis.Api`
- [x] Escrever testes para contexto `Blackboex.Apis`: `@moduletag :unit`
  - `create_api/1` cria API em status draft
  - `list_apis/1` retorna APIs da org
  - `get_api/2` retorna API por id na org (retorna nil para dados de sessao/params)
  - `update_api/2` atualiza campos
- [x] Implementar contexto `Blackboex.Apis`
- [x] Escrever testes para `create_api_from_generation/4`: `@moduletag :unit`
  - Cria Api a partir de um GenerationResult + org + user + name
  - Mapeia campos do GenerationResult para campos do schema Api
- [x] Implementar `create_api_from_generation/4` que cria Api a partir de GenerationResult
- [ ] Criar factory `ApiFactory` com ExMachina
- [x] Verificar: CRUD de APIs funciona

## 6. Streaming para LiveView

Ref: `docs/discovery/01-llm-providers.md` Section 5.3 (streaming, Task + send)

- [x] Escrever teste para `Blackboex.LLM.StreamHandler`: `@moduletag :unit`
  - Usa Task + send pattern (envia mensagens para pid, NAO PubSub)
  - Eventos: `{:llm_token, token}`, `{:llm_done, result}`, `{:llm_error, reason}`
  - Acumula resposta completa
  - Emite evento final `{:llm_done, result}` com resposta completa
- [x] Implementar `Blackboex.LLM.StreamHandler`
- [x] Escrever testes LiveView para `BlackboexWeb.ApiLive.New`: `@moduletag :liveview`
  - Renderiza formulario com textarea e botao "Gerar"
  - Usuario nao logado e redirecionado
  - Apos submit, mostra area de preview (mock do LLM)
  - Apos geracao, mostra campos nome/slug e botao "Salvar"
- [x] Implementar LiveView `BlackboexWeb.ApiLive.New`:
  - Textarea para descricao
  - Botao "Gerar API"
  - Area de preview com streaming
  - Campos nome/slug + "Salvar como Rascunho"
- [x] Escrever teste LiveView para `BlackboexWeb.ApiLive.Index`: `@moduletag :liveview`
  - Lista APIs do usuario
  - Mostra nome, status, data de criacao
  - Link para criar nova API
- [x] Implementar LiveView `BlackboexWeb.ApiLive.Index`
- [x] Adicionar rotas no router: `live "/apis", ApiLive.Index`, `live "/apis/new", ApiLive.New`
- [x] Adicionar links na sidebar
- [x] Verificar: fluxo completo — descrever -> gerar -> salvar

## 7. Rate Limiting & Tracking de Uso

Ref: `docs/discovery/01-llm-providers.md` (rate limiting, telemetry); Section 7.2

- [x] Escrever testes para `Blackboex.LLM.RateLimiter`: `@moduletag :unit`
  - Input: `check_rate(user_id, plan)`
  - Bucket key format: `"llm:#{user_id}"`
  - Permite geracoes dentro do limite
  - Bloqueia apos exceder limite
  - Limites diferentes por plano (free: 10/h, pro: 100/h)
- [x] Implementar `Blackboex.LLM.RateLimiter`
- [x] Escrever testes para schema `Blackboex.LLM.Usage`: `@moduletag :unit`
  - Changeset valido com provider, model, tokens, cost, operation
- [x] Criar migration para tabela `llm_usage`:
  - `id` (UUID), `user_id`, `organization_id`, `provider`, `model`,
    `input_tokens`, `output_tokens`, `cost_cents`, `operation`, `api_id`, `duration_ms`
- [x] Implementar schema `Blackboex.LLM.Usage`
- [ ] Implementar telemetry handler: attach a evento `[:req_llm, :token_usage]` para registrar uso. Ref: `docs/discovery/01-llm-providers.md` Section 7.2
- [x] Verificar: rate limiting funciona

## 8. Qualidade

- [x] `mix format --check-formatted` passa
- [x] `mix credo --strict` passa
- [x] `mix dialyzer` passa
- [x] `make precommit` passa
- [x] `@spec` em todas as funcoes publicas
- [x] Todos os testes escritos ANTES da implementacao

---

## Criterios de Aceitacao

- [x] Usuario logado acessa "Criar API"
- [x] Digita descricao (ex: "API que converte Celsius para Fahrenheit")
- [x] Clica "Gerar" e ve codigo Elixir gerado (streaming via Task+send)
- [x] Pode dar nome e slug
- [x] Salva como rascunho
- [x] API aparece na lista de APIs
- [x] Rate limiting bloqueia apos exceder limite
- [ ] Uso de LLM registrado no banco (telemetry handler pendente)
- [x] `make precommit` passa
- [x] 100% TDD — todos os testes escritos antes da implementacao
