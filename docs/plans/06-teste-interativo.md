# Fase 06 - Teste Interativo de APIs

> **Entregavel testavel:** Usuario testa APIs no browser com request builder completo
> (tipo Postman), ve respostas formatadas, tem historico de requests, e pode gerar
> snippets de codigo para consumir a API.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - Dados de sessao/URL params sao input nao-confiavel — sempre `Repo.get` com fallback, nunca `Repo.get!`
> - Rodar todos os linters apos cada bloco de implementacao
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

## Fontes de Discovery
- `docs/discovery/05-api-testing.md` (test UI, mock data, snippets, contract testing)

## Pre-requisitos
- Fase 03 concluida (APIs compiladas e respondendo HTTP)
- Fase 04 concluida (editor com aba de teste basico — Section 5 substitui "Teste Rapido" da Fase 04)

---

## 1. Request Builder

Ref: discovery/05 section 1.3 (request builder design)

- [ ] Escrever testes LiveView para componente `RequestBuilder` (`@moduletag :liveview`):
  - `RequestBuilder` e um `Phoenix.LiveComponent`
  - Renderiza selector de metodo HTTP (GET, POST, PUT, PATCH, DELETE)
  - Campo de URL pre-preenchido com URL da API
  - Abas via SaladUI Tabs: Params, Headers, Body, Auth
  - Aba Params: tabela chave-valor funcional (add/remove)
  - Aba Headers: Content-Type pre-preenchido
  - Aba Body: textarea para JSON com validacao
  - Aba Auth: campo para API key
  - Botao "Enviar" presente
  - Ctrl+Enter envia request (keyboard shortcut)
- [ ] Implementar `BlackboexWeb.Components.RequestBuilder` como `Phoenix.LiveComponent`
- [ ] Verificar: renderiza com todas as abas

## 2. Response Viewer

Ref: discovery/05 section 1.4 (response viewer design)

- [ ] Escrever testes LiveView para componente `ResponseViewer` (`@moduletag :liveview`):
  - Mostra status badge colorido (2xx verde, 4xx amarelo, 5xx vermelho)
  - Mostra tempo de resposta
  - Aba Body: JSON formatado em Monaco read-only
  - Aba Headers: tabela de headers
  - Estado loading com spinner
  - Estado erro com mensagem
- [ ] Implementar `BlackboexWeb.Components.ResponseViewer`
- [ ] Verificar: respostas formatadas corretamente

## 3. Execucao de Requests

Ref: discovery/05 section 2.1 (request execution, SSRF prevention)

- [ ] Escrever testes para `Blackboex.Testing.RequestExecutor` (`@moduletag :unit`):
  - `execute/1` com request valida retorna response completa (status, headers, body, duration)
  - `execute/1` com timeout retorna `{:error, :timeout}`
  - Protecao SSRF: URL deve corresponder ao pattern `/api/{username}/{slug}/*` em localhost. Qualquer outra URL retorna `{:error, :forbidden}`
  - URLs externas retornam `{:error, :forbidden}`
- [ ] Adicionar `{:req, "~> 0.5"}` ao `mix.exs` do app web (req ja existe no domain app via req_llm, mas web app precisa diretamente)
- [ ] Implementar `Blackboex.Testing.RequestExecutor`:
  - Usa `Req` para fazer HTTP request interno
  - Valida URL contra pattern `/api/{username}/{slug}/*` em localhost
  - Timeout de 30s
  - Retorna `%{status, headers, body, duration_ms}`
- [ ] Escrever teste LiveView: botao "Enviar" dispara request e mostra resposta
- [ ] Integrar no LiveView: evento "send_request" -> executor -> response viewer
- [ ] Verificar: request executado e resposta mostrada

## 4. Historico de Requests

Ref: discovery/05 section 3.1 (request history)

- [ ] Escrever testes para schema `Blackboex.Testing.TestRequest` (`@moduletag :unit`):
  - Changeset valido com api_id, method, path, status, duration
  - Headers sensiveis (Authorization, Cookie, X-Api-Key) sao redactados antes de salvar
- [ ] Criar migration para tabela `test_requests`:
  - `id` (UUID, primary key)
  - `api_id`, `user_id`, `method`, `path`, `headers` (jsonb),
    `body` (text nullable), `response_status`, `response_headers` (jsonb),
    `response_body` (text), `duration_ms`
  - `timestamps(updated_at: false)`
  - Nota: `response_body` truncado a 64KB antes de salvar
- [ ] Implementar schema e salvar cada request/response automaticamente:
  - Redactar valores de headers Authorization, Cookie, X-Api-Key antes de persistir
  - Truncar `response_body` a 64KB
- [ ] Escrever testes LiveView para historico (`@moduletag :liveview`):
  - Lista ultimos 50 requests
  - Cada item: metodo + path + status + tempo
  - Clicar em item carrega request no builder e response no viewer
  - "Limpar historico" funciona
- [ ] Implementar sidebar de historico
- [ ] Nota: limpeza automatica de test_requests com mais de 7 dias sera implementada como Oban job em fase futura
- [ ] Verificar: historico persiste e navega

## 5. Geracao de Dados de Exemplo

Ref: discovery/05 section 4.1 (sample data generation)

- [ ] Escrever testes para `Blackboex.Testing.SampleData` (`@moduletag :unit`):
  - `generate/1` com API que tem param_schema gera dados conforme schema
  - `generate/1` sem param_schema gera dados via heuristica/descricao
  - Gera variantes: happy path, edge case, dados invalidos
  - Edge cases concretos: strings vazias, numeros zero/negativos, valores null, strings muito longas (>1000 chars), caracteres especiais (unicode, emojis, SQL injection patterns)
- [ ] Implementar `Blackboex.Testing.SampleData`
- [ ] Escrever teste LiveView: botao "Gerar exemplo" preenche body
- [ ] Integrar na UI
- [ ] Verificar: dados de exemplo gerados e preenchem body

## 6. Tela de Teste Completa

Ref: discovery/05 section 5.1 (test screen layout)

- [ ] Escrever teste LiveView para tela completa (`@moduletag :liveview`):
  - Request builder no topo
  - Response viewer no meio
  - Historico na lateral (colapsavel)
  - Quick actions: "Testar GET /" e "Testar POST / com exemplo" (usa dados de SampleData da Secao 5)
- [ ] Substituir "Teste Rapido" da Fase 04 pelo componente completo (abordagem inline como aba no editor)
- [ ] Nota: pagina dedicada `/apis/:id/test` sera considerada como melhoria futura se necessario
- [ ] Verificar: tela de teste integrada ao editor

## 7. Code Snippets

Ref: discovery/05 section 8 (code snippet generation)

- [ ] Escrever testes para `Blackboex.Testing.SnippetGenerator` (`@moduletag :unit`):
  - `generate/3` recebe `(api :: %Api{}, language :: atom(), request :: map())` e gera snippet
  - `generate/3` com `:curl` gera cURL valido
  - `generate/3` com `:python` gera Python (requests) valido
  - `generate/3` com `:javascript` gera JavaScript (fetch) valido
  - `generate/3` com `:elixir` gera Elixir (Req) valido
  - `generate/3` com `:ruby` gera Ruby (net/http) valido
  - `generate/3` com `:go` gera Go (net/http) valido
  - Snippets incluem URL, headers, body, API key
- [ ] Implementar `Blackboex.Testing.SnippetGenerator`
- [ ] Escrever teste LiveView: dropdown "Copiar como..." com linguagens
- [ ] Implementar botao com dropdown e copy-to-clipboard
- [ ] Verificar: snippets corretos para cada linguagem

## 8. Validacao de Resposta

Ref: discovery/05 section 6.1 (response validation)

- [ ] Escrever testes para `Blackboex.Testing.ResponseValidator` (`@moduletag :unit`):
  - `validate/2` recebe response e `param_schema` da Api (NAO OpenAPI spec — isso sera Fase 08)
  - `validate/2` com resposta valida retorna []
  - `validate/2` detecta status code inesperado
  - `validate/2` detecta campo ausente no body
  - `validate/2` detecta tipo errado de campo
- [ ] Implementar `Blackboex.Testing.ResponseValidator`
- [ ] Integrar na UI: badge "Valido"/"N violacoes" na resposta
- [ ] Verificar: validacao funciona quando schema disponivel

## 9. Qualidade

- [ ] `mix format --check-formatted` passa
- [ ] `mix credo --strict` passa
- [ ] `mix dialyzer` passa
- [ ] `make precommit` passa
- [ ] `@spec` em todas as funcoes publicas
- [ ] Testes com tags corretas: `@moduletag :unit` para schema/contexto/executor, `@moduletag :liveview` para LiveView, `@moduletag :integration` para fluxos completos

---

## Criterios de Aceitacao

- [ ] Request builder com abas (method incl. PATCH, url, params, headers, body, auth)
- [ ] Response viewer mostra status, body formatado em Monaco read-only, headers, timing
- [ ] Requests executados no backend com protecao SSRF (apenas `/api/{username}/{slug}/*`)
- [ ] Ctrl+Enter envia request
- [ ] Historico persiste e navega, headers sensiveis redactados
- [ ] Dados de exemplo gerados automaticamente (incluindo edge cases)
- [ ] Code snippets em 6 linguagens
- [ ] Validacao de resposta contra param_schema quando disponivel
- [ ] `make precommit` passa
- [ ] 100% TDD
