# Fase 08 - Documentacao Automatica & Testes Auto-Gerados

> **Entregavel testavel:** Cada API publicada tem OpenAPI spec gerada automaticamente,
> Swagger UI embutido, e testes ExUnit gerados pelo LLM que validam o comportamento.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - `open_api_spex` e `ex_json_schema` provavelmente tem macros — verificar `.formatter.exs` e `import_deps`
> - Rodar todos os linters apos cada bloco de implementacao
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 02):**
> - Versoes de deps no discovery podem estar desatualizadas — sempre `mix hex.search <pkg>` antes de adicionar
> - Deps que usam `defdelegate` com default args geram `unknown_function` no Dialyzer — adicionar ao `.dialyzer_ignore.exs`
> - Trabalho async em LiveView DEVE usar `Task.async` + `handle_info({ref, result})` + `handle_info({:DOWN, ...})`. NUNCA `send(self(), :do_work)`
> - Rate limiting, autorizacao e tracking de uso DEVEM ser chamados no fluxo real, nao apenas implementados como modulos soltos
> - Templates e prompts NAO podem contradizer regras de seguranca
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

## Fontes de Discovery
- `docs/discovery/05-api-testing.md` (auto-generated tests, contract testing, test execution)
- `docs/discovery/06-api-publishing.md` (OpenAPI, Swagger UI)

## Pre-requisitos
- Fase 07 concluida (APIs publicadas com URL publica)
- Fase 02 concluida (LLM integration)

---

## 1. Dependencias

Ref: discovery/05 secao 6.4, discovery/06 secao 6

- [ ] Adicionar `open_api_spex ~> 3.22` ao `mix.exs` do app **domain** (`blackboex`) para geracao de specs
- [ ] Adicionar `open_api_spex ~> 3.22` ao `mix.exs` do app **web** (`blackboex_web`) para SwaggerUI plug
- [ ] Adicionar `{:ex_json_schema, "~> 0.10"}` ao `mix.exs` do app domain para validacao de respostas (contract testing)
- [ ] Verificar: `mix deps.get` compila sem erros

## 2. Migrations (antes das implementacoes)

Ref: discovery/05 secoes 3, 5 (schema de docs e testes)

- [ ] Criar migration para adicionar campo `documentation_md` (text, nullable) na tabela `apis`
- [ ] Criar migration para tabela `test_suites`:
  - `id` (UUID), `api_id`, `version_number`, `test_code`, `status`,
    `results` (jsonb), `total_tests`, `passed_tests`, `failed_tests`, `duration_ms`,
    `inserted_at`, `updated_at`
- [ ] Verificar: migrations rodam sem erros

## 3. Geracao de OpenAPI Spec

Ref: discovery/06 secao 6 (OpenAPI generation), discovery/05 secao 6

- [ ] Escrever testes para `Blackboex.Docs.OpenApiGenerator`:
  - `generate/1` com API :computation retorna spec com POST / e GET /
  - `generate/1` com API :crud retorna spec com todos os verbos REST
  - `generate/1` com API :webhook retorna spec com POST /
  - Spec contem: info (titulo, descricao, versao), servers, paths, security
  - Se API tem param_schema, schemas de request/response gerados
  - Spec valida conforme OpenAPI 3.1
  - Serializavel como JSON
  - Serializavel como YAML
- [ ] Implementar `Blackboex.Docs.OpenApiGenerator`
- [ ] Verificar: specs geradas sao validas

## 4. Swagger UI por API

Ref: discovery/06 secao 6 (Swagger UI serving), discovery/05 secao 8

> **URL:** Swagger UI em `/api/:username/:slug/docs` — corresponde ao base path da API.

- [ ] Escrever testes:
  - GET `/api/:username/:slug/docs` retorna HTML com Swagger UI
  - Swagger UI carrega spec JSON da API
  - API nao publicada retorna 404
- [ ] Escrever testes para endpoint de spec:
  - GET `/api/:username/:slug/openapi.json` retorna JSON valido com content-type application/json
  - GET `/api/:username/:slug/openapi.json` para API inexistente retorna 404
- [ ] Implementar endpoint que serve spec JSON: `/api/:username/:slug/openapi.json`
- [ ] Implementar endpoint YAML: `/api/:username/:slug/openapi.yaml`
- [ ] Implementar Swagger UI usando `open_api_spex` SwaggerUI plug:
  - Tema escuro
- [ ] "Try it out" funciona (requests direto do Swagger UI)
- [ ] Adicionar secao de code snippets na pagina de documentacao:
  - cURL, Python (requests), JavaScript (fetch), Elixir (HTTPoison)
  - Ref: discovery/05 secao 8
- [ ] Link "Documentacao" na pagina publica da API
- [ ] Verificar: Swagger UI renderiza e "Try it out" funciona

## 5. Geracao de Testes pelo LLM

Ref: discovery/05 secoes 2.2, 2.3 (prompt template, retry loop)

- [ ] Escrever testes para `Blackboex.Testing.TestGenerator`:
  - `generate_tests/1` com mock LLM retorna codigo ExUnit valido
  - Codigo gerado tem `use ExUnit.Case`
  - Testa cenarios: happy path, input invalido, edge cases
  - Minimo 5 test cases por API
  - Codigo sintaticamente valido (parsea com `Code.string_to_quoted`)
  - Retry loop: se codigo gerado nao compila, erros sao reenviados ao LLM para correcao (ate 3 tentativas)
- [ ] Definir prompt template para geracao de testes:
  - Inclui: descricao da API, codigo fonte, OpenAPI spec, tipo de template
  - Instrucoes claras de formato ExUnit esperado
  - Exemplos de testes bons/ruins
  - Ref: discovery/05 secao 2.2
- [ ] Implementar `Blackboex.Testing.TestGenerator`:
  - Usa LLM com prompt template definido
  - Prompt inclui: descricao, codigo, OpenAPI spec, template type
  - Parse e valida resposta com `Code.string_to_quoted`
  - Retry loop: generate -> compile-check -> se erros, envia erros de volta ao LLM -> retry (max 3x)
  - Ref: discovery/05 secao 2.3
- [ ] Verificar: testes gerados sao validos (com mock)

## 6. Schemas de Test Suite

Ref: discovery/05 secao 3 (test persistence)

- [ ] Escrever testes para schema `Blackboex.Testing.TestSuite`:
  - Changeset valido com api_id, version_number, test_code, status
  - Resultados em jsonb (array de %{name, status, duration, error})
- [ ] Implementar schema `Blackboex.Testing.TestSuite`
- [ ] Verificar: schema funciona com migration criada na secao 2

## 7. Execucao de Testes no Browser

Ref: discovery/05 secoes 4, 7 (test runner, DB isolation, ExUnit programmatic)

- [ ] Escrever testes para `Blackboex.Testing.TestRunner`:
  - `run/1` com testes validos retorna resultados por teste
  - `run/1` com teste com syntax error retorna `{:error, :compile_error}`
  - `run/1` com timeout retorna `{:error, :timeout}`
  - Execucao em processo isolado (30s timeout)
  - DB isolation via Ecto Sandbox durante execucao
- [ ] Implementar `Blackboex.Testing.TestRunner`:
  - Executar ExUnit programaticamente:
    1. `ExUnit.configure(autorun: false)`
    2. Compilar modulo de teste com `Code.compile_string/1`
    3. Executar `ExUnit.run()` em processo isolado
    4. Custom formatter para capturar resultados por teste
  - Timeout de 30s via `Task.async/1` + `Task.yield/2`
  - DB isolation: checkout Ecto Sandbox connection para processo de teste
    - Ref: discovery/05 secao 7
- [ ] Verificar: testes executam e resultados capturados

## 8. UI de Testes

Ref: discovery/05 secao 5 (test UI, user interaction)

> **Nota:** Secao dividida em sub-tarefas para melhor granularidade.

### 8a. Botao "Gerar Testes"
- [ ] Escrever teste LiveView: Aba "Testes" no editor mostra botao "Gerar Testes"
- [ ] Implementar botao "Gerar Testes" que chama `TestGenerator.generate_tests/1`
- [ ] Apos gerar, Monaco editor mostra codigo dos testes (editavel)

### 8b. Botao "Executar Testes"
- [ ] Escrever teste LiveView: Botao "Executar Testes" visivel apos testes gerados
- [ ] Implementar botao que chama `TestRunner.run/1`

### 8c. Lista de Resultados
- [ ] Escrever teste LiveView: Resultados com icone verde/vermelho por teste
- [ ] Escrever teste LiveView: Teste falho expandivel mostra assertion, esperado vs recebido
- [ ] Implementar lista de resultados com expand/collapse

### 8d. Badge de Status
- [ ] Escrever teste LiveView: Badge no header "5/5 testes passando"
- [ ] Implementar badge com contagem

### 8e. Historico de Execucoes
- [ ] Escrever teste LiveView: Historico mostra ultimas 10 execucoes
- [ ] Implementar historico de execucoes

### 8f. Regenerar Testes
- [ ] Escrever teste LiveView: Botao "Regenerar Testes" disponivel
- [ ] Implementar botao que chama `TestGenerator` novamente

- [ ] Verificar: fluxo gerar -> editar -> executar -> ver resultados

## 9. Validacao de Contrato

Ref: discovery/05 secao 6.4 (contract testing, response validation)

> **IMPORTANTE:** `OpenApiSpex.cast_and_validate/4` e para validacao de REQUEST, nao de response.
> Para contract testing de respostas, usar `ExJsonSchema.Validator.validate/2`.

- [ ] Escrever testes para `Blackboex.Testing.ContractValidator`:
  - `validate/2` com resposta conforme spec retorna `[]`
  - `validate/2` com campo ausente retorna violacao
  - `validate/2` com tipo errado retorna violacao
  - `validate/2` com status inesperado retorna violacao
- [ ] Implementar com `ExJsonSchema.Validator.validate/2`:
  - Converter OpenAPI response schema para JSON Schema
  - Validar response body contra schema
  - Retornar lista de violacoes com paths e mensagens
- [ ] Escrever teste LiveView: toggle "Validar contrato" funciona
- [ ] Integrar: validacao automatica em requests de teste (quando ativo)
- [ ] Verificar: violacoes detectadas e reportadas

## 10. Documentacao Markdown pelo LLM

Ref: discovery/05 secao 8 (documentation generation)

> **Nota:** Migration para `documentation_md` ja criada na secao 2.

- [ ] Escrever testes para `Blackboex.Docs.DocGenerator`:
  - `generate/1` com mock LLM retorna Markdown valido
  - Doc contem: descricao detalhada, exemplos request/response, guia de erros, guia auth
- [ ] Implementar `Blackboex.Docs.DocGenerator`
- [ ] Renderizar doc na pagina publica da API (alem do Swagger UI)
- [ ] Verificar: documentacao gerada e exibida

## 11. Qualidade

Ref: discovery/05, discovery/06 (boas praticas gerais)

- [ ] `mix format --check-formatted` passa
- [ ] `mix credo --strict` passa
- [ ] `mix dialyzer` passa
- [ ] `make precommit` passa
- [ ] `@spec` em todas as funcoes publicas

---

## Criterios de Aceitacao

- [ ] OpenAPI 3.1 spec gerada para cada API publicada (JSON e YAML)
- [ ] Swagger UI em `/api/:username/:slug/docs`
- [ ] Spec JSON em `/api/:username/:slug/openapi.json`
- [ ] "Try it out" funciona no Swagger UI
- [ ] Code snippets na pagina de documentacao (cURL, Python, JS, Elixir)
- [ ] LLM gera testes ExUnit que compilam e executam (com retry loop ate 3x)
- [ ] Resultados de testes no browser com status por teste
- [ ] Testes editaveis pelo usuario
- [ ] Validacao de contrato via `ExJsonSchema` detecta respostas fora da spec
- [ ] DB isolation via Ecto Sandbox durante execucao de testes
- [ ] Documentacao Markdown na pagina publica
- [ ] `open_api_spex` no app domain (spec gen) e web (SwaggerUI plug)
- [ ] `make precommit` passa
- [ ] 100% TDD
