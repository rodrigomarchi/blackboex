defmodule Blackboex.Samples.Page do
  @moduledoc """
  Page samples in the platform-wide sample catalogue.

  The list is structured as a documentation tree rooted at "Bem-vindo ao
  Blackboex". Each topic page covers a single subsystem of the platform so
  users land in a managed sample workspace already populated with a coherent
  "manual" they can browse, edit, and copy from.
  """

  alias Blackboex.Samples.Id

  @welcome_uuid Id.uuid(:page, "welcome")
  @guide_uuid Id.uuid(:page, "formatting_guide")

  @spec list() :: [map()]
  def list, do: [welcome() | topics()] ++ [formatting_guide(), elixir_patterns()]

  defp welcome do
    %{
      kind: :page,
      id: "welcome",
      sample_uuid: @welcome_uuid,
      name: "Bem-vindo ao Blackboex",
      title: "[Demo] Bem-vindo ao Blackboex",
      description: "Visão geral da plataforma e como navegar pelos exemplos.",
      category: "Introdução",
      position: 0,
      status: "published",
      content: """
      # Bem-vindo ao Blackboex

      Este projeto **Exemplos** é gerado automaticamente quando sua organização é
      criada. Ele serve como manual interativo: cada artefato (API, Flow, Page e
      Playground) é um exemplo real que você pode abrir, executar e adaptar.

      ## O que você encontra aqui

      - **APIs** — endpoints HTTP gerados a partir de descrições em linguagem natural,
        compilados num sandbox seguro e versionados.
      - **Flows** — orquestrações visuais com nodes (start, código Elixir, HTTP,
        condições, sub-fluxos, aprovação, delay e fim).
      - **Playgrounds** — células únicas de Elixir para experimentar trechos de
        código no sandbox da plataforma, com captura de IO e execução por
        usuário.
      - **Pages** — exatamente o que você está lendo agora: Markdown com
        suporte a Mermaid, listas, tabelas e blocos de código.

      ## Como usar este workspace

      1. **Explore** os exemplos sem medo de quebrá-los — qualquer alteração
         que você fizer é restaurada na próxima sincronização do manifesto.
      2. **Duplique** o que precisar para um projeto seu (botão "mover" em
         cada artefato).
      3. **Crie** projetos próprios na sua organização para trabalho
         definitivo — o workspace de Exemplos é só o playground de leitura.

      ```mermaid
      flowchart LR
        Org[Organização] --> Sample[Projeto Exemplos]
        Org --> Yours[Seus Projetos]
        Sample -.copia.-> Yours
        Yours --> Prod[Produção]
      ```

      ## Próximas páginas

      As demais pages deste workspace cobrem cada subsistema em detalhes.
      Comece por **Conceitos Fundamentais** se for sua primeira vez aqui.
      """
    }
  end

  defp topics do
    [
      topic(
        "concepts",
        1,
        "Conceitos Fundamentais",
        "Plataforma",
        "Organizações, projetos, escopos e como o Blackboex se posiciona.",
        concepts_content()
      ),
      topic(
        "apis",
        2,
        "APIs — Geração com IA",
        "APIs",
        "Como descrever, compilar, validar e invocar APIs HTTP.",
        apis_content()
      ),
      topic(
        "flows",
        3,
        "Flows — Orquestração Visual",
        "Flows",
        "Editor visual, tipos de node, webhook tokens e execução assíncrona.",
        flows_content()
      ),
      topic(
        "playgrounds",
        4,
        "Playgrounds — Sandbox de Elixir",
        "Playgrounds",
        "Single-cell Elixir REPL com captura de IO e helpers HTTP/Api.",
        playgrounds_content()
      ),
      topic(
        "pages_doc",
        5,
        "Pages — Documentação Markdown",
        "Pages",
        "Hierarquia, status, Markdown estendido e Mermaid.",
        pages_content()
      ),
      topic(
        "llms",
        6,
        "Integração com LLMs",
        "AI",
        "Anthropic, OpenAI, circuit breaker, rate limiter e prompts.",
        llms_content()
      ),
      topic(
        "conversations",
        7,
        "Conversations & Runs",
        "AI",
        "Event sourcing das conversas: runs, events e replay.",
        conversations_content()
      ),
      topic(
        "telemetry",
        8,
        "Telemetria & Observabilidade",
        "Operação",
        "OpenTelemetry, eventos, métricas e dashboards.",
        telemetry_content()
      ),
      topic(
        "auth",
        9,
        "Autenticação & Multi-tenancy",
        "Segurança",
        "Scope, sessions, memberships, isolamento por organização.",
        auth_content()
      ),
      topic(
        "audit",
        10,
        "Auditoria de Mudanças",
        "Segurança",
        "ExAudit, AuditLog, escopo admin e trilha imutável.",
        audit_content()
      ),
      topic(
        "feature_flags",
        11,
        "Feature Flags",
        "Operação",
        "FunWithFlags, gates por org/projeto, rollout controlado.",
        feature_flags_content()
      ),
      topic(
        "testing",
        12,
        "Workflow de Testes",
        "Engenharia",
        "TDD obrigatório, fixtures, named setups, separação por tag.",
        testing_content()
      ),
      topic(
        "make_commands",
        13,
        "Comandos Make & Operação",
        "Engenharia",
        "Make targets, Docker, migrations, lint, testes seletivos.",
        make_commands_content()
      ),
      topic(
        "roadmap",
        14,
        "Roadmap & Próximos Passos",
        "Plataforma",
        "Direção do produto e como contribuir com seu workspace.",
        roadmap_content()
      )
    ]
  end

  defp topic(id, position, name, category, description, content) do
    %{
      kind: :page,
      id: id,
      sample_uuid: Id.uuid(:page, id),
      parent_sample_uuid: @welcome_uuid,
      name: name,
      title: "[Demo] #{name}",
      description: description,
      category: category,
      position: position,
      status: "published",
      content: content
    }
  end

  defp formatting_guide do
    %{
      kind: :page,
      id: "formatting_guide",
      sample_uuid: @guide_uuid,
      parent_sample_uuid: @welcome_uuid,
      name: "Guia de Formatação",
      title: "[Demo] Guia de Formatação",
      description: "Markdown editor formatting guide.",
      category: "Documentation",
      position: 15,
      status: "published",
      content: """
      # Guia de Formatação do Editor

      Bem-vindo ao guia de exemplos do Blackboex. Esta página demonstra Markdown,
      listas, tabelas, blocos de código e diagramas Mermaid.

      - **Texto em negrito**
      - `código inline`
      - Listas de tarefas

      ```elixir
      Enum.map([1, 2, 3], &(&1 * 2))
      ```

      ```mermaid
      flowchart TD
        A[Request] --> B[Blackboex]
        B --> C[Response]
      ```
      """
    }
  end

  defp elixir_patterns do
    %{
      kind: :page,
      id: "elixir_patterns",
      sample_uuid: Id.uuid(:page, "elixir_patterns"),
      parent_sample_uuid: @guide_uuid,
      name: "Padrões de Código Elixir",
      title: "[Demo] Padrões de Código Elixir",
      description: "Small Elixir reference page.",
      category: "Documentation",
      position: 16,
      status: "published",
      content: """
      # Padrões de Código Elixir

      ## Pattern Matching

      ```elixir
      with {:ok, user} <- fetch_user(id),
           :ok <- authorize(user) do
        {:ok, user}
      end
      ```
      """
    }
  end

  defp concepts_content do
    """
    # Conceitos Fundamentais

    O Blackboex é uma plataforma multi-tenant para construir, executar e
    monitorar APIs e workflows com geração assistida por IA. Antes de tudo,
    três entidades estruturam o resto:

    | Entidade | Papel |
    |----------|-------|
    | **Organização** | Tenant raiz. Tudo é escopado por `organization_id`. |
    | **Projeto** | Agrupador lógico dentro da org (APIs, Flows, Pages, Playgrounds). |
    | **Membership** | Usuário ↔ Organização (roles: admin, member). |

    ## Scope: o objeto que viaja com você

    Toda LiveView, plug e contexto recebe um `Blackboex.Accounts.Scope` que
    contém o `user` autenticado e a `organization` ativa. Use o scope para:

    - Filtrar consultas (`scope.organization.id`)
    - Verificar permissões (`Blackboex.Policy`)
    - Auditar mudanças (`scope` é injetado nos audits)

    Nunca consulte diretamente por `id` sem cruzar com a org do scope — isso
    evita IDOR (Insecure Direct Object Reference).

    ```mermaid
    flowchart TD
      User[Usuário] -->|login| Session
      Session -->|carrega| Scope
      Scope -->|filtra| Org[(Organização)]
      Org --> P1[Projeto A]
      Org --> P2[Projeto B]
      P1 --> APIs & Flows & Pages & Playgrounds
    ```

    ## Próximo passo

    Veja **Autenticação & Multi-tenancy** para o fluxo completo de login,
    invite-only registration e o on_mount hook que popula o scope.
    """
  end

  defp apis_content do
    """
    # APIs — Geração com IA

    Uma **API** no Blackboex é um endpoint HTTP completo gerado a partir de
    uma descrição em linguagem natural, compilado em sandbox seguro e
    versionado por arquivos.

    ## Ciclo de vida

    ```mermaid
    stateDiagram-v2
      [*] --> draft
      draft --> compiling: compile
      compiling --> compiled: AST + spec OK
      compiling --> draft: erros
      compiled --> deployed: deploy
      deployed --> compiled: nova versão
    ```

    ## Arquivos gerados

    Cada API mantém arquivos em `/src/` e `/test/`:

    | Caminho | Conteúdo |
    |---------|----------|
    | `/src/handler.ex` | Função principal `handle/1` |
    | `/src/helpers.ex` | Helpers privados |
    | `/src/request_schema.ex` | Validação do payload de entrada |
    | `/src/response_schema.ex` | Forma do retorno |
    | `/test/handler_test.ex` | Suite ExUnit gerada junto |
    | `/README.md` | Documentação derivada |

    ## Invocando uma API

    ```bash
    curl -X POST https://localhost:4000/api/<org>/<project>/<api> \\
      -H "Authorization: Bearer <api_key>" \\
      -H "Content-Type: application/json" \\
      -d '{"input": "valor"}'
    ```

    ## Exemplos disponíveis

    Veja a aba **APIs** deste projeto. Há ~19 templates cobrindo: cálculos
    financeiros, validação de documentos, scoring de crédito, webhooks
    (GitHub/Slack), simulação de erros e CRUD de recursos.

    ## Segurança

    - AST validator bloqueia módulos perigosos (`File`, `System`, `Code`,
      `:erlang`, `:os`).
    - Rate limiting por API key (ExRated).
    - Logs de invocação ficam em `InvocationLog` — agregados em
      `MetricRollup`.
    """
  end

  defp flows_content do
    """
    # Flows — Orquestração Visual

    Um **Flow** é uma definição em JSON manipulada por um editor visual.
    Cada Flow tem um `webhook_token` único; quando ativo, recebe POSTs em
    `/webhook/:token`.

    ## Tipos de node

    | Type | Função |
    |------|--------|
    | `start` | Define o schema de entrada |
    | `elixir_code` | Bloco de código com `input` e `state` em escopo |
    | `http_request` | Chamada HTTP externa com timeout |
    | `condition` | Branching booleano |
    | `delay` | Espera N segundos antes de continuar |
    | `sub_flow` | Invoca outro Flow no mesmo projeto |
    | `approval` | Pausa até aprovação manual ou timeout |
    | `end` | Encerra a execução, devolvendo `output` |

    ## Execução

    ```mermaid
    sequenceDiagram
      Cliente->>Webhook: POST /webhook/<token>
      Webhook->>FlowExecutor: dispatch
      FlowExecutor->>NodeExec1: start
      NodeExec1->>NodeExec2: elixir_code
      NodeExec2-->>FlowExecutor: {result, state}
      FlowExecutor-->>Cliente: 200 {output}
    ```

    Cada execução grava `FlowExecution` (status, started_at, finished_at)
    e um `NodeExecution` por node atravessado. Isso vira a base do replay e
    da observabilidade.

    ## Idempotência

    Flows que recebem webhooks podem usar a chave `idempotency_key` no payload.
    O `WebhookProcessor` template demonstra o padrão **check → process → mark**
    para evitar reprocessamento.

    ## Templates inclusos

    Cerca de 28 templates: HelloWorld, Notification, AllNodesDemo, DataPipeline,
    OrderProcessor, BatchProcessor, HttpEnrichment, ApprovalWorkflow,
    RestApiCrud, LeadScoring, WebhookProcessor, SagaCompensation, LlmRouter,
    SubFlowOrchestrator e outros. Estão na aba **Flows**.
    """
  end

  defp playgrounds_content do
    """
    # Playgrounds — Sandbox de Elixir

    Um **Playground** é uma única célula de código Elixir, executada num
    sandbox isolado. É a forma mais rápida de:

    - Experimentar sintaxe e padrões
    - Chamar uma API ou Flow do projeto
    - Ler variáveis de ambiente do projeto (`env`)
    - Prototipar uma transformação antes de promovê-la para uma API

    ## Ambiente de execução

    | Limite | Valor |
    |--------|-------|
    | Timeout | 15s |
    | Heap máximo | 10MB |
    | Output | 64KB (truncado) |
    | HTTP por execução | 5 chamadas, timeout 3s |
    | Rate limit | 10 execuções/min/usuário |

    ## Módulos permitidos (allowlist)

    Apenas: `Enum`, `Map`, `List`, `String`, `Integer`, `Float`, `Tuple`,
    `Keyword`, `MapSet`, `Date`, `Time`, `DateTime`, `NaiveDateTime`, `Calendar`,
    `Regex`, `URI`, `Base`, `Jason`, `Access`, `Stream`, `Range`, `Atom`, `IO`,
    `Inspect`, `Kernel`, `Bitwise`, mais os helpers `Blackboex.Playgrounds.Http`
    e `Blackboex.Playgrounds.Api`.

    **Bloqueado**: `defmodule`, `Function.capture`, `File`, `System`, `:erlang`,
    `:os`, `:code`, `:port`.

    ## Helpers de plataforma

    ```elixir
    alias Blackboex.Playgrounds.Http
    alias Blackboex.Playgrounds.Api

    {:ok, %{status: 200, body: body}} = Http.get("https://example.com")

    Api.call_flow("token", %{"x" => 1})
    Api.call_api(org, project, api, params, api_key)
    ```

    ## Variáveis do projeto

    O binding `env` está disponível como mapa de strings:

    ```elixir
    env["API_URL"]  # ou nil se não setado
    ```

    Configure variáveis em **Project Settings → Env Vars**.

    ## Exemplos disponíveis

    Veja a aba **Playgrounds** — há ~20 exemplos cobrindo Enum, pipe,
    pattern matching, Stream, Date/Time, Regex, HTTP, chamadas de Flow e mais.
    """
  end

  defp pages_content do
    """
    # Pages — Documentação Markdown

    **Pages** são páginas de Markdown organizadas em árvore por projeto.
    Boas para: documentação interna, runbooks, especificações, planejamento e
    exemplos (como esta página).

    ## Hierarquia

    Cada Page tem um `parent_id` opcional. Pages de primeiro nível agrupam
    sub-páginas. A navegação à esquerda reflete a árvore.

    ## Status

    - `draft` — só admins veem
    - `published` — visível a todos os membros do projeto

    ## Markdown estendido

    Suporte a:

    - **Negrito**, *itálico*, `código inline`
    - Listas, listas de tarefas, tabelas
    - Blocos com syntax highlighting
    - **Mermaid** (`flowchart`, `sequenceDiagram`, `stateDiagram-v2`)
    - Links internos para outras Pages

    ## Exemplo de Mermaid

    ```mermaid
    sequenceDiagram
      participant U as Usuário
      participant L as LiveView
      participant C as Contexto
      U->>L: handle_event("save", params)
      L->>C: Pages.update_page(page, attrs)
      C-->>L: {:ok, updated}
      L-->>U: assigns atualizados
    ```

    ## Versão e idempotência

    Pages com `sample_uuid` são gerenciadas pela manifesto. Suas alterações
    são preservadas até a próxima sincronização — depois, o conteúdo é
    restaurado para a versão canônica.
    """
  end

  defp llms_content do
    """
    # Integração com LLMs

    O Blackboex usa LLMs (Anthropic Claude, OpenAI) para:

    - Gerar APIs a partir de descrições naturais
    - Editar código de Playground via chat
    - Sugerir definições de Flow
    - Sumarizar logs e auditorias

    ## Camadas

    ```mermaid
    flowchart LR
      Caller --> Client[Blackboex.LLM.Client]
      Client --> Breaker[Circuit Breaker]
      Breaker --> Limiter[Rate Limiter]
      Limiter --> Provider{Provider}
      Provider -->|Anthropic| Claude
      Provider -->|OpenAI| GPT
    ```

    ## Circuit Breaker

    Após N falhas consecutivas em janela X, o circuito abre. Isso protege:

    - Custo (não queimamos tokens em provider degradado)
    - Latência (falha rápido em vez de esperar timeout)
    - Cascata (não derruba dependentes)

    Estado: `:closed` → `:open` → `:half_open` → `:closed`.

    ## Rate Limiter

    Per-organização e per-modelo. Configurável em `config/runtime.exs`.

    ## Prompts versionados

    Cada subsistema tem seu próprio módulo de prompts:

    - `Blackboex.Agent.Prompts` — geração de API
    - `Blackboex.PlaygroundAgent.Prompts` — chat de Playground
    - `Blackboex.PageAgent.Prompts` — escrita de páginas
    - `Blackboex.FlowAgent.Prompts` — geração de Flow

    Mudanças nos prompts são mudanças semânticas — preferir versionar
    explicitamente em vez de "pequenos ajustes".

    ## Configuração

    ```bash
    export ANTHROPIC_API_KEY=sk-...
    export OPENAI_API_KEY=sk-...
    ```

    Ou setar como variável de projeto (`Blackboex.ProjectEnvVars`).
    """
  end

  defp conversations_content do
    """
    # Conversations & Runs

    Toda interação com IA persiste em **event sourcing**: a conversa é uma
    sequência imutável de eventos.

    ## Modelo

    | Schema | Papel |
    |--------|-------|
    | `Conversation` | Thread (Playground/Page/Flow) |
    | `Run` | Uma rodada do agente (request → response) |
    | `Event` | Item atômico: `tool_call`, `tool_result`, `message`, `error` |

    ## Por que event sourcing

    1. **Replay**: reconstruir o estado a partir dos eventos
    2. **Auditoria**: nada é apagado ou modificado
    3. **Streaming**: enviar eventos para o LiveView via PubSub à medida que
       chegam
    4. **Custo**: cada Event carrega `input_tokens`/`output_tokens` para
       agregação em `LLM.Usage`

    ## Subsistemas separados

    Há tabelas paralelas por domínio para evitar JOIN heterogêneo:

    - `playground_conversations` / `playground_runs` / `playground_events`
    - `page_conversations` / `page_runs` / `page_events`
    - `flow_conversations` / `flow_runs` / `flow_events`

    ## Streaming

    ```mermaid
    sequenceDiagram
      LV as LiveView
      SM as StreamManager
      LLM as LLM Provider
      LV->>SM: start_run(input)
      SM->>LLM: stream_request
      LLM-->>SM: chunk_1
      SM->>LV: PubSub broadcast
      LLM-->>SM: chunk_2
      SM->>LV: PubSub broadcast
      LLM-->>SM: end
      SM->>LV: complete
    ```

    O LiveView faz `Phoenix.PubSub.subscribe/2` no `mount` e atualiza assigns
    via `handle_info/2`.
    """
  end

  defp telemetry_content do
    """
    # Telemetria & Observabilidade

    Blackboex emite eventos `:telemetry` para todos os pontos críticos:

    | Evento | Quando |
    |--------|--------|
    | `[:blackboex, :api, :invocation]` | API HTTP invocada |
    | `[:blackboex, :flow, :execution]` | Flow disparado |
    | `[:blackboex, :playground, :execute]` | Código executado |
    | `[:blackboex, :llm, :request]` | Request enviado ao provider |
    | `[:blackboex, :llm, :response]` | Response (com tokens) |
    | `[:blackboex, :auth, :login]` | Login bem-sucedido/falho |

    ## OpenTelemetry

    Eventos são roteados para OTLP via `Blackboex.Telemetry.Reporter`. Em
    produção, alimenta dashboards Grafana/Tempo.

    ## Métricas agregadas

    `Blackboex.Apis.MetricRollup` agrega `InvocationLog` por minuto/hora/dia
    para evitar full table scan no dashboard.

    ## Health check

    `GET /healthz` retorna 200 quando:

    - DB respondendo (`SELECT 1` com timeout)
    - Migration count não-zero
    - Aplicações principais up

    Use em load balancer / Kubernetes liveness probe.

    ## Wrapper seguro

    `Blackboex.Telemetry.safe_execute/2` envolve `:telemetry.execute/2` em
    try/rescue. Erros de handler de telemetria nunca derrubam o caminho
    quente.
    """
  end

  defp auth_content do
    """
    # Autenticação & Multi-tenancy

    O Blackboex usa **invite-only registration**. Cadastro público não existe.

    ## Fluxo de login

    ```mermaid
    sequenceDiagram
      U as Usuário
      W as Web
      A as Accounts
      DB as DB
      U->>W: POST /users/log_in (email, password)
      W->>A: get_user_by_email_and_password
      A->>DB: SELECT user
      A-->>W: %User{}
      W->>A: generate_user_session_token
      W-->>U: 302 + cookie
    ```

    ## Scope

    `Blackboex.Accounts.Scope` agrega:

    - `user` — autenticado
    - `organization` — ativa (definida em `select_org`)
    - `live_action`/`current_path` — para LiveView contexts

    O on_mount hook `:fetch_current_scope` injeta o scope em todas as
    LiveViews. Plugs equivalentes existem para controllers.

    ## Multi-tenancy

    Toda query que filtra dados de usuário **deve** cruzar por
    `scope.organization.id`. Padrão recomendado:

    ```elixir
    def list_apis_for_project(project_id) when is_binary(project_id) do
      from(a in Api, where: a.project_id == ^project_id)
      |> Repo.all()
    end
    ```

    ...mas o `project_id` deve ter sido buscado já filtrado pela org. O
    `Blackboex.Policy` (LetMe) verifica isso explicitamente.

    ## Sessões

    `UserToken` separa tokens por contexto: `"session"`, `"reset_password"`,
    `"confirm"`, `"change_email"`. Cada um tem TTL próprio.

    ## Onboarding

    O wizard de primeiro uso (`OnboardingLive`) cria a primeira organização
    + projeto Exemplos automaticamente. Vê **Conceitos Fundamentais** para a
    estrutura.
    """
  end

  defp audit_content do
    """
    # Auditoria de Mudanças

    Mudanças relevantes do domínio passam por `ExAudit`, gerando um
    `AuditLog` para cada:

    - `insert/update/delete` em schemas auditados
    - Diff campo-a-campo
    - Carimbo do `Scope.user_id` que originou a operação

    ## Schemas auditados

    | Schema | Por que auditar |
    |--------|-----------------|
    | `Api` | Mudanças disparam recompilação |
    | `Flow` | Definição é executável |
    | `Page` | Conteúdo público para o time |
    | `Organization` | Multi-tenancy crítico |
    | `Membership` | Quem tem acesso a quê |
    | `ProjectEnvVar` | Pode conter secrets — diff de chave, valor mascarado |

    ## Como ler

    Aba **Audit Log** no admin (Backpex):

    - Filtra por org / actor / período
    - Mostra diff JSON
    - Imutável (sem `update`/`delete` na tabela `audit_logs`)

    ## Programaticamente

    ```elixir
    Blackboex.Audit.list_for_resource(api.id, limit: 50)
    ```

    ## Por que importa

    - **Compliance**: exigido para SOC2/ISO em muitos contextos
    - **Debug**: "quem mudou esse Flow ontem?"
    - **Segurança**: detecção de comportamento anômalo
    """
  end

  defp feature_flags_content do
    """
    # Feature Flags

    Usamos `FunWithFlags`. Flags são escopadas por:

    - **Boolean** global
    - **Per-actor** (organização ou usuário)
    - **Per-percentage** (rollout gradual)
    - **Per-group** (e.g., beta_orgs)

    ## API básica

    ```elixir
    if FunWithFlags.enabled?(:new_flow_editor, for: scope.organization) do
      # caminho novo
    else
      # caminho antigo
    end
    ```

    ## Wrapper

    `Blackboex.Features` centraliza chamadas — não use `FunWithFlags`
    diretamente fora de `lib/blackboex/features/`. Isso facilita:

    - Trocar o backend (Redis/DB) sem reescrever call sites
    - Logar auditoria de toggle
    - Stub em testes (`Mox`)

    ## Lifecycle de um flag

    ```mermaid
    stateDiagram-v2
      [*] --> created
      created --> rollout: 1% → 10% → 50%
      rollout --> default_on: 100%
      default_on --> removed: código limpa o gate
      removed --> [*]
    ```

    Quando atingir 100% e estabilizar, **abra um PR** removendo o gate. Não
    deixe flags zumbis no código.

    ## Observação

    Para mudanças visíveis ao usuário, sempre considere:

    - Tem rollback rápido?
    - Tem alerta se taxa de erro > X%?
    - Tem comunicação aos stakeholders?
    """
  end

  defp testing_content do
    """
    # Workflow de Testes

    Regra zero: **TDD obrigatório**. Escreva o teste, veja-o falhar, depois
    implemente. Sem exceções.

    ## Comandos

    | Comando | O que faz |
    |---------|-----------|
    | `make test` | Suite completa |
    | `make test.unit` | Apenas `@moduletag :unit` |
    | `make test.integration` | Apenas `@moduletag :integration` |
    | `make test.liveview` | Apenas `@moduletag :liveview` |
    | `make test.failed` | Re-roda os que falharam |
    | `make test.cover` | Cobertura |
    | `make lint` | format + credo + dialyzer |
    | `make precommit` | compile + format + test |

    ## Fixtures (obrigatórias)

    Todo schema inserido em teste **precisa** ter fixture. Inserção inline
    com `%Schema{} |> changeset |> Repo.insert` é proibida (exceto em testes
    do próprio changeset).

    ## Named setups

    Compor em vez de duplicar:

    ```elixir
    setup [:register_and_log_in_user, :create_org_and_api]
    ```

    Disponíveis: `:register_and_log_in_user`, `:create_user_and_org`,
    `:create_org`, `:create_api`, `:create_org_and_api`, `:create_project`,
    `:create_flow`, `:create_org_and_flow`, `:create_page`, `:create_page_tree`,
    `:create_playground`, `:stub_llm_client`.

    ## LiveView

    Use `assert_has(view, selector)` e `refute_has(view, selector)` em vez
    de `has_element?` cru.

    ## Mocks

    `Mox.verify_on_exit!` é automático em DataCase. Só `import Mox` se você
    usar `expect/3` ou `stub/3` direto.

    ## Zero warnings

    Nunca ignore `[D]` design warnings do Credo. Nunca dispense alertas
    Dialyzer sem investigar root cause.
    """
  end

  defp make_commands_content do
    """
    # Comandos Make & Operação

    O `Makefile` na raiz tem alvos para todos os fluxos comuns.

    ## Setup inicial

    ```bash
    make setup     # docker up + deps + DB criado/migrado
    make server    # localhost:4000
    make iex       # console interativo
    ```

    ## Banco de dados

    | Comando | Efeito |
    |---------|--------|
    | `make db.migrate` | Roda migrations pendentes |
    | `make db.rollback` | Volta uma migration |
    | `make db.reset` | drop + create + migrate + seed |
    | `make db.gen.migration NAME=x` | Gera arquivo vazio |

    ## Docker

    ```bash
    make docker.up      # postgres, etc.
    make docker.down    # para containers
    make docker.reset   # limpa volumes
    ```

    ## Testes seletivos

    ```bash
    make test.domain    # apenas apps/blackboex
    make test.web       # apenas apps/blackboex_web
    mix test path/to/test.exs:42   # uma linha específica
    ```

    ## Lint

    `make lint` roda em ordem: `mix format --check-formatted`, `mix credo
    --strict`, `mix dialyzer`. Falha em qualquer = falha total.

    ## Rotas

    `make routes` mostra a tabela de rotas Phoenix completa.

    ## Convenção

    Antes de fazer push: `make precommit`. Antes de abrir PR: `make lint`.
    Pipeline CI roda os mesmos alvos.
    """
  end

  defp roadmap_content do
    """
    # Roadmap & Próximos Passos

    Esta página é um marcador vivo. O conteúdo aqui muda conforme o produto
    evolui. Para histórico, veja `git log` ou os ADRs em `docs/architecture.md`.

    ## Em desenvolvimento

    - Geração assistida de Flows via NL → JSON
    - Catálogo público de templates compartilhados entre organizações
    - Métricas avançadas: latência por node, custo de LLM por API
    - Suporte a WebSockets em APIs geradas

    ## Próximos passos para você

    1. **Explore** todos os exemplos deste workspace
    2. **Crie** um novo projeto na sua organização
    3. **Duplique** um template (API ou Flow) e adapte
    4. **Configure** suas chaves de LLM em Project Env Vars
    5. **Convide** colaboradores via página de organização

    ## Onde encontrar mais

    - `docs/architecture.md` — diagrama de contextos, supervisão, invariantes
    - `docs/gotchas.md` — armadilhas conhecidas, lições aprendidas
    - `AGENTS.md` (root e por-diretório) — contexto para agentes de IA

    ## Contribuindo

    Para mudanças no produto base, abra issue/PR no repositório principal.
    Para feedback do produto, use o canal interno da sua organização.
    """
  end
end
