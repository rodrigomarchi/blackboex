# BlackBoex - Planos de Implementacao

## Estado Atual do Projeto

O projeto ja esta bootstrapped com:

- Umbrella app: `apps/blackboex` (dominio) + `apps/blackboex_web` (web)
- Elixir 1.19.4 / OTP 28, Phoenix 1.8.3, LiveView 1.1, Bandit
- Ecto + PostgreSQL 16 (Docker Compose com DB dev + test)
- Tailwind 4, esbuild, SaladUI, Heroicons
- Credo strict, Dialyxir, Mox, ExMachina, Floki
- Makefile completo (setup, server, test, lint, precommit, etc)

## Metodologia: TDD

**Todo codigo novo segue TDD rigoroso:**

1. **Red** — Escrever o teste primeiro. O teste DEVE falhar.
2. **Green** — Escrever a implementacao minima para o teste passar.
3. **Refactor** — Melhorar o codigo mantendo os testes verdes.

Cada tarefa nos planos comeca por "Escrever teste para X" seguido de "Implementar X".
Os testes sao a especificacao executavel do comportamento esperado.

Tags de teste: `@moduletag :unit`, `@moduletag :integration`, `@moduletag :liveview`
(usar `@moduletag` no topo do modulo; `@tag` so funciona antes de `test`, nao antes de `describe`)

## Visao Geral das Fases

| Fase | Nome | Entregavel Testavel |
|------|------|---------------------|
| 01 | Auth & Organizacoes | Usuario cria conta, faz login, tem org pessoal, RBAC basico |
| 02 | LLM & Geracao de Codigo | Usuario descreve API em linguagem natural e recebe codigo Elixir |
| 03 | Compilacao & Execucao | Codigo gerado compila em sandbox e responde HTTP via rotas dinamicas |
| 04 | Editor & Versionamento | Usuario edita codigo no browser com Monaco, salva versoes |
| 05 | Edicao Conversacional | Usuario refina codigo via chat com LLM, ve diffs, aceita/rejeita |
| 06 | Teste Interativo | Usuario testa API no browser com request builder e historico |
| 07 | Publicacao | API publicada com URL publica, API key auth, rate limiting |
| 08 | Documentacao & Testes Auto | OpenAPI spec gerada, Swagger UI, testes auto-gerados pelo LLM |
| 09 | Billing & Admin | Stripe integrado, painel admin, audit logging |
| 10 | Observabilidade | Telemetria completa, dashboards Grafana, alertas, analytics por API |

## Dependencias entre Fases

```
01 Auth
 └─> 02 LLM
      └─> 03 Compilacao
           ├─> 04 Editor
           │    └─> 05 Chat Edit
           ├─> 06 Teste
           └─> 07 Publicacao
                └─> 08 Docs & Auto-Tests
09 Billing (depende de 01-07)
10 Observabilidade (instrumenta tudo)
```

## Como Usar os Planos

1. Cada plano e um arquivo `.md` com task list em formato checkbox
2. Ao executar um plano, **sempre atualize o progresso** marcando tarefas como `[x]`
3. Nao pule fases — cada uma depende das anteriores
4. Ao final de cada fase, execute os criterios de aceitacao antes de avancar
5. Siga TDD: teste primeiro, implementacao depois

---

## Licoes Aprendidas (Fase 01)

Regras praticas validadas durante a implementacao. **Ler antes de comecar qualquer fase.**

### Testes

- **`@moduletag`** no topo do modulo para tags de teste, nunca `@tag` antes de `describe` (gera warning/erro em ExUnit recente)
- **`System.unique_integer([:positive])`** em fixtures — sem `[:positive]`, numeros negativos criam hyphens inesperados em slugs/nomes
- **Testar LiveView hooks unitariamente** exige `__changed__` no socket assigns: `%Phoenix.LiveView.Socket{assigns: Map.put(assigns, :__changed__, %{})}`
- **Mudancas em rotas default** (ex: `signed_in_path`) quebram muitos testes existentes — atualizar TODAS as assertions de redirect
- **Sempre testar edge cases** alem do happy path: input nil, entidade deletada, membership revogada, slugs com unicode/especiais/vazio

### Umbrella & Phoenix

- **SaladUI em umbrella** precisa de `component_module_prefix: "BlackboexWeb.Components"` no config (sem isso gera `NilWeb`) E um modulo `BlackboexWeb.Component` manual que faz `use Phoenix.Component` + `import SaladUI.Helpers`
- **Componentes SaladUI tem dependencias ocultas** — `sidebar` precisa de `skeleton` e `tooltip`. Instalar e verificar compilacao
- **`phx.gen.auth`** deve rodar de dentro do app web (`cd apps/blackboex_web`), nao da raiz do umbrella
- **Swoosh prod** nao e configurado pelo `phx.gen.auth` — adicionar adapter + credenciais em `runtime.exs`

### Ecto & Dialyzer

- **Nunca usar `Repo.get!` com dados da sessao** — entidade pode ter sido deletada. Usar `Repo.get` + pattern match
- **Ecto.Multi + Dialyzer** gera falso positivo (`call_without_opaque` com MapSet). Manter `.dialyzer_ignore.exs` atualizado
- **LetMe DSL + formatter** — adicionar `import_deps: [:let_me]` no `.formatter.exs` do app que usa, senao `allow role: :owner` vira `allow(role: :owner)`
- **Slugs gerados de input humano** — sempre validar formato (`validate_format`), comprimento (`validate_length`), e unicidade. Testar: unicode, chars especiais, string vazia, muito longo

### Seguranca

- **Dados da sessao sao input nao-confiavel** — org_id, user_id podem referenciar entidades deletadas ou revogadas. Sempre re-verificar membership a cada request
- **Nomes derivados de email** podem colidir (john@a.com e john@b.com) — adicionar sufixo aleatorio para uniqueness

---

## Licoes Aprendidas (Fase 02)

Regras praticas validadas durante a implementacao da integracao LLM. **Ler antes de comecar qualquer fase.**

### Dependencias & Compilacao

- **Versoes no discovery estao desatualizadas** — sempre `mix hex.search <pkg>` para confirmar versao real antes de adicionar ao `mix.exs`
- **`defdelegate` com default args** (ex: ReqLLM, ExRated) gera `unknown_function` no Dialyzer — adicionar ao `.dialyzer_ignore.exs` proativamente
- **Nao usar `%__MODULE__{}` em module attributes** — struct nao esta definida nesse ponto do compile. Usar keyword lists + `struct!/2` em funcoes

### LiveView & Async

- **Trabalho async em LiveView: SEMPRE `Task.async`** + `handle_info({ref, result})` + `handle_info({:DOWN, ...})`. NUNCA `send(self(), :do_work)` pois executa dentro do processo LiveView e bloqueia a UI inteira
- **`defp` entre clausulas `def` do mesmo nome** gera warning "clauses should be grouped together" — agrupar TODAS as clausulas publicas de cada callback primeiro, helpers privados no final do modulo
- **`@module_attr` em templates HEEx** resolve para `assigns`, NAO para module attribute — usar valor hardcoded ou passar como assign no mount
- **Testes LiveView com `Task.async` + Mox** precisam `async: false` — Mox expects sao per-process e Task roda em processo separado

### Integracao com Libs Externas

- **Filtrar opts internos antes de passar a libs externas** — opts como `user_id` vazam para ReqLLM se nao removidos. Usar `Keyword.drop([:user_id, ...])` antes da chamada
- **Templates/prompts NAO podem contradizer regras de seguranca** — ex: template CRUD mencionava Agent/ETS que estavam na lista de modulos proibidos. Auditar consistencia entre prompts e regras

### Validacao & Integridade

- **`%{@module_attr | key: val}` falha se `key` nao existe** no map original — usar `Map.put(@attr, :key, val)` que funciona sempre
- **Campos com default no schema precisam de `validate_inclusion`** — `status` era string livre sem validacao, `name` sem max length, `description` sem max length. Adicionar validacoes de boundary em TODOS os campos string
- **Rate limiting e tracking de uso DEVEM estar wired in** — modulo existir sem ser chamado no fluxo real e pior que nao existir (falsa seguranca). Na auditoria, RateLimiter e Usage existiam mas nenhum era invocado

### APIs Externas & Discovery Docs

- **Discovery docs tem exemplos de API ERRADOS** — ReqLLM.Response nao tem `.content`; a API real e `ReqLLM.Response.text(response)`. NUNCA confiar nos exemplos do discovery doc. Sempre verificar a API real com `deps/<pkg>/lib/` ou `mix docs`
- **Deps OTP que precisam de supervision tree** (ex: ExRated com ETS tables) devem ser listados em `extra_applications` no `mix.exs`, senao nao iniciam e causam crash em runtime
- **Erros de libs externas NAO devem ser engolidos** — `{:error, _reason} -> {:error, :llm_failed}` esconde a mensagem real (ex: "credit balance too low"). Sempre logar o erro original e propagar mensagem legivel ao usuario

---

## Licoes Aprendidas (Fase 05)

Regras praticas validadas durante a implementacao da edicao conversacional. **Ler antes de comecar qualquer fase.**

### JSONB & Concorrencia

- **JSONB array read-modify-write tem race condition TOCTOU** — ler array, append em memoria, salvar de volta perde writes concorrentes. Usar `Ecto.Multi` com `SELECT ... FOR UPDATE` para serializar writes. Testar com `Task.async` concorrente
- **JSONB `{:array, :map}` nao tem validacao de schema** — adicionar validacao custom no changeset para estrutura dos maps (ex: enum de roles validos, campos obrigatorios dentro de cada map)
- **JSONB arrays crescem sem limite** — adicionar validacao `max_items` no changeset. Sem isso, memoria do LiveView e tamanho da query crescem indefinidamente. Ex: `@max_messages 500`
- **Pin operator `^` nao funciona em `Repo.update_all` com `fragment`** — usar `Ecto.Multi` com `SELECT FOR UPDATE` + `Repo.update` em vez de tentar SQL inline com fragments pinados

### LiveView & LiveComponent

- **LiveComponent em testes: usar `render(lv)`, NAO o `html` de `live/3`** — o HTML estatico retornado por `live/3` nao inclui conteudo renderizado por LiveComponents. Sempre `render(lv)` para obter HTML conectado
- **LiveComponent NAO herda assigns do parent** — todo assign necessario deve ser passado explicitamente via atributos no template HEEx (ex: `pending_edit={@pending_edit}`, `template_type={@api.template_type}`)
- **Variaveis descartadas `_conv` nao encadeiam** — `{:ok, _conv} = f(conv)` seguido de `{:ok, _conv} = f(conv)` usa o `conv` original nas duas chamadas. Sempre encadear: `{:ok, conv} = f(conv)` quando o resultado e usado adiante

### Erros & UX

- **Erros de LLM/libs devem ser mapeados para mensagens amigaveis** — criar helper `friendly_error/1` que mapeia atomos (`:timeout`, `:rate_limited`, `:econnrefused`) para texto legivel. SEMPRE `Logger.warning` o erro original antes de mostrar mensagem ao usuario
- **Erros de changeset devem ser logados** — `Logger.error("contexto: #{inspect(changeset)}")` antes de `put_flash(:error, "mensagem amigavel")`. Sem logs, debugging em producao e impossivel

### Seguranca & Testes

- **XSS em conteudo dinamico: Phoenix HEEx escapa por padrao** — mas DEVE ser testado explicitamente com payload `<script>alert('xss')</script>` e verificar que renderiza como `&lt;script&gt;`
- **Cascade delete (`on_delete: :delete_all`) deve ser testado** — criar entidade filha, deletar pai, verificar que filha foi removida. Migration correta nao garante que o teste passa
- **Auditar apos implementacao, nao apenas testar** — apos cada secao, revisar: validacao de input, race conditions, erros silenciados, XSS, cascade delete, limites de crescimento

---

## Licoes Aprendidas (Fase 06)

Regras praticas validadas durante a implementacao do teste interativo de APIs. **Ler antes de comecar qualquer fase.**

### Geracao de Codigo/Snippets

- **Interpolacao de valores do usuario em strings de codigo e INJECTION** — NUNCA fazer `"curl -X #{method} '#{url}'"`. Usar funcoes de escaping por linguagem: `shell_escape()` (single-quote wrap + `'\''`), `python_string()` (backslash escape), `js_string()` (backslash + newline), `go_string()` (double-quote escape), `inspect()` para Elixir. Cada linguagem tem seus chars perigosos
- **Backticks em Go raw strings** — Go nao permite backtick dentro de backtick-delimited strings. Escapar via concat: `` ` + "`" + ` ``
- **Testar injection em CADA linguagem gerada** — criar testes com payloads maliciosos (`'; rm -rf /`, `"break`, backticks) e verificar que o escaping funciona

### Autorizacao & IDOR

- **Buscar por ID sem verificar ownership e IDOR** — `Repo.get(TestRequest, id)` retorna qualquer registro. SEMPRE verificar que o recurso pertence ao usuario/org/API corrente via pin match: `{:ok, %{api_id: ^api_id} = item}`. Isso vale para TODA funcao que aceita ID externo
- **Context modules nao tem auth built-in** — funcoes como `get_test_request/1`, `list_test_requests/1` sao abertas. A verificacao DEVE acontecer no LiveView/Controller chamador, nao no context

### SSRF & URLs

- **`URI.parse("//evil.com")` retorna `scheme: nil`** — checar `scheme != nil` sozinho NAO bloqueia protocol-relative URLs. Verificar TAMBEM `host != nil` para rejeitar URLs com host externo
- **SSRF regex deve ancorar no padrao completo** — `~r|^/api/[^/]+/[^/]+|` sem `$` permite subpaths (correto neste caso), mas path traversal (`../`) e neutralizado pelo routing do Plug. Documentar decisao

### LiveView Events & Concorrencia

- **Eventos LiveView vem do cliente — NUNCA confiar** — todo `handle_event` deve validar params com guard clauses: `when method in @valid_methods`. Definir modulo attrs com valores validos: `@valid_methods ~w(GET POST PUT PATCH DELETE)`
- **Task.async concorrente: guardar contra double-submit** — se o usuario clica "Enviar" duas vezes, a segunda Task sobrescreve `test_ref` e a primeira fica orfao. Guard no handler: `def handle_event("send", _, %{assigns: %{loading: true}} = socket), do: {:noreply, socket}`
- **Limpar refs de Task em TODOS os paths de saida** — `test_ref: nil` no handle_info de sucesso, erro E `:DOWN`. Ref stale causa pattern match failure em mensagens futuras
- **`String.to_existing_atom` vs whitelist** — `String.to_existing_atom(user_input)` pode crashar com `ArgumentError`. Preferir whitelist guard: `when lang in @valid_languages` + `String.to_atom(lang)` (seguro porque whitelist impede atom exhaustion)

### Mensagens de Erro

- **`inspect(reason)` em mensagens ao usuario expoe internals** — NUNCA mostrar `inspect()` de erros ao usuario. Usar mensagens amigaveis fixas: "Erro de conexão. Verifique se a API está compilada." Logger.warning com o erro real para debugging

### Schemas & Validacao

- **Todo campo string DEVE ter `validate_length` com max** — `path` sem max permite 1MB+ de dados. `body` sem max permite payloads gigantes. Definir limites: path (2048), body (1MB), response_body (64KB via truncate)
- **Lista de headers sensiveis deve ser abrangente** — Authorization, Cookie, X-Api-Key sao o minimo. Adicionar: X-Auth-Token, X-Access-Token, X-Csrf-Token, Proxy-Authorization, Set-Cookie. Testar cada um

### XSS — Falsos Positivos Comuns

- **Phoenix HEEx `{}` auto-escapa por padrao** — `{@variable}` SEMPRE escapa HTML. `<script>` vira `&lt;script&gt;`. Apenas `raw()` ou `{:safe, ...}` bypassa. NAO gastar tempo corrigindo XSS em HEEx a menos que use `raw()`. MAS: sempre testar explicitamente com payload `<script>` para confirmar
