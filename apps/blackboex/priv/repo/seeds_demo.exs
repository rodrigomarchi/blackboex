# Demo seed: Pages + Playgrounds for rodtroll@gmail.com
#
# Usage:
#   mix run apps/blackboex/priv/repo/seeds_demo.exs
#
# Idempotent — deletes existing demo pages/playgrounds before re-creating.

alias Blackboex.{Accounts, Organizations, Projects, Pages, Playgrounds}

# ── Find user & org ───────────────────────────────────────────

user =
  Accounts.get_user_by_email("rodtroll@gmail.com") ||
    raise "User rodtroll@gmail.com not found — register first"

[org | _] = Organizations.list_user_organizations(user)
project = Projects.get_default_project(org.id) || raise "No default project for org #{org.id}"

IO.puts("Seeding demo data for #{user.email} / org=#{org.name} / project=#{project.name}")

# ── Helpers ───────────────────────────────────────────────────

create_page! = fn attrs ->
  base = %{
    organization_id: org.id,
    project_id: project.id,
    user_id: user.id,
    status: "published"
  }

  case Pages.create_page(Map.merge(base, attrs)) do
    {:ok, page} ->
      IO.puts("  ✓ Page: #{page.title}")
      page

    {:error, cs} ->
      raise "Failed to create page #{inspect(attrs[:title])}: #{inspect(cs.errors)}"
  end
end

create_playground! = fn attrs ->
  base = %{
    organization_id: org.id,
    project_id: project.id,
    user_id: user.id
  }

  case Playgrounds.create_playground(Map.merge(base, attrs)) do
    {:ok, pg} ->
      IO.puts("  ✓ Playground: #{pg.name}")
      pg

    {:error, cs} ->
      raise "Failed to create playground #{inspect(attrs[:name])}: #{inspect(cs.errors)}"
  end
end

# ── Clean previous demo data ─────────────────────────────────

IO.puts("\nCleaning previous demo pages & playgrounds...")

Pages.list_pages(project.id)
|> Enum.filter(&String.starts_with?(&1.title, "[Demo]"))
|> Enum.each(fn p -> Pages.delete_page(p) end)

Playgrounds.list_playgrounds(project.id)
|> Enum.filter(&String.starts_with?(&1.name, "[Demo]"))
|> Enum.each(fn p -> Playgrounds.delete_playground(p) end)

# ══════════════════════════════════════════════════════════════
#  PAGES — Tiptap / Markdown showcase
# ══════════════════════════════════════════════════════════════

IO.puts("\n── Creating Pages ──")

# ── Root: Guide index ─────────────────────────────────────────

guide = create_page!.(%{
  title: "[Demo] Guia de Formatação",
  position: 0,
  content: """
  # Guia de Formatação do Editor

  Bem-vindo ao guia completo de formatação. Use o menu lateral para navegar pelas seções.

  Cada página-filha demonstra um conjunto de recursos do editor:

  - **Texto & Tipografia** — negrito, itálico, sublinhado, riscado, código inline
  - **Headings & Blocos** — títulos, citações, divisores
  - **Listas** — bullet, numerada, tarefas
  - **Código** — blocos com syntax highlighting
  - **Tabelas** — formatação tabular
  - **Diagramas Mermaid** — flowcharts, sequência, etc.
  - **Conteúdo Avançado** — combinações e padrões reais

  > **Dica:** digite `/` em qualquer ponto do editor para abrir o menu de comandos rápidos.
  """
})

# ── Child 1: Texto & Tipografia ──────────────────────────────

create_page!.(%{
  title: "[Demo] Texto e Tipografia",
  parent_id: guide.id,
  position: 0,
  content: """
  # Texto e Tipografia

  ## Formatação Inline

  Aqui estão os estilos de texto disponíveis:

  - **Texto em negrito** para dar ênfase forte
  - *Texto em itálico* para ênfase suave
  - ~~Texto riscado~~ para indicar remoção
  - `código inline` para referências de código
  - Combinação: **_negrito e itálico_** juntos

  ## Parágrafos e Quebras

  Este é o primeiro parágrafo. O editor respeita quebras de parágrafo duplas para separar blocos de texto, exatamente como Markdown convencional.

  Este é o segundo parágrafo. Note o espaçamento automático entre eles.

  ## Citações (Blockquote)

  > "A simplicidade é a sofisticação suprema."
  > — Leonardo da Vinci

  > **Nota importante:** Citações podem conter formatação interna,
  > incluindo **negrito**, *itálico* e `código`.

  ---

  ## Links

  Visite a [documentação do Elixir](https://hexdocs.pm/elixir) para referência completa da linguagem.

  Links automáticos também funcionam: https://elixir-lang.org
  """
})

# ── Child 2: Headings & Estrutura ────────────────────────────

create_page!.(%{
  title: "[Demo] Headings e Estrutura",
  parent_id: guide.id,
  position: 1,
  content: """
  # Heading 1 — Título Principal

  Usado para o título da página ou seção principal.

  ## Heading 2 — Seção

  Divide o conteúdo em seções lógicas.

  ### Heading 3 — Subseção

  Nível mais granular suportado pelo editor.

  ---

  ## Divisores Horizontais

  Use divisores para separar seções visualmente. O divisor acima foi criado com `---` ou pelo comando `/divider`.

  ---

  ## Estrutura Hierárquica de Documento

  Um bom documento segue esta hierarquia:

  ### Introdução
  Contexto e objetivo do documento.

  ### Desenvolvimento
  Conteúdo principal, dividido em seções claras.

  ### Conclusão
  Resumo dos pontos e próximos passos.

  ---

  > **Dica:** Use o comando `/heading1`, `/heading2` ou `/heading3` para inserir headings rapidamente.
  """
})

# ── Child 3: Listas ──────────────────────────────────────────

create_page!.(%{
  title: "[Demo] Listas",
  parent_id: guide.id,
  position: 2,
  content: """
  # Listas

  ## Lista com Marcadores (Bullet)

  - Primeiro item
  - Segundo item
  - Terceiro item com mais detalhes que ocupa mais espaço na linha

  ## Lista Numerada

  1. Configurar o ambiente de desenvolvimento
  2. Instalar dependências com `mix deps.get`
  3. Criar o banco de dados com `mix ecto.create`
  4. Rodar as migrações com `mix ecto.migrate`
  5. Iniciar o servidor com `mix phx.server`

  ## Lista de Tarefas (Task List)

  - [x] Definir schema do banco de dados
  - [x] Implementar contexto de domínio
  - [x] Criar fixtures para testes
  - [ ] Escrever testes de integração
  - [ ] Implementar LiveView
  - [ ] Revisar segurança

  ## Listas Aninhadas

  - Backend
    - Elixir / Phoenix
    - PostgreSQL
    - Oban (jobs)
  - Frontend
    - LiveView
    - Tailwind CSS
    - Tiptap (editor)
  - Infraestrutura
    - Docker
    - CI/CD
  """
})

# ── Child 4: Blocos de Código ─────────────────────────────────

create_page!.(%{
  title: "[Demo] Blocos de Código",
  parent_id: guide.id,
  position: 3,
  content: """
  # Blocos de Código

  O editor suporta syntax highlighting para diversas linguagens.

  ## Elixir

  ```elixir
  defmodule MyApp.Accounts do
    @moduledoc "Context for user accounts."

    alias MyApp.Accounts.User
    alias MyApp.Repo

    @spec get_user(integer()) :: User.t() | nil
    def get_user(id), do: Repo.get(User, id)

    @spec list_users() :: [User.t()]
    def list_users do
      User
      |> order_by(:inserted_at)
      |> Repo.all()
    end
  end
  ```

  ## JavaScript

  ```javascript
  const fetchData = async (url) => {
    try {
      const response = await fetch(url);
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      return await response.json();
    } catch (error) {
      console.error("Fetch failed:", error.message);
      return null;
    }
  };
  ```

  ## SQL

  ```sql
  SELECT u.email, COUNT(a.id) AS api_count
  FROM users u
  LEFT JOIN apis a ON a.user_id = u.id
  WHERE u.confirmed_at IS NOT NULL
  GROUP BY u.email
  ORDER BY api_count DESC
  LIMIT 10;
  ```

  ## Bash

  ```bash
  #!/bin/bash
  set -euo pipefail

  echo "Setting up development environment..."
  mix deps.get
  mix ecto.setup
  mix phx.server
  ```

  ## JSON

  ```json
  {
    "name": "blackboex",
    "version": "1.0.0",
    "endpoints": [
      { "method": "GET", "path": "/api/v1/health" },
      { "method": "POST", "path": "/api/v1/invoke" }
    ]
  }
  ```

  ## Código Inline

  Use `Enum.map/2` para transformar listas e `Repo.get!/2` para buscar registros.
  """
})

# ── Child 5: Tabelas ─────────────────────────────────────────

create_page!.(%{
  title: "[Demo] Tabelas",
  parent_id: guide.id,
  position: 4,
  content: """
  # Tabelas

  ## Tabela Simples

  | Coluna A | Coluna B | Coluna C |
  |----------|----------|----------|
  | Valor 1  | Valor 2  | Valor 3  |
  | Valor 4  | Valor 5  | Valor 6  |

  ## Comparação de Tecnologias

  | Feature         | Phoenix LiveView | React + API | Next.js SSR |
  |-----------------|:----------------:|:-----------:|:-----------:|
  | Server-rendered | ✓                | ✗           | ✓           |
  | Real-time       | ✓ (WebSocket)    | Parcial     | ✗           |
  | SEO-friendly    | ✓                | ✗           | ✓           |
  | Bundle size     | ~0 KB            | ~150 KB     | ~80 KB      |
  | Complexidade    | Baixa            | Alta        | Média       |

  ## Atalhos de Teclado

  | Ação             | Mac              | Windows/Linux     |
  |------------------|------------------|-------------------|
  | Salvar           | `⌘ + S`         | `Ctrl + S`        |
  | Negrito          | `⌘ + B`         | `Ctrl + B`        |
  | Itálico          | `⌘ + I`         | `Ctrl + I`        |
  | Código inline    | `⌘ + E`         | `Ctrl + E`        |
  | Link             | `⌘ + K`         | `Ctrl + K`        |
  | Highlight        | `⌘ + Shift + H` | `Ctrl + Shift + H`|
  | Riscado          | `⌘ + Shift + S` | `Ctrl + Shift + S`|

  ## Status de Módulos

  | Módulo           | Status       | Cobertura | Notas                  |
  |------------------|-------------|-----------|------------------------|
  | Accounts         | Completo    | 94%       | Auth + multi-tenancy   |
  | Apis             | Completo    | 91%       | CRUD + deploy          |
  | Billing          | Em progresso| 78%       | Falta webhook retry    |
  | Conversations    | Completo    | 88%       | Event-sourced          |
  | CodeGen          | Completo    | 85%       | Sandbox isolado        |
  """
})

# ── Child 6: Diagramas Mermaid ────────────────────────────────

create_page!.(%{
  title: "[Demo] Diagramas Mermaid",
  parent_id: guide.id,
  position: 5,
  content: """
  # Diagramas Mermaid

  O editor renderiza diagramas Mermaid automaticamente.

  ## Flowchart — Fluxo de Request

  ```mermaid
  flowchart TD
      A[Request HTTP] --> B{Autenticado?}
      B -->|Sim| C[Rate Limiter]
      B -->|Não| D[401 Unauthorized]
      C --> E{Dentro do limite?}
      E -->|Sim| F[Processar Request]
      E -->|Não| G[429 Too Many Requests]
      F --> H[Retornar Response]
  ```

  ## Sequence Diagram — Execução de Código

  ```mermaid
  sequenceDiagram
      participant U as Usuário
      participant LV as LiveView
      participant E as Executor
      participant S as Sandbox

      U->>LV: Clica "Executar"
      LV->>E: execute_code(playground, code)
      E->>E: Validar AST
      E->>S: Task.async (5s timeout)
      S->>S: Capturar IO
      S-->>E: {:ok, output}
      E->>E: Salvar last_output
      E-->>LV: {:ok, playground}
      LV-->>U: Exibir resultado
  ```

  ## Entity Relationship — Modelo de Dados

  ```mermaid
  erDiagram
      USER ||--o{ ORGANIZATION : "pertence a"
      ORGANIZATION ||--o{ PROJECT : "contém"
      PROJECT ||--o{ API : "contém"
      PROJECT ||--o{ PAGE : "contém"
      PROJECT ||--o{ PLAYGROUND : "contém"
      PAGE ||--o{ PAGE : "parent/children"
      API ||--o{ API_KEY : "possui"
      API ||--o{ INVOCATION_LOG : "registra"
  ```

  ## State Diagram — Ciclo de Vida da API

  ```mermaid
  stateDiagram-v2
      [*] --> Draft
      Draft --> Published : deploy
      Published --> Draft : undeploy
      Published --> Published : update & redeploy
      Draft --> [*] : delete
  ```
  """
})

# ── Child 7: Conteúdo Avançado (combinações) ─────────────────

advanced = create_page!.(%{
  title: "[Demo] Conteúdo Avançado",
  parent_id: guide.id,
  position: 6,
  content: """
  # Conteúdo Avançado

  Esta página combina múltiplos elementos para demonstrar documentação realista.

  ## Arquitetura do Sistema

  ```mermaid
  flowchart LR
      subgraph Web
          LV[LiveView]
          API[REST API]
      end
      subgraph Domain
          CTX[Contexts]
          WK[Workers]
      end
      subgraph Data
          PG[(PostgreSQL)]
          RD[(Redis)]
      end

      LV --> CTX
      API --> CTX
      CTX --> PG
      CTX --> RD
      WK --> CTX
  ```

  ## Setup Rápido

  1. Clone o repositório
  2. Configure as variáveis de ambiente:

  ```bash
  cp .env.example .env
  # edite .env com suas credenciais
  ```

  3. Suba os serviços:

  ```elixir
  # No IEx, verifique a conexão:
  Blackboex.Repo.aggregate(Blackboex.Accounts.User, :count)
  ```

  ## Checklist de Deploy

  - [x] Testes passando (`mix test`)
  - [x] Linters limpos (`mix lint`)
  - [x] Migrations reversíveis
  - [ ] Performance review
  - [ ] Security audit

  > **Atenção:** Sempre rode `make precommit` antes de abrir um PR.

  ## Referência Rápida de Módulos

  | Contexto       | Facade                      | Principal função        |
  |----------------|----------------------------|-------------------------|
  | Accounts       | `Blackboex.Accounts`       | Autenticação e sessões  |
  | Organizations  | `Blackboex.Organizations`  | Multi-tenancy           |
  | Apis           | `Blackboex.Apis`           | CRUD de APIs            |
  | Billing        | `Blackboex.Billing`        | Stripe + usage tracking |
  | Conversations  | `Blackboex.Conversations`  | Chat event-sourced      |

  ---

  *Este conjunto de páginas demonstra todas as capacidades do editor Tiptap.*
  """
})

# ── Grandchild: sub-página de Avançado ────────────────────────

create_page!.(%{
  title: "[Demo] Padrões de Código Elixir",
  parent_id: advanced.id,
  position: 0,
  content: """
  # Padrões de Código Elixir

  Sub-página demonstrando hierarquia de 3 níveis.

  ## Pattern Matching

  ```elixir
  def handle_result({:ok, %{status: 200, body: body}}) do
    {:ok, Jason.decode!(body)}
  end

  def handle_result({:ok, %{status: status}}) when status >= 400 do
    {:error, :upstream_error}
  end

  def handle_result({:error, reason}) do
    {:error, reason}
  end
  ```

  ## Pipeline (Pipe Operator)

  ```elixir
  users
  |> Enum.filter(& &1.active?)
  |> Enum.sort_by(& &1.name)
  |> Enum.map(&format_user/1)
  |> Enum.join("\\n")
  ```

  ## With Statement

  ```elixir
  with {:ok, user} <- Accounts.get_user(id),
       {:ok, org} <- Organizations.get_organization(user, org_id),
       :ok <- Policy.authorize(:org_read, user, org) do
    {:ok, org}
  end
  ```
  """
})

# ══════════════════════════════════════════════════════════════
#  PLAYGROUNDS — Executable Elixir examples
# ══════════════════════════════════════════════════════════════

IO.puts("\n── Creating Playgrounds ──")

# ── 1: Enum basics ───────────────────────────────────────────

create_playground!.(%{
  name: "[Demo] Enum — Transformações Básicas",
  description: "Map, filter, reduce e outras operações fundamentais com Enum",
  code: """
  # Transformações com Enum
  lista = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

  dobrados = Enum.map(lista, fn x -> x * 2 end)
  IO.puts("Dobrados: \#{inspect(dobrados)}")

  pares = Enum.filter(lista, fn x -> rem(x, 2) == 0 end)
  IO.puts("Pares: \#{inspect(pares)}")

  soma = Enum.reduce(lista, 0, fn x, acc -> x + acc end)
  IO.puts("Soma: \#{soma}")

  {min, max} = Enum.min_max(lista)
  IO.puts("Min: \#{min}, Max: \#{max}")

  agrupados = Enum.group_by(lista, fn x ->
    if rem(x, 2) == 0, do: :par, else: :impar
  end)
  IO.puts("Agrupados: \#{inspect(agrupados)}")

  chunks = Enum.chunk_every(lista, 3)
  IO.puts("Chunks de 3: \#{inspect(chunks)}")
  """
})

# ── 2: String manipulation ───────────────────────────────────

create_playground!.(%{
  name: "[Demo] String — Manipulação de Texto",
  description: "Operações com strings, interpolação, split/join, regex",
  code: """
  # Manipulação de Strings
  nome = "Elixir Programming Language"

  IO.puts("Original: \#{nome}")
  IO.puts("Upcase: \#{String.upcase(nome)}")
  IO.puts("Downcase: \#{String.downcase(nome)}")
  IO.puts("Tamanho: \#{String.length(nome)}")
  IO.puts("Reverso: \#{String.reverse(nome)}")

  palavras = String.split(nome)
  IO.puts("Palavras: \#{inspect(palavras)}")
  IO.puts("Num palavras: \#{length(palavras)}")

  slug = nome
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  IO.puts("Slug: \#{slug}")

  # Regex
  email = "user@example.com"
  valid? = Regex.match?(~r/^[\\w.+-]+@[\\w.-]+\\.[a-z]{2,}$/i, email)
  IO.puts("Email '\#{email}' válido? \#{valid?}")

  # String padding
  IO.puts(String.pad_leading("42", 6, "0"))
  IO.puts(String.pad_trailing("hello", 10, "."))
  """
})

# ── 3: Map & Keyword ─────────────────────────────────────────

create_playground!.(%{
  name: "[Demo] Map e Keyword — Estruturas Chave-Valor",
  description: "Maps, keyword lists, acesso, atualização, merge e pattern matching",
  code: """
  # Maps
  user = %{name: "Alice", age: 30, role: :admin}
  IO.puts("User: \#{inspect(user)}")
  IO.puts("Nome: \#{user.name}")

  # Atualizar map
  updated = %{user | age: 31}
  IO.puts("Atualizado: \#{inspect(updated)}")

  # Map.merge
  extra = %{email: "alice@example.com", active: true}
  full = Map.merge(user, extra)
  IO.puts("Merged: \#{inspect(full)}")

  # Map.new a partir de lista
  from_list = Map.new([{:a, 1}, {:b, 2}, {:c, 3}])
  IO.puts("From list: \#{inspect(from_list)}")

  # Transformar valores
  prices = %{apple: 1.5, banana: 0.75, cherry: 3.0}
  discounted = Map.new(prices, fn {fruit, price} -> {fruit, price * 0.9} end)
  IO.puts("Com desconto: \#{inspect(discounted)}")

  # Keyword lists
  opts = [timeout: 5000, retries: 3, verbose: true]
  IO.puts("Timeout: \#{Keyword.get(opts, :timeout)}")
  IO.puts("Default: \#{Keyword.get(opts, :missing, "nenhum")}")

  # Pattern matching em maps
  %{name: nome, role: papel} = user
  IO.puts("Extraído — nome: \#{nome}, papel: \#{papel}")
  """
})

# ── 4: Pattern matching ──────────────────────────────────────

create_playground!.(%{
  name: "[Demo] Pattern Matching",
  description: "Desestruturação, case, cond, guards e pattern matching avançado",
  code: """
  # Pattern Matching em Elixir

  # Desestruturação de tuplas
  {:ok, valor} = {:ok, 42}
  IO.puts("Valor: \#{valor}")

  # Desestruturação de listas
  [primeiro | resto] = [1, 2, 3, 4, 5]
  IO.puts("Primeiro: \#{primeiro}")
  IO.puts("Resto: \#{inspect(resto)}")

  # Case com patterns
  resultado = case {:ok, %{status: 200, body: "hello"}} do
    {:ok, %{status: 200, body: body}} -> "Sucesso: \#{body}"
    {:ok, %{status: status}} -> "HTTP \#{status}"
    {:error, reason} -> "Erro: \#{reason}"
  end
  IO.puts(resultado)

  # Cond (equivalente a if/else if)
  temperatura = 28
  clima = cond do
    temperatura >= 35 -> "Muito quente"
    temperatura >= 25 -> "Agradável"
    temperatura >= 15 -> "Fresco"
    true -> "Frio"
  end
  IO.puts("Temperatura \#{temperatura}°C: \#{clima}")

  # Pin operator (^)
  esperado = "elixir"
  ^esperado = String.downcase("ELIXIR")
  IO.puts("Pin match OK: \#{esperado}")

  # Guards
  classify = fn
    x when is_integer(x) and x > 0 -> "positivo"
    x when is_integer(x) and x < 0 -> "negativo"
    0 -> "zero"
    x when is_binary(x) -> "string: \#{x}"
    _ -> "outro"
  end

  Enum.each([42, -7, 0, "hello", :atom], fn val ->
    IO.puts("\#{inspect(val)} => \#{classify.(val)}")
  end)
  """
})

# ── 5: Pipe operator & functional composition ────────────────

create_playground!.(%{
  name: "[Demo] Pipe Operator e Composição",
  description: "Encadeamento funcional com |>, transformação de dados em pipeline",
  code: """
  # Pipe Operator — transformação de dados em pipeline

  # Pipeline: processar lista de nomes
  nomes = ["  alice ", "BOB", " Charlie  ", "  diana "]

  processados = nomes
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.sort()
    |> Enum.map(&String.capitalize/1)

  IO.puts("Nomes: \#{inspect(processados)}")

  # Pipeline: estatísticas de texto
  texto = "O rato roeu a roupa do rei de Roma"

  palavras = texto |> String.downcase() |> String.split()
  IO.puts("Palavras: \#{length(palavras)}")

  frequencia = palavras
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_k, v} -> v end, :desc)

  IO.puts("Frequência:")
  Enum.each(frequencia, fn {palavra, count} ->
    barra = String.duplicate("█", count)
    IO.puts("  \#{String.pad_trailing(palavra, 8)} \#{barra} (\#{count})")
  end)

  # Pipeline: FizzBuzz
  IO.puts("\\nFizzBuzz (1-20):")
  1..20
  |> Enum.map(fn n ->
    cond do
      rem(n, 15) == 0 -> "FizzBuzz"
      rem(n, 3) == 0 -> "Fizz"
      rem(n, 5) == 0 -> "Buzz"
      true -> Integer.to_string(n)
    end
  end)
  |> Enum.join(", ")
  |> IO.puts()
  """
})

# ── 6: Date/Time ─────────────────────────────────────────────

create_playground!.(%{
  name: "[Demo] Date e Time",
  description: "Manipulação de datas, horas e cálculos temporais",
  code: """
  # Date e Time em Elixir

  hoje = Date.utc_today()
  IO.puts("Hoje: \#{hoje}")
  IO.puts("Ano: \#{hoje.year}, Mês: \#{hoje.month}, Dia: \#{hoje.day}")
  IO.puts("Dia da semana: \#{Date.day_of_week(hoje)}")

  # Aritmética de datas
  amanha = Date.add(hoje, 1)
  semana_que_vem = Date.add(hoje, 7)
  mes_passado = Date.add(hoje, -30)

  IO.puts("Amanhã: \#{amanha}")
  IO.puts("Semana que vem: \#{semana_que_vem}")
  IO.puts("30 dias atrás: \#{mes_passado}")

  # Diferença entre datas
  natal = Date.new!(hoje.year, 12, 25)
  diff = Date.diff(natal, hoje)
  IO.puts("Dias até o Natal: \#{diff}")

  # DateTime
  agora = DateTime.utc_now()
  IO.puts("\\nAgora (UTC): \#{agora}")

  # Range de datas
  inicio = Date.new!(hoje.year, hoje.month, 1)
  IO.puts("\\nPrimeiros 7 dias do mês:")
  Date.range(inicio, Date.add(inicio, 6))
  |> Enum.each(fn d ->
    dia_semana = case Date.day_of_week(d) do
      1 -> "Seg"
      2 -> "Ter"
      3 -> "Qua"
      4 -> "Qui"
      5 -> "Sex"
      6 -> "Sáb"
      7 -> "Dom"
    end
    IO.puts("  \#{d} (\#{dia_semana})")
  end)
  """
})

# ── 7: Recursion & algorithms ────────────────────────────────

create_playground!.(%{
  name: "[Demo] Recursão e Algoritmos",
  description: "Fibonacci, ordenação, busca — algoritmos clássicos em Elixir",
  code: """
  # Recursão e Algoritmos

  # Fibonacci com memoização via Map
  fib = fn fib_fn ->
    fn
      n, cache when n <= 1 ->
        {n, Map.put(cache, n, n)}
      n, cache ->
        case Map.get(cache, n) do
          nil ->
            {a, cache} = fib_fn.(fib_fn).(n - 1, cache)
            {b, cache} = fib_fn.(fib_fn).(n - 2, cache)
            result = a + b
            {result, Map.put(cache, n, result)}
          val ->
            {val, cache}
        end
    end
  end

  IO.puts("Fibonacci (0..15):")
  {_, cache} = Enum.reduce(0..15, {0, %{}}, fn n, {_, cache} ->
    {val, cache} = fib.(fib).(n, cache)
    IO.puts("  F(\#{n}) = \#{val}")
    {val, cache}
  end)

  # Quicksort
  quicksort = fn quicksort_fn ->
    fn
      [] -> []
      [pivot | rest] ->
        menores = Enum.filter(rest, &(&1 <= pivot))
        maiores = Enum.filter(rest, &(&1 > pivot))
        quicksort_fn.(quicksort_fn).(menores) ++ [pivot] ++ quicksort_fn.(quicksort_fn).(maiores)
    end
  end

  lista = [38, 27, 43, 3, 9, 82, 10]
  IO.puts("\\nQuicksort:")
  IO.puts("  Entrada: \#{inspect(lista)}")
  IO.puts("  Saída:   \#{inspect(quicksort.(quicksort).(lista))}")

  # Frequência de caracteres
  IO.puts("\\nFrequência de caracteres:")
  "abracadabra"
  |> String.graphemes()
  |> Enum.frequencies()
  |> Enum.sort_by(fn {_k, v} -> v end, :desc)
  |> Enum.each(fn {char, count} ->
    bar = String.duplicate("▓", count)
    IO.puts("  '\#{char}' \#{bar} \#{count}")
  end)
  """
})

# ── 8: JSON with Jason ───────────────────────────────────────

create_playground!.(%{
  name: "[Demo] Jason — JSON Encoding/Decoding",
  description: "Serialização e parsing JSON com Jason",
  code: """
  # JSON com Jason

  # Encode: Elixir -> JSON
  data = %{
    name: "Blackboex",
    version: "1.0.0",
    features: ["apis", "playground", "pages"],
    config: %{
      max_requests: 1000,
      timeout_ms: 5000,
      enabled: true
    }
  }

  json = Jason.encode!(data, pretty: true)
  IO.puts("Encoded JSON:")
  IO.puts(json)

  # Decode: JSON -> Elixir
  IO.puts("\\n---\\n")
  raw = ~s({"users":[{"name":"Alice","score":95},{"name":"Bob","score":87},{"name":"Carol","score":92}]})
  decoded = Jason.decode!(raw)
  IO.puts("Decoded: \#{inspect(decoded, pretty: true)}")

  # Processar dados JSON
  IO.puts("\\nRanking:")
  decoded["users"]
  |> Enum.sort_by(fn u -> u["score"] end, :desc)
  |> Enum.with_index(1)
  |> Enum.each(fn {u, pos} ->
    IO.puts("  \#{pos}. \#{u["name"]} — \#{u["score"]} pts")
  end)

  # Round-trip
  original = %{a: 1, b: [2, 3], c: %{nested: true}}
  roundtrip = original |> Jason.encode!() |> Jason.decode!(keys: :atoms)
  IO.puts("\\nRound-trip match: \#{original == roundtrip}")
  """
})

# ── 9: Comprehensions & Stream ────────────────────────────────

create_playground!.(%{
  name: "[Demo] Comprehensions e Stream",
  description: "For comprehensions, generators, filtros e lazy streams",
  code: """
  # Comprehensions

  # For básico com filtro
  pares_quadrados = for x <- 1..10, rem(x, 2) == 0, do: x * x
  IO.puts("Quadrados dos pares: \#{inspect(pares_quadrados)}")

  # Produto cartesiano
  combinacoes = for x <- [:a, :b, :c], y <- [1, 2], do: {x, y}
  IO.puts("Combinações: \#{inspect(combinacoes)}")

  # For com into (construir map)
  palavras = ["hello", "world", "elixir", "is", "great"]
  tamanhos = for w <- palavras, into: %{}, do: {w, String.length(w)}
  IO.puts("Tamanhos: \#{inspect(tamanhos)}")

  # Tabuleiro de xadrez
  IO.puts("\\nPosições do xadrez (primeiras 16):")
  posicoes = for col <- ?a..?h, row <- 1..8, do: "\#{<<col>>}\#{row}"
  posicoes |> Enum.take(16) |> Enum.chunk_every(8) |> Enum.each(&IO.puts(inspect(&1)))

  # Stream (lazy)
  IO.puts("\\nStream: primeiros 10 múltiplos de 7:")
  Stream.iterate(7, &(&1 + 7))
  |> Stream.take(10)
  |> Enum.to_list()
  |> IO.inspect()

  IO.puts("\\nStream: Fibonacci lazy (primeiros 12):")
  Stream.unfold({0, 1}, fn {a, b} -> {a, {b, a + b}} end)
  |> Stream.take(12)
  |> Enum.to_list()
  |> IO.inspect()

  # Stream.zip
  nomes = ["Alice", "Bob", "Carol"]
  scores = [95, 87, 92]
  ranking = Enum.zip(nomes, scores)
  IO.puts("\\nZip: \#{inspect(ranking)}")
  """
})

# ── 10: MapSet & tuple operations ─────────────────────────────

create_playground!.(%{
  name: "[Demo] MapSet e Tuplas",
  description: "Conjuntos, operações de conjuntos, tuplas e desestruturação",
  code: """
  # MapSet — Conjuntos

  frutas_a = MapSet.new(["maçã", "banana", "laranja", "uva"])
  frutas_b = MapSet.new(["banana", "kiwi", "uva", "manga"])

  IO.puts("Conjunto A: \#{inspect(MapSet.to_list(frutas_a))}")
  IO.puts("Conjunto B: \#{inspect(MapSet.to_list(frutas_b))}")

  uniao = MapSet.union(frutas_a, frutas_b)
  IO.puts("\\nUnião: \#{inspect(MapSet.to_list(uniao))}")

  inter = MapSet.intersection(frutas_a, frutas_b)
  IO.puts("Interseção: \#{inspect(MapSet.to_list(inter))}")

  diff = MapSet.difference(frutas_a, frutas_b)
  IO.puts("Diferença (A - B): \#{inspect(MapSet.to_list(diff))}")

  IO.puts("\\nBanana em A? \#{MapSet.member?(frutas_a, "banana")}")
  IO.puts("Kiwi em A? \#{MapSet.member?(frutas_a, "kiwi")}")
  IO.puts("Tamanho da união: \#{MapSet.size(uniao)}")

  # Tuplas
  IO.puts("\\n--- Tuplas ---")
  ponto = {10, 20, 30}
  IO.puts("Ponto: \#{inspect(ponto)}")
  IO.puts("Elem 0: \#{elem(ponto, 0)}")
  IO.puts("Elem 2: \#{elem(ponto, 2)}")
  IO.puts("Tamanho: \#{tuple_size(ponto)}")

  atualizado = put_elem(ponto, 1, 99)
  IO.puts("Atualizado: \#{inspect(atualizado)}")

  # Tuple como retorno de função
  resultados = [
    {:ok, "sucesso"},
    {:error, "não encontrado"},
    {:ok, "outro sucesso"},
    {:error, "timeout"}
  ]

  {oks, erros} = Enum.split_with(resultados, fn {status, _} -> status == :ok end)
  IO.puts("\\nOKs: \#{length(oks)}, Erros: \#{length(erros)}")
  """
})

# ── 11: Anonymous functions & closures ────────────────────────

create_playground!.(%{
  name: "[Demo] Funções Anônimas e Closures",
  description: "Lambdas, capture operator, closures e higher-order functions",
  code: """
  # Funções Anônimas e Closures

  # Sintaxe completa
  somar = fn a, b -> a + b end
  IO.puts("3 + 4 = \#{somar.(3, 4)}")

  # Capture syntax (&)
  dobrar = &(&1 * 2)
  IO.puts("Dobro de 21 = \#{dobrar.(21)}")

  # Multi-clause anonymous function
  saudacao = fn
    "pt" -> "Olá!"
    "en" -> "Hello!"
    "es" -> "¡Hola!"
    lang -> "[\#{lang}] ???"
  end

  Enum.each(["pt", "en", "es", "jp"], fn lang ->
    IO.puts("  \#{lang}: \#{saudacao.(lang)}")
  end)

  # Closure — captura variáveis do escopo externo
  multiplicador = fn fator ->
    fn x -> x * fator end
  end

  triplo = multiplicador.(3)
  IO.puts("\\nTriplo de 7: \#{triplo.(7)}")
  IO.puts("Triplo de 15: \#{triplo.(15)}")

  # Higher-order: aplicar lista de funções
  transformacoes = [
    &String.upcase/1,
    &String.reverse/1,
    fn s -> String.slice(s, 0, 5) end
  ]

  palavra = "elixir"
  IO.puts("\\nTransformações de '\#{palavra}':")
  Enum.each(transformacoes, fn f ->
    IO.puts("  -> \#{f.(palavra)}")
  end)

  # Compose manual
  compose = fn f, g -> fn x -> f.(g.(x)) end end
  shout_reverse = compose.(&String.upcase/1, &String.reverse/1)
  IO.puts("\\nCompose(upcase, reverse)('hello'): \#{shout_reverse.("hello")}")
  """
})

# ── 12: Bitwise & Integer ────────────────────────────────────

create_playground!.(%{
  name: "[Demo] Integer e Bitwise",
  description: "Operações numéricas, conversão de bases, bitwise e math",
  code: """
  # Integer e operações numéricas
  import Bitwise

  IO.puts("=== Bases numéricas ===")
  IO.puts("Decimal 255:   \#{255}")
  IO.puts("Binário:       \#{Integer.to_string(255, 2)}")
  IO.puts("Octal:         \#{Integer.to_string(255, 8)}")
  IO.puts("Hexadecimal:   \#{Integer.to_string(255, 16)}")

  IO.puts("\\n=== Parse ===")
  {val, ""} = Integer.parse("42")
  IO.puts("Parse '42': \#{val}")
  {val, ""} = Integer.parse("FF", 16)
  IO.puts("Parse 'FF' base 16: \#{val}")

  IO.puts("\\n=== Bitwise ===")
  a = 0b1010
  b = 0b1100
  IO.puts("a = \#{Integer.to_string(a, 2)} (\#{a})")
  IO.puts("b = \#{Integer.to_string(b, 2)} (\#{b})")
  IO.puts("a AND b = \#{Integer.to_string(a &&& b, 2)} (\#{a &&& b})")
  IO.puts("a OR  b = \#{Integer.to_string(a ||| b, 2)} (\#{a ||| b})")
  IO.puts("a XOR b = \#{Integer.to_string(a ^^^ b, 2)} (\#{a ^^^ b})")
  IO.puts("NOT a   = \#{~~~a}")
  IO.puts("a << 2  = \#{a <<< 2}")
  IO.puts("a >> 1  = \#{a >>> 1}")

  IO.puts("\\n=== Float ===")
  IO.puts("Pi aprox: \#{Float.round(3.14159265, 4)}")
  IO.puts("Ceil 4.2: \#{Float.ceil(4.2)}")
  IO.puts("Floor 4.8: \#{Float.floor(4.8)}")

  IO.puts("\\n=== Dígitos ===")
  Integer.digits(12345)
  |> IO.inspect(label: "Dígitos de 12345")

  Integer.undigits([1, 2, 3, 4, 5])
  |> IO.inspect(label: "Reconstruído")
  """
})

IO.puts("\n✅ Demo seed complete!")
IO.puts("   Pages: #{length(Pages.list_pages(project.id))} total")
IO.puts("   Playgrounds: #{length(Playgrounds.list_playgrounds(project.id))} total")
