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
