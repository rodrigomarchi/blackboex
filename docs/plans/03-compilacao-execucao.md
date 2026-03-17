# Fase 03 - Compilacao & Execucao Segura

> **Entregavel testavel:** Codigo gerado compila em modulo Elixir real, executa
> em sandbox com isolamento de processo, e responde a requisicoes HTTP via rotas dinamicas.

> **IMPORTANTE:** Ao executar este plano, sempre atualize o progresso marcando
> as tarefas concluidas como `[x]`.

> **METODOLOGIA:** TDD — todo codigo comeca pelo teste. Red -> Green -> Refactor.

> **CHECKLIST PRE-EXECUCAO (Licoes Fase 01):**
> - Ao adicionar `{:plug, "~> 1.16"}` ao app dominio, verificar `.formatter.exs` se `plug` tem macros DSL
> - Nunca usar `Repo.get!` com dados de sessao/URL params — usar `Repo.get` + pattern match
> - Rodar todos os linters apos cada bloco de implementacao
> - Atualizar `.dialyzer_ignore.exs` para falsos positivos de Ecto.Multi se necessario
>
> **CHECKLIST PRE-EXECUCAO (Licoes Fase 02):**
> - Versoes de deps no discovery podem estar desatualizadas — sempre `mix hex.search <pkg>` antes de adicionar
> - Deps que usam `defdelegate` com default args (ex: ReqLLM, ExRated) geram `unknown_function` no Dialyzer — adicionar ao `.dialyzer_ignore.exs` proativamente
> - Nao usar `%__MODULE__{}` em module attributes (`@providers [%__MODULE__{...}]`) — struct nao existe nesse ponto. Usar keyword lists + `struct!/2` em runtime
> - Trabalho async em LiveView DEVE usar `Task.async` + `handle_info({ref, result})` + `handle_info({:DOWN, ...})`. NUNCA `send(self(), :do_work)` — isso bloqueia o processo LiveView inteiro
> - Rate limiting, autorizacao e tracking de uso DEVEM ser chamados no fluxo real, nao apenas implementados como modulos soltos — auditar se cada modulo criado esta wired in
> - Templates e prompts NÃO podem contradizer regras de seguranca (ex: template mencionando Agent/ETS quando estao na lista proibida)
> - Filtrar opts internos (`user_id`, etc) antes de passar a libs externas — `Keyword.drop([:user_id])` para nao vazar
> - `%{@module_attr | key: val}` falha se `key` nao existe no map original — usar `Map.put/3`
> - `defp` entre clausulas `def` do mesmo nome gera warning "clauses should be grouped" — agrupar todas as clausulas publicas primeiro, helpers privados depois
> - `@module_attr` em templates HEEx resolve para `assigns`, NAO para module attribute — hardcode ou passar como assign
> - Testes LiveView com `Task.async` + Mox precisam `async: false` — Mox expects sao per-process e Task roda em processo separado
> - Discovery docs tem exemplos de API ERRADOS — NUNCA confiar nos exemplos. Sempre verificar a API real em `deps/<pkg>/lib/`
> - Deps OTP que precisam de supervision tree (ex: ExRated) devem ser listados em `extra_applications` no `mix.exs`
> - Erros de libs externas NAO devem ser engolidos — sempre logar o erro original e propagar mensagem legivel ao usuario

## Fontes de Discovery
- `docs/discovery/03-api-creation.md` (AST validation, sandbox, routing, templates)
- `docs/discovery/06-api-publishing.md` (gateway, request lifecycle)

## Pre-requisitos
- Fase 02 concluida (APIs em draft com codigo gerado)

---

## 1. Validacao AST

Ref: discovery/03 secoes 2.1–2.3 (AST walker, allowlist/blocklist, atom protection)

- [x] Escrever testes para `Blackboex.CodeGen.ASTValidator`:
  - Codigo seguro com modulos permitidos passa: `{:ok, ast}`
  - Codigo com `File.read` falha com razao clara
  - Codigo com `System.cmd` falha
  - Codigo com `:os.cmd` falha
  - Codigo com `:erlang.open_port` falha
  - Codigo com `Process.spawn` falha
  - Codigo com `Code.eval_string` falha
  - Codigo com `send/2` falha
  - Codigo com `receive` falha
  - Codigo com `import` de modulo perigoso falha
  - Codigo com `apply/3` com modulo dinamico falha
  - Codigo usando `Enum`, `Map`, `String`, `List`, `Jason` passa
  - Codigo com syntax error retorna `{:error, parse_error}`
  - Multiplas violacoes retornam lista completa (nao para na primeira)
  - Codigo com atoms desconhecidos em excesso falha (protecao atom table)
- [x] Implementar `Blackboex.CodeGen.ASTValidator`:
  - `validate/1` (code_string) -> `{:ok, ast}` | `{:error, reasons}`
  - `Code.string_to_quoted/2` para parse — usar opcao `static_atoms_encoder` para prevenir exhaustao da atom table. Ref: discovery/03 secao 2.3
  - AST walker com allowlist/blocklist de modulos
  - Allowlist: `Map`, `List`, `Enum`, `String`, `Integer`, `Float`, `Jason`,
    `Keyword`, `Tuple`, `MapSet`, `Date`, `Time`, `DateTime`, `NaiveDateTime`,
    `Regex`, `URI`, `Access`
  - Blocklist: `File`, `System`, `Process`, `Port`, `IO`, `Code`, `Module`,
    `Node`, `Application`, `:os`, `:erlang`, `:ets`, `:dets`, `:mnesia`,
    `:net`, `:gen_tcp`, `:gen_udp`, `:httpc`
- [x] Verificar: `make test` passa com minimo 15 cenarios de AST (26 cenarios)

## 2. Module Builder & Templates

Ref: discovery/03 secoes 2.2–2.3 (templates, Plug modules, module naming)

> **Nota de dependencia:** `apps/blackboex/` nao tem Phoenix como dependencia (CLAUDE.md).
> ModuleBuilder gera modulos Plug, portanto adicionar `{:plug, "~> 1.16"}` como
> dependencia explicita no `mix.exs` do domain app. Plug e leve e nao puxa Phoenix.

- [x] Adicionar `{:plug, "~> 1.16"}` ao `mix.exs` de `apps/blackboex/`
- [x] Escrever testes para `Blackboex.CodeGen.ModuleBuilder`:
  - `build_module/3` — argumentos: `(module_name :: atom(), handler_code :: String.t(), template_type :: atom())`
  - `build_module/3` com handler valido e template `:computation` gera modulo Plug valido
  - `build_module/3` com template `:crud` gera modulo com GET/POST/PUT/DELETE
  - `build_module/3` com template `:webhook` gera modulo com POST
  - Modulo gerado tem nome `Blackboex.DynamicApi.Api_{uuid}`
  - Modulo gerado e codigo Elixir valido (parsea com `Code.string_to_quoted`)
  - Retorno e `{:ok, module_code_string}` (string, nao AST)
- [x] Implementar `Blackboex.CodeGen.ModuleBuilder`:
  - Templates geram modulo Plug completo com `use Plug.Router`
  - Retorna `{:ok, module_code_string}` — codigo como string
  - Template `:computation`: POST / (executa handler), GET / (info)
  - Template `:crud`: GET /, GET /:id, POST /, PUT /:id, DELETE /:id
  - Template `:webhook`: POST / (processa payload)
- [x] Verificar: cada template gera codigo valido

## 3. Compilacao de Modulos

Ref: discovery/03 secoes 2.3, 3.1 (compilacao segura, Module.create vs Code.compile_string)

- [x] Escrever testes para `Blackboex.CodeGen.Compiler`:
  - `compile/2` — argumentos: `(api :: %Api{}, source_code :: String.t())`
  - `compile/2` com codigo valido retorna `{:ok, module}`
  - `compile/2` com codigo invalido retorna `{:error, errors}`
  - `compile/2` valida AST antes de compilar (rejeita codigo inseguro)
  - `unload/1` remove modulo carregado
  - Modulo compilado responde a `function_exported?/3`
  - Recompilar mesmo modulo funciona (hot reload)
- [x] Implementar `Blackboex.CodeGen.Compiler`:
  1. Validar AST com `ASTValidator`
  2. Montar modulo com `ModuleBuilder`
  3. Compilar com `Code.compile_quoted/1` a partir do AST validado
  4. Retornar modulo
- [x] Implementar `unload/1` com `:code.purge/1` + `:code.delete/1`
- [x] Atualizar status da API para "compiled" apos sucesso
  > **Nota:** Enum de status: `draft -> compiled -> published -> archived`.
  > Status enum atualizado no Api schema.
- [x] Verificar: compilacao e descarregamento funcionam
- [x] Adicionar estrategia de limpeza em testes: usar callback `on_exit` para purge de modulos compilados dinamicamente

## 4. Isolamento de Processo (Sandbox)

Ref: discovery/03 secao 3.2 (sandbox, Task.Supervisor, limites de recurso)

- [x] Adicionar `Blackboex.SandboxTaskSupervisor` (Task.Supervisor) a arvore de supervisao em `Blackboex.Application`
- [x] Escrever testes para `Blackboex.CodeGen.Sandbox`:
  - `execute/3` — argumentos: `(module :: atom(), params :: map(), opts :: keyword())`
  - `execute/3` com funcao normal retorna `{:ok, response}` dentro do timeout
  - `execute/3` com loop infinito retorna `{:error, :timeout}` apos 5s
  - `execute/3` com alocacao excessiva retorna `{:error, :memory_exceeded}`
  - `execute/3` com excecao retorna `{:error, {:exception, message}}`
  - Processo isolado morre sem afetar caller
- [x] Implementar `Blackboex.CodeGen.Sandbox`:
  - Executa via `Task.Supervisor.async_nolink(Blackboex.SandboxTaskSupervisor, ...)` com `max_heap_size: 10_000_000` (10MB)
  - Timeout de 5000ms
  - Captura erros, timeouts, memory exceeded
  - Inclui `execute_plug/3` para execucao de modulos Plug
- [x] Verificar: isolamento funciona para todos os cenarios

## 5. Data Store para APIs CRUD

Ref: discovery/03 secao 4.1 (persistencia JSONB, isolamento por api_id)

- [x] Escrever testes para `Blackboex.Apis.DataStore`:
  - `put/3` — argumentos: `(api_id :: Ecto.UUID.t(), key :: String.t(), value :: map())`
  - `put/3` cria nova entry
  - `put/3` atualiza entry existente (upsert)
  - `get/2` retorna entry ou nil
  - `list/1` retorna todas entries da API
  - `delete/2` remove entry
  - Entries isoladas por api_id (API A nao ve dados da API B)
- [x] Criar migration para tabela `api_data`:
  - `id` (UUID), `api_id`, `key` (string), `value` (jsonb)
  - unique index `[:api_id, :key]`
  - `timestamps()`
- [x] Implementar schema `Blackboex.Apis.DataStore.Entry` e modulo `DataStore`
- [x] Verificar: CRUD + isolamento por API funciona

## 6. API Registry (ETS)

Ref: discovery/03 secao 5.1 (ETS registry, lookup por path, reload)

- [x] Escrever testes para `Blackboex.Apis.Registry`:
  - `register/2` insere api_id -> module no ETS
  - `lookup/1` retorna `{:ok, module}` para API registrada
  - `lookup/1` retorna `{:error, :not_found}` para API nao registrada
  - `lookup_by_path/2` encontra API por username + slug
  - `unregister/1` remove do ETS
  - Registry recarrega APIs compiladas do banco no init
- [x] Implementar GenServer `Blackboex.Apis.Registry`:
  - ETS `:api_registry` com `:set`, `:named_table`, `:public`, `read_concurrency: true`
  - Design de chaves ETS: chave primaria `{api_id}`, indice secundario `{username, slug}` mapeado para api_id. Ref: discovery/03 secao 5.1
  - Reload no `init/1` buscando APIs com status "compiled" ou "published"
- [x] Adicionar `Blackboex.Apis.Registry` a arvore de supervisao em `Blackboex.Application`
- [x] Verificar: lookup O(1), persist restart via reload do banco

## 7. Roteamento Dinamico

Ref: discovery/03 secao 6.1, discovery/06 (gateway, request lifecycle, routing)

> **Nota sobre URL:** Esquema escolhido: `/api/:username/:slug`. Discovery sugeria
> alternativas (subdominio, etc.) — decisao explicita por path-based. Ref: discovery/06.

> **IMPORTANTE:** Phoenix `forward` NAO suporta segmentos de path dinamicos.
> `forward "/:username/:slug"` nao funciona. Usar abordagem catch-all:
> `forward "/api", BlackboexWeb.Plugs.DynamicApiRouter` e parsear
> `conn.path_info` dentro do plug para extrair username e slug.

- [x] Escrever testes de integracao para `BlackboexWeb.Plugs.DynamicApiRouter`:
  - Request para `/api/:username/:slug` com API compilada retorna 200
  - Request para `/api/:username/:slug` com API inexistente retorna 404 JSON
  - Request para `/api/:username/:slug` com API em draft retorna 404
  - Resposta e JSON valido
  - Erros do handler retornam 500 JSON formatado
  - GET retorna info para computation API
- [x] Implementar plug `BlackboexWeb.Plugs.DynamicApiRouter`:
  - Parsear `conn.path_info` para extrair username e slug (nao usar params de forward)
  - Lookup no Registry via `lookup_by_path/2`
  - Delegar para `Sandbox.execute_plug/3` para protecao de recursos (timeout, memory)
  - Capturar erros e retornar JSON
- [x] Adicionar rota no router Phoenix:
  ```elixir
  forward "/api", BlackboexWeb.Plugs.DynamicApiRouter
  ```
- [x] Verificar: requests HTTP chegam e sao despachados corretamente

## 8. Fluxo Completo: Gerar -> Compilar -> Testar

Ref: discovery/03 secao 7.1 (fluxo end-to-end)

- [x] Escrever teste de integracao end-to-end:
  - Criar API com codigo valido
  - Compilar via `Compiler`
  - Registrar no Registry
  - Fazer request HTTP para `/api/:username/:slug`
  - Verificar resposta correta
- [x] Adicionar botao "Compilar" na tela de visualizacao da API
- [x] Escrever teste LiveView:
  - Botao "Compilar" aparece quando API tem source_code
  - Compilacao bem-sucedida mostra badge "Compilado" e URL
  - Compilacao falha mostra erros inline (AST ou compilacao)
- [x] Implementar fluxo na UI:
  - Validar AST -> Montar modulo -> Compilar -> Registrar -> Atualizar status
  - Mostrar erros inline
  - Mostrar URL de teste quando compilado
- [x] Adicionar area simples de teste na UI:
  - URL da API compilada
  - Botao "Testar" que faz GET/POST e mostra resposta
- [x] Verificar: fluxo completo funciona end-to-end

## 9. Qualidade

- [x] `mix format --check-formatted` passa
- [x] `mix credo --strict` passa
- [x] `mix dialyzer` passa
- [x] `make precommit` passa
- [x] `@spec` em todas as funcoes publicas
- [x] Testes de seguranca: minimo 15 cenarios de codigo malicioso no ASTValidator (26 cenarios)
- [x] Testes de isolamento: timeout, memory, runtime errors

---

## Criterios de Aceitacao

- [x] Codigo gerado na Fase 02 pode ser compilado com sucesso
- [x] Modulo compilado responde a requests HTTP em `/api/:username/:slug`
- [x] API `:computation` responde POST com resultado calculado
- [x] API `:crud` suporta GET/POST/PUT/DELETE com persistencia JSONB
- [x] Codigo malicioso rejeitado na validacao AST com mensagens claras
- [x] Loop infinito resulta em timeout (5s) sem afetar o sistema
- [x] Alocacao excessiva de memoria cortada sem afetar o sistema
- [x] Erros de compilacao mostrados na UI com detalhes
- [x] Registry sobrevive restart (recarrega do banco)
- [x] APIs disabled/archived retornam 404/503 (nao registradas no Registry)
- [x] `make precommit` passa
- [x] 100% TDD
