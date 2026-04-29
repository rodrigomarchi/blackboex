# Demo seed: Pages + Playgrounds for rodtroll@gmail.com
#
# Usage:
#   mix run apps/blackboex/priv/repo/seeds_demo.exs
#
# Idempotent — deletes existing demo pages/playgrounds before re-creating.

alias Blackboex.{Accounts, Organizations, Projects, Pages, Playgrounds, Flows}

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
  # ╔══════════════════════════════════════════════════════╗
  # ║  Enum — Transformações Básicas                      ║
  # ║  Aprenda a transformar, filtrar e agregar listas     ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Em Elixir, o módulo Enum é o mais usado para trabalhar com
  # coleções (listas, ranges, maps). Ele oferece funções como
  # map, filter, reduce — similares ao JavaScript ou Python.

  # Criamos uma lista com números de 1 a 10.
  # Listas em Elixir usam colchetes [], como em Python/JS.
  lista = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10]

  # Enum.map/2 aplica uma função a cada elemento e retorna uma nova lista.
  # "fn x -> x * 2 end" é uma função anônima (como arrow function em JS).
  # O resultado é uma NOVA lista — Elixir nunca modifica dados existentes (imutabilidade).
  dobrados = Enum.map(lista, fn x -> x * 2 end)

  # IO.puts/1 imprime texto no console (como print/console.log).
  # inspect() converte qualquer valor Elixir para uma string legível.
  # \#{} dentro de strings é interpolação (como template literals `${}` em JS).
  IO.puts("Dobrados: \#{inspect(dobrados)}")

  # Enum.filter/2 retorna apenas os elementos que satisfazem a condição.
  # rem(x, 2) calcula o resto da divisão (módulo) — se for 0, o número é par.
  pares = Enum.filter(lista, fn x -> rem(x, 2) == 0 end)
  IO.puts("Pares: \#{inspect(pares)}")

  # Enum.reduce/3 percorre a lista acumulando um resultado.
  # "acc" é o acumulador (começa em 0). A cada passo, soma x ao acc.
  # É como um for-loop que vai juntando valores (fold em outras linguagens).
  soma = Enum.reduce(lista, 0, fn x, acc -> x + acc end)
  IO.puts("Soma: \#{soma}")

  # Enum.min_max/1 retorna uma tupla {menor, maior}.
  # Tuplas usam chaves {} e são coleções de tamanho fixo.
  # O "=" em Elixir não é atribuição: é pattern matching (desestruturação).
  {min, max} = Enum.min_max(lista)
  IO.puts("Min: \#{min}, Max: \#{max}")

  # Enum.group_by/2 agrupa elementos por uma chave que você define.
  # :par e :impar são átomos (atoms) — constantes nomeadas, como symbols em Ruby.
  agrupados = Enum.group_by(lista, fn x ->
    if rem(x, 2) == 0, do: :par, else: :impar
  end)
  IO.puts("Agrupados: \#{inspect(agrupados)}")

  # Enum.chunk_every/2 divide a lista em sublistas de tamanho N.
  chunks = Enum.chunk_every(lista, 3)
  IO.puts("Chunks de 3: \#{inspect(chunks)}")
  """
})

# ── 2: String manipulation ───────────────────────────────────

create_playground!.(%{
  name: "[Demo] String — Manipulação de Texto",
  description: "Operações com strings, interpolação, split/join, regex",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  String — Manipulação de Texto                      ║
  # ║  Aprenda a transformar, buscar e formatar strings    ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Strings em Elixir são binários UTF-8 (entre aspas duplas "").
  # O módulo String oferece funções para manipulação de texto.

  # Criamos uma string simples com aspas duplas.
  nome = "Elixir Programming Language"

  # String.upcase/1, downcase/1, length/1, reverse/1 — funções básicas.
  # O /1 indica que a função recebe 1 argumento (aridade).
  IO.puts("Original: \#{nome}")
  IO.puts("Upcase: \#{String.upcase(nome)}")
  IO.puts("Downcase: \#{String.downcase(nome)}")
  IO.puts("Tamanho: \#{String.length(nome)}")
  IO.puts("Reverso: \#{String.reverse(nome)}")

  # String.split/1 quebra a string por espaços (como split() em JS/Python).
  palavras = String.split(nome)
  IO.puts("Palavras: \#{inspect(palavras)}")
  IO.puts("Num palavras: \#{length(palavras)}")

  # |> é o pipe operator — passa o resultado da esquerda como 1º argumento
  # da função à direita. É como encadear métodos, mas funcional.
  # Leia de cima para baixo: pega nome → minúscula → troca caracteres → limpa.
  slug = nome
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "-")
    |> String.trim("-")
  IO.puts("Slug: \#{slug}")

  # ~r/.../ é um sigil de regex (expressão regular).
  # Sigils são atalhos do Elixir — ~r cria um Regex, similar a /.../ em JS.
  # Nomes de variáveis podem terminar com ? — é convenção para booleanos.
  email = "user@example.com"
  valid? = Regex.match?(~r/^[\\w.+-]+@[\\w.-]+\\.[a-z]{2,}$/i, email)
  IO.puts("Email '\#{email}' válido? \#{valid?}")

  # String.pad_leading/3 e pad_trailing/3 — preenchem a string até um tamanho.
  # Útil para formatar tabelas e alinhar texto no console.
  IO.puts(String.pad_leading("42", 6, "0"))
  IO.puts(String.pad_trailing("hello", 10, "."))
  """
})

# ── 3: Map & Keyword ─────────────────────────────────────────

create_playground!.(%{
  name: "[Demo] Map e Keyword — Estruturas Chave-Valor",
  description: "Maps, keyword lists, acesso, atualização, merge e pattern matching",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Map e Keyword — Estruturas Chave-Valor             ║
  # ║  Aprenda a criar, acessar e transformar maps         ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Maps são como objetos em JS ou dicts em Python: pares chave-valor.
  # Em Elixir, maps usam %{} e são a estrutura mais comum para dados.

  # %{chave: valor} cria um map com chaves atom.
  # Atoms (:admin, :name, etc.) são constantes nomeadas — como symbols em Ruby.
  user = %{name: "Alice", age: 30, role: :admin}

  # IO.inspect/1 é como IO.puts mas imprime qualquer tipo Elixir diretamente.
  IO.puts("User: \#{inspect(user)}")

  # Acesso por ponto (user.name) só funciona com chaves atom.
  IO.puts("Nome: \#{user.name}")

  # %{map | chave: novo_valor} atualiza um map existente (sintaxe de update).
  # Isso cria um NOVO map — o original não muda (imutabilidade).
  updated = %{user | age: 31}
  IO.puts("Atualizado: \#{inspect(updated)}")

  # Map.merge/2 combina dois maps. Chaves do segundo sobrescrevem o primeiro.
  extra = %{email: "alice@example.com", active: true}
  full = Map.merge(user, extra)
  IO.puts("Merged: \#{inspect(full)}")

  # Map.new/1 cria um map a partir de uma lista de tuplas {chave, valor}.
  # Tuplas {} são coleções de tamanho fixo, usadas como "structs leves".
  from_list = Map.new([{:a, 1}, {:b, 2}, {:c, 3}])
  IO.puts("From list: \#{inspect(from_list)}")

  # Map.new/2 com função — transforma cada par {k, v} ao criar o map.
  # fn {fruit, price} -> ... end desestrutura a tupla diretamente nos argumentos.
  prices = %{apple: 1.5, banana: 0.75, cherry: 3.0}
  discounted = Map.new(prices, fn {fruit, price} -> {fruit, price * 0.9} end)
  IO.puts("Com desconto: \#{inspect(discounted)}")

  # Keyword lists são listas de tuplas {atom, valor} — usadas para opções.
  # Parecem maps, mas permitem chaves duplicadas e preservam ordem.
  opts = [timeout: 5000, retries: 3, verbose: true]
  IO.puts("Timeout: \#{Keyword.get(opts, :timeout)}")
  IO.puts("Default: \#{Keyword.get(opts, :missing, "nenhum")}")

  # Pattern matching em maps — extrair valores diretamente com "=".
  # O "=" em Elixir é match (comparação + extração), não atribuição.
  %{name: nome, role: papel} = user
  IO.puts("Extraído — nome: \#{nome}, papel: \#{papel}")
  """
})

# ── 4: Pattern matching ──────────────────────────────────────

create_playground!.(%{
  name: "[Demo] Pattern Matching",
  description: "Desestruturação, case, cond, guards e pattern matching avançado",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Pattern Matching                                    ║
  # ║  O superpoder do Elixir: desestruturar e comparar    ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Em Elixir, o operador "=" NÃO é atribuição — é pattern matching.
  # Ele tenta "encaixar" o lado esquerdo no lado direito, extraindo valores.
  # É como destructuring em JS, mas muito mais poderoso.

  # {:ok, valor} é uma tupla. O "=" extrai 42 para a variável "valor".
  # Se o lado direito fosse {:error, _}, daria erro (não encaixa em {:ok, _}).
  {:ok, valor} = {:ok, 42}
  IO.puts("Valor: \#{valor}")

  # [primeiro | resto] separa a "cabeça" (1º elemento) do "resto" da lista.
  # O operador | (cons) é fundamental em Elixir para trabalhar com listas.
  [primeiro | resto] = [1, 2, 3, 4, 5]
  IO.puts("Primeiro: \#{primeiro}")
  IO.puts("Resto: \#{inspect(resto)}")

  # "case" testa o valor contra vários padrões (patterns), de cima para baixo.
  # Cada "padrão ->" define o que fazer se o valor encaixar.
  # Aqui combinamos tuplas e maps no mesmo pattern matching.
  resultado = case {:ok, %{status: 200, body: "hello"}} do
    {:ok, %{status: 200, body: body}} -> "Sucesso: \#{body}"
    {:ok, %{status: status}} -> "HTTP \#{status}"
    {:error, reason} -> "Erro: \#{reason}"
  end
  IO.puts(resultado)

  # "cond" é como if/else if — avalia condições booleanas em sequência.
  # O primeiro "true" vence. O "true ->" final é o else (sempre verdadeiro).
  temperatura = 28
  clima = cond do
    temperatura >= 35 -> "Muito quente"
    temperatura >= 25 -> "Agradável"
    temperatura >= 15 -> "Fresco"
    true -> "Frio"
  end
  IO.puts("Temperatura \#{temperatura}°C: \#{clima}")

  # O pin operator (^) força comparação em vez de reatribuição.
  # ^esperado diz: "o valor DEVE ser igual a esperado, não crie nova variável".
  esperado = "elixir"
  ^esperado = String.downcase("ELIXIR")
  IO.puts("Pin match OK: \#{esperado}")

  # Guards são condições extras no pattern matching com "when".
  # is_integer/1, is_binary/1 etc. são funções de tipo (type checks).
  # _ (underscore) captura qualquer valor (como default/wildcard).
  classify = fn
    x when is_integer(x) and x > 0 -> "positivo"
    x when is_integer(x) and x < 0 -> "negativo"
    0 -> "zero"
    x when is_binary(x) -> "string: \#{x}"
    _ -> "outro"
  end

  # classify.(val) chama a função anônima — note o ponto antes dos parênteses.
  # Isso diferencia chamadas de funções anônimas de funções nomeadas.
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
  # ╔══════════════════════════════════════════════════════╗
  # ║  Pipe Operator e Composição Funcional               ║
  # ║  Encadear transformações de dados de forma legível   ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # O pipe operator |> é o recurso mais icônico do Elixir.
  # Ele pega o resultado da expressão à esquerda e passa como
  # PRIMEIRO argumento da função à direita.
  # Ex: "abc" |> String.upcase() equivale a String.upcase("abc")

  # &String.trim/1 é o "capture operator" — referencia uma função existente.
  # O & captura a função, /1 indica que ela recebe 1 argumento (aridade).
  # É como passar uma referência de método em JS: arr.map(String.trim)
  nomes = ["  alice ", "BOB", " Charlie  ", "  diana "]

  # Leia o pipeline de cima para baixo, como uma receita:
  # 1. Pega nomes → 2. Remove espaços → 3. Minúscula → 4. Ordena → 5. Capitaliza
  processados = nomes
    |> Enum.map(&String.trim/1)
    |> Enum.map(&String.downcase/1)
    |> Enum.sort()
    |> Enum.map(&String.capitalize/1)

  IO.puts("Nomes: \#{inspect(processados)}")

  # Outro pipeline: análise de frequência de palavras num texto.
  texto = "O rato roeu a roupa do rei de Roma"

  # Podemos encadear pipes na mesma linha para operações curtas.
  palavras = texto |> String.downcase() |> String.split()
  IO.puts("Palavras: \#{length(palavras)}")

  # Enum.frequencies/1 conta quantas vezes cada elemento aparece.
  # Enum.sort_by/3 ordena por um critério — aqui, pelo count decrescente.
  # {_k, v} — o underscore _ indica que não usamos essa variável (convenção).
  frequencia = palavras
    |> Enum.frequencies()
    |> Enum.sort_by(fn {_k, v} -> v end, :desc)

  IO.puts("Frequência:")
  Enum.each(frequencia, fn {palavra, count} ->
    barra = String.duplicate("█", count)
    IO.puts("  \#{String.pad_trailing(palavra, 8)} \#{barra} (\#{count})")
  end)

  # FizzBuzz clássico usando pipeline.
  # 1..20 é um Range (sequência de números), como range() em Python.
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
  # ╔══════════════════════════════════════════════════════╗
  # ║  Date e Time                                         ║
  # ║  Trabalhar com datas, horas e cálculos temporais     ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Elixir tem tipos nativos para Date, Time, DateTime e NaiveDateTime.
  # Não precisa de bibliotecas externas para operações básicas.

  # Date.utc_today/0 retorna a data atual em UTC.
  # Structs como Date têm campos acessíveis por ponto (.year, .month, .day).
  hoje = Date.utc_today()
  IO.puts("Hoje: \#{hoje}")
  IO.puts("Ano: \#{hoje.year}, Mês: \#{hoje.month}, Dia: \#{hoje.day}")
  IO.puts("Dia da semana: \#{Date.day_of_week(hoje)}")

  # Date.add/2 soma ou subtrai dias — retorna uma nova data (imutabilidade).
  amanha = Date.add(hoje, 1)
  semana_que_vem = Date.add(hoje, 7)
  mes_passado = Date.add(hoje, -30)

  IO.puts("Amanhã: \#{amanha}")
  IO.puts("Semana que vem: \#{semana_que_vem}")
  IO.puts("30 dias atrás: \#{mes_passado}")

  # Date.new!/3 cria uma data — o "!" indica que lança exceção se inválida.
  # Funções com "!" são a versão "bang" — falham alto em vez de retornar {:error, _}.
  # Date.diff/2 calcula a diferença em dias entre duas datas.
  natal = Date.new!(hoje.year, 12, 25)
  diff = Date.diff(natal, hoje)
  IO.puts("Dias até o Natal: \#{diff}")

  # DateTime inclui data + hora + timezone. utc_now/0 retorna o momento atual.
  agora = DateTime.utc_now()
  IO.puts("\\nAgora (UTC): \#{agora}")

  # Date.range/2 cria um intervalo de datas (como range de números).
  # Podemos iterar sobre ele com Enum.each, Enum.map, etc.
  inicio = Date.new!(hoje.year, hoje.month, 1)
  IO.puts("\\nPrimeiros 7 dias do mês:")

  # "case" com pattern matching em inteiros — cada número mapeia para um dia.
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
  # ╔══════════════════════════════════════════════════════╗
  # ║  Recursão e Algoritmos                               ║
  # ║  Fibonacci, Quicksort e contagem de frequências      ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Elixir não tem loops (for/while). Toda repetição usa recursão
  # ou funções do Enum/Stream. Aqui vemos recursão explícita.

  # Fibonacci com memoização (cache) via Map.
  # Como Elixir não tem "def" dentro de scripts, usamos funções anônimas.
  # O truque fib.(fib) passa a função para si mesma (simula recursão).
  # "when n <= 1" é um guard — condição extra no pattern matching.
  fib = fn fib_fn ->
    fn
      n, cache when n <= 1 ->
        {n, Map.put(cache, n, n)}
      n, cache ->
        # Map.get/2 busca no cache. Se nil, calcula recursivamente.
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
  # Enum.reduce percorre 0..15, acumulando o cache entre as chamadas.
  # %{} é um map vazio — nosso cache começa sem nenhum valor.
  {_, cache} = Enum.reduce(0..15, {0, %{}}, fn n, {_, cache} ->
    {val, cache} = fib.(fib).(n, cache)
    IO.puts("  F(\#{n}) = \#{val}")
    {val, cache}
  end)

  # Quicksort — algoritmo clássico de ordenação.
  # [pivot | rest] separa o primeiro elemento (pivô) do restante.
  # ++ concatena listas (como concat em JS).
  # &(&1 <= pivot) é syntax sugar: fn x -> x <= pivot end.
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

  # String.graphemes/1 divide uma string em seus caracteres visuais (grafemas).
  # Enum.frequencies/1 conta quantas vezes cada elemento aparece.
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
  # ╔══════════════════════════════════════════════════════╗
  # ║  Jason — JSON Encoding/Decoding                      ║
  # ║  Converter entre Elixir e JSON (o formato da web)    ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Jason é a biblioteca padrão do Elixir para trabalhar com JSON.
  # JSON é o formato mais usado para trocar dados entre sistemas na web.
  # Jason converte maps/listas Elixir ↔ strings JSON.

  # Encode: Elixir → JSON (transformar dados Elixir em texto JSON).
  # Jason.encode!/2 com "pretty: true" formata com indentação.
  # O "!" indica que lança exceção se falhar (versão sem ! retorna {:ok, _}).
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

  # Decode: JSON → Elixir (transformar texto JSON em dados Elixir).
  # ~s() é um sigil que cria uma string (útil quando tem aspas dentro).
  IO.puts("\\n---\\n")
  raw = ~s({"users":[{"name":"Alice","score":95},{"name":"Bob","score":87},{"name":"Carol","score":92}]})
  decoded = Jason.decode!(raw)
  IO.puts("Decoded: \#{inspect(decoded, pretty: true)}")

  # Após decodificar, as chaves são strings (não atoms).
  # Acessamos com ["chave"] em vez de .chave.
  IO.puts("\\nRanking:")
  decoded["users"]
  |> Enum.sort_by(fn u -> u["score"] end, :desc)
  |> Enum.with_index(1)
  |> Enum.each(fn {u, pos} ->
    IO.puts("  \#{pos}. \#{u["name"]} — \#{u["score"]} pts")
  end)

  # Round-trip: Elixir → JSON → Elixir.
  # "keys: :atoms" faz o decode converter chaves string para atoms.
  # Verificamos que o resultado é igual ao original.
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
  # ╔══════════════════════════════════════════════════════╗
  # ║  Comprehensions e Stream                             ║
  # ║  For avançado + processamento lazy (preguiçoso)      ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # "for" em Elixir NÃO é um loop — é uma comprehension (como list
  # comprehension em Python). Gera uma nova lista a partir de geradores.

  # "for x <- 1..10" itera sobre o range. A parte após a vírgula é um filtro.
  # "do:" no final define o valor gerado para cada elemento.
  pares_quadrados = for x <- 1..10, rem(x, 2) == 0, do: x * x
  IO.puts("Quadrados dos pares: \#{inspect(pares_quadrados)}")

  # Múltiplos geradores (<-) criam produto cartesiano (todas as combinações).
  # :a, :b, :c são atoms — constantes nomeadas, como enums em outras linguagens.
  combinacoes = for x <- [:a, :b, :c], y <- [1, 2], do: {x, y}
  IO.puts("Combinações: \#{inspect(combinacoes)}")

  # "into: %{}" faz o for construir um map em vez de lista.
  # Cada iteração retorna {chave, valor} que vai para o map.
  palavras = ["hello", "world", "elixir", "is", "great"]
  tamanhos = for w <- palavras, into: %{}, do: {w, String.length(w)}
  IO.puts("Tamanhos: \#{inspect(tamanhos)}")

  # ?a é o codepoint (número) do caractere 'a'. ?a..?h gera 97..104.
  # <<col>> converte o codepoint de volta para string (um caractere).
  IO.puts("\\nPosições do xadrez (primeiras 16):")
  posicoes = for col <- ?a..?h, row <- 1..8, do: "\#{<<col>>}\#{row}"
  posicoes |> Enum.take(16) |> Enum.chunk_every(8) |> Enum.each(&IO.puts(inspect(&1)))

  # Stream é como Enum, mas LAZY — não processa até ser necessário.
  # Isso é eficiente para sequências grandes ou infinitas.
  # Stream.iterate/2 cria uma sequência infinita aplicando uma função repetidamente.
  # &(&1 + 7) é syntax sugar para fn x -> x + 7 end. &1 é o 1º argumento.
  IO.puts("\\nStream: primeiros 10 múltiplos de 7:")
  Stream.iterate(7, &(&1 + 7))
  |> Stream.take(10)
  |> Enum.to_list()
  |> IO.inspect()

  # Stream.unfold/2 gera valores a partir de um estado que se transforma.
  # A cada passo retorna {valor_emitido, próximo_estado}.
  # Aqui geramos Fibonacci: estado {a, b} → emite a, próximo estado {b, a+b}.
  IO.puts("\\nStream: Fibonacci lazy (primeiros 12):")
  Stream.unfold({0, 1}, fn {a, b} -> {a, {b, a + b}} end)
  |> Stream.take(12)
  |> Enum.to_list()
  |> IO.inspect()

  # Enum.zip/2 combina duas listas em pares (tuplas), como zip() em Python.
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
  # ╔══════════════════════════════════════════════════════╗
  # ║  MapSet e Tuplas                                     ║
  # ║  Conjuntos matemáticos e coleções de tamanho fixo    ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # MapSet é a implementação de conjuntos (sets) em Elixir.
  # Conjuntos não permitem duplicatas e suportam operações matemáticas.
  # Como Set em JS/Python ou HashSet em Java.

  # MapSet.new/1 cria um conjunto a partir de uma lista.
  frutas_a = MapSet.new(["maçã", "banana", "laranja", "uva"])
  frutas_b = MapSet.new(["banana", "kiwi", "uva", "manga"])

  IO.puts("Conjunto A: \#{inspect(MapSet.to_list(frutas_a))}")
  IO.puts("Conjunto B: \#{inspect(MapSet.to_list(frutas_b))}")

  # Operações clássicas de conjuntos (teoria dos conjuntos da matemática).
  uniao = MapSet.union(frutas_a, frutas_b)
  IO.puts("\\nUnião: \#{inspect(MapSet.to_list(uniao))}")

  inter = MapSet.intersection(frutas_a, frutas_b)
  IO.puts("Interseção: \#{inspect(MapSet.to_list(inter))}")

  diff = MapSet.difference(frutas_a, frutas_b)
  IO.puts("Diferença (A - B): \#{inspect(MapSet.to_list(diff))}")

  # member?/2 verifica se um elemento pertence ao conjunto.
  # Funções que retornam booleano terminam com "?" por convenção.
  IO.puts("\\nBanana em A? \#{MapSet.member?(frutas_a, "banana")}")
  IO.puts("Kiwi em A? \#{MapSet.member?(frutas_a, "kiwi")}")
  IO.puts("Tamanho da união: \#{MapSet.size(uniao)}")

  # Tuplas usam {} e são coleções de tamanho fixo (como tuple em Python).
  # São mais rápidas que listas para acesso por índice.
  IO.puts("\\n--- Tuplas ---")
  ponto = {10, 20, 30}
  IO.puts("Ponto: \#{inspect(ponto)}")

  # elem/2 acessa por índice (começa em 0). tuple_size/1 retorna o tamanho.
  IO.puts("Elem 0: \#{elem(ponto, 0)}")
  IO.puts("Elem 2: \#{elem(ponto, 2)}")
  IO.puts("Tamanho: \#{tuple_size(ponto)}")

  # put_elem/3 cria uma NOVA tupla com o valor alterado (imutabilidade).
  atualizado = put_elem(ponto, 1, 99)
  IO.puts("Atualizado: \#{inspect(atualizado)}")

  # Tuplas são muito usadas como retorno de funções: {:ok, valor} ou {:error, motivo}.
  # Esse padrão é a convenção de Elixir para tratamento de erros (sem exceções).
  resultados = [
    {:ok, "sucesso"},
    {:error, "não encontrado"},
    {:ok, "outro sucesso"},
    {:error, "timeout"}
  ]

  # Enum.split_with/2 divide a lista em dois grupos baseado numa condição.
  {oks, erros} = Enum.split_with(resultados, fn {status, _} -> status == :ok end)
  IO.puts("\\nOKs: \#{length(oks)}, Erros: \#{length(erros)}")
  """
})

# ── 11: Anonymous functions & closures ────────────────────────

create_playground!.(%{
  name: "[Demo] Funções Anônimas e Closures",
  description: "Lambdas, capture operator, closures e higher-order functions",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Funções Anônimas e Closures                         ║
  # ║  Lambdas, capture operator e funções de alta ordem   ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Elixir é uma linguagem funcional — funções são valores de primeira classe.
  # Você pode guardá-las em variáveis, passá-las como argumentos e retorná-las.

  # "fn args -> corpo end" cria uma função anônima (como arrow function em JS).
  # Para chamar: use ponto antes dos parênteses → somar.(3, 4)
  # O ponto diferencia funções anônimas de funções nomeadas (def).
  somar = fn a, b -> a + b end
  IO.puts("3 + 4 = \#{somar.(3, 4)}")

  # & é o capture operator — atalho para funções anônimas curtas.
  # &(&1 * 2) equivale a fn x -> x * 2 end. &1 = primeiro argumento.
  dobrar = &(&1 * 2)
  IO.puts("Dobro de 21 = \#{dobrar.(21)}")

  # Funções anônimas podem ter múltiplas cláusulas (pattern matching).
  # Elixir testa cada padrão de cima para baixo, como um switch/case.
  saudacao = fn
    "pt" -> "Olá!"
    "en" -> "Hello!"
    "es" -> "¡Hola!"
    lang -> "[\#{lang}] ???"
  end

  Enum.each(["pt", "en", "es", "jp"], fn lang ->
    IO.puts("  \#{lang}: \#{saudacao.(lang)}")
  end)

  # Closure — a função interna "captura" a variável "fator" do escopo externo.
  # Isso funciona como closures em JS: a variável fica "presa" na função.
  multiplicador = fn fator ->
    fn x -> x * fator end
  end

  triplo = multiplicador.(3)
  IO.puts("\\nTriplo de 7: \#{triplo.(7)}")
  IO.puts("Triplo de 15: \#{triplo.(15)}")

  # Higher-order functions: funções que recebem ou retornam outras funções.
  # &String.upcase/1 captura a função nomeada upcase do módulo String.
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

  # Composição de funções: criar uma nova função combinando duas.
  # compose(f, g) retorna fn x -> f(g(x)) — aplica g primeiro, depois f.
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
  # ╔══════════════════════════════════════════════════════╗
  # ║  Integer e Bitwise                                   ║
  # ║  Bases numéricas, operações bit a bit e floats       ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Elixir suporta inteiros de tamanho arbitrário (não tem overflow!),
  # operações bitwise e conversão entre bases numéricas.

  # "import Bitwise" traz os operadores &&&, |||, ^^^, <<<, >>> para o escopo.
  # Em Elixir, "import" só traz funções — diferente de import em JS/Python.
  import Bitwise

  # Integer.to_string/2 converte um número para string em qualquer base.
  # Base 2 = binário, 8 = octal, 16 = hexadecimal.
  IO.puts("=== Bases numéricas ===")
  IO.puts("Decimal 255:   \#{255}")
  IO.puts("Binário:       \#{Integer.to_string(255, 2)}")
  IO.puts("Octal:         \#{Integer.to_string(255, 8)}")
  IO.puts("Hexadecimal:   \#{Integer.to_string(255, 16)}")

  # Integer.parse/2 converte string → inteiro. Retorna {valor, resto}.
  # O pattern matching {val, ""} garante que a string inteira foi consumida.
  IO.puts("\\n=== Parse ===")
  {val, ""} = Integer.parse("42")
  IO.puts("Parse '42': \#{val}")
  {val, ""} = Integer.parse("FF", 16)
  IO.puts("Parse 'FF' base 16: \#{val}")

  # Operações bitwise manipulam bits individuais dos números.
  # 0b1010 é notação binária (valor 10 em decimal).
  # &&& = AND, ||| = OR, ^^^ = XOR, ~~~ = NOT, <<< = shift left, >>> = shift right.
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

  # Float — números com ponto decimal.
  # Float.round/2 arredonda, ceil/1 arredonda para cima, floor/1 para baixo.
  IO.puts("\\n=== Float ===")
  IO.puts("Pi aprox: \#{Float.round(3.14159265, 4)}")
  IO.puts("Ceil 4.2: \#{Float.ceil(4.2)}")
  IO.puts("Floor 4.8: \#{Float.floor(4.8)}")

  # Integer.digits/1 transforma um número em lista de dígitos.
  # IO.inspect/2 com "label:" imprime com um rótulo (útil para debug).
  IO.puts("\\n=== Dígitos ===")
  Integer.digits(12345)
  |> IO.inspect(label: "Dígitos de 12345")

  # Integer.undigits/1 reconstrói o número a partir dos dígitos.
  Integer.undigits([1, 2, 3, 4, 5])
  |> IO.inspect(label: "Reconstruído")
  """
})

# ── 13: Enum Avançado — Reduce Patterns ─────────────────────

create_playground!.(%{
  name: "[Demo] Enum Avançado — Reduce Patterns",
  description: "Padrões avançados com Enum.reduce: acumuladores, construção de maps, totais corridos",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Enum Avançado — Reduce Patterns                     ║
  # ║  Padrões poderosos com acumuladores e reduce         ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Enum.reduce/3 é a função mais poderosa do Enum — todas as outras
  # (map, filter, sum, etc.) podem ser implementadas com reduce.
  # Ele percorre a lista mantendo um "acumulador" que se transforma a cada passo.

  # 1. Construir map de frequências manualmente.
  # ~w(...) é um sigil que cria uma lista de palavras (como "...".split() em Python).
  # Map.update/4: se a chave existe, aplica a função; senão, usa o valor padrão (1).
  # &(&1 + 1) é syntax sugar para fn x -> x + 1 end.
  palavras = ~w(elixir erlang elixir phoenix elixir erlang otp)

  freq = Enum.reduce(palavras, %{}, fn palavra, acc ->
    Map.update(acc, palavra, 1, &(&1 + 1))
  end)
  IO.puts("Frequências: \#{inspect(freq)}")

  # 2. Running total — o acumulador é uma tupla {total_atual, lista_acumulada}.
  # Desestruturamos a tupla diretamente nos argumentos do fn.
  vendas = [100, 250, 75, 300, 150]
  {_, acumulado} = Enum.reduce(vendas, {0, []}, fn valor, {total, lista} ->
    novo_total = total + valor
    {novo_total, lista ++ [novo_total]}
  end)
  IO.puts("Vendas: \#{inspect(vendas)}")
  IO.puts("Acumulado: \#{inspect(acumulado)}")

  # 3. Agrupar e somar por categoria usando reduce.
  # String.to_existing_atom/1 converte string → atom (seguro, só atoms já existentes).
  # Map.update!/3 atualiza uma chave que DEVE existir (o "!" lança erro se não existir).
  transacoes = [
    %{tipo: "receita", valor: 1000},
    %{tipo: "despesa", valor: 350},
    %{tipo: "receita", valor: 500},
    %{tipo: "despesa", valor: 200},
    %{tipo: "receita", valor: 750}
  ]

  resumo = Enum.reduce(transacoes, %{receita: 0, despesa: 0}, fn t, acc ->
    chave = String.to_existing_atom(t.tipo)
    Map.update!(acc, chave, &(&1 + t.valor))
  end)
  IO.puts("\\nResumo financeiro: \#{inspect(resumo)}")
  IO.puts("Saldo: \#{resumo.receita - resumo.despesa}")

  # 4. Enum.reduce_while/3 — reduce que pode parar no meio (early return).
  # {:cont, acc} continua iterando. {:halt, acc} para imediatamente.
  numeros = [2, 4, 6, 8, 11, 12, 14]
  resultado = Enum.reduce_while(numeros, {:ok, []}, fn n, {:ok, acc} ->
    if rem(n, 2) == 0 do
      {:cont, {:ok, acc ++ [n]}}
    else
      {:halt, {:error, "encontrou ímpar: \#{n}", acc}}
    end
  end)
  IO.puts("\\nReduce while (para no primeiro ímpar):")
  IO.puts("  \#{inspect(resultado)}")

  # 5. Flatten manual — concatena sublistas numa só usando reduce.
  # ++ concatena listas (como concat em JS ou + em Python).
  nested = [[1, 2], [3, 4, 5], [6]]
  flat = Enum.reduce(nested, [], fn list, acc -> acc ++ list end)
  IO.puts("\\nFlatten manual: \#{inspect(flat)}")
  """
})

# ── 14: String — Templates e Formatação ─────────────────────

create_playground!.(%{
  name: "[Demo] String — Templates e Formatação",
  description: "Sigils, charlist vs string, Unicode, grapheme clusters e formatação avançada",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  String — Templates e Formatação Avançada            ║
  # ║  Sigils, Unicode, charlists e formatação de tabelas  ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Elixir tem suporte nativo a Unicode e oferece sigils como
  # atalhos para criar estruturas de dados comuns.

  # ~w() é um sigil de lista de palavras — divide por espaços automaticamente.
  # Sigils começam com ~ seguido de uma letra: ~r (regex), ~w (words), ~s (string).
  lista_palavras = ~w(hello world elixir phoenix)
  IO.puts("~w sigil: \#{inspect(lista_palavras)}")

  # ~w(...)a cria lista de atoms em vez de strings (o "a" no final).
  lista_atoms = ~w(get post put delete)a
  IO.puts("~w com atoms: \#{inspect(lista_atoms)}")

  # String vs Charlist: duas representações de texto em Elixir.
  # Strings (aspas duplas "") são binários UTF-8 — o padrão moderno.
  # Charlists (~c"" ou aspas simples) são listas de codepoints — compatibilidade com Erlang.
  string = "hello"
  charlist = ~c"hello"
  IO.puts("\\nString: \#{inspect(string, binaries: :as_strings)}")
  IO.puts("Charlist: \#{inspect(charlist)}")
  IO.puts("String bytes: \#{byte_size(string)}")
  IO.puts("Charlist length: \#{length(charlist)}")

  # Unicode: String.length conta grafemas (caracteres visuais), não bytes.
  # Um emoji de família pode ocupar muitos bytes mas é 1 grafema visual.
  emoji = "👨‍👩‍👧‍👦"
  IO.puts("\\nEmoji: \#{emoji}")
  IO.puts("String.length: \#{String.length(emoji)}")
  IO.puts("byte_size: \#{byte_size(emoji)}")
  IO.puts("Graphemes: \#{inspect(String.graphemes(emoji))}")

  # "café" tem 4 grafemas mas 5 bytes (o "é" ocupa 2 bytes em UTF-8).
  cafe = "café"
  IO.puts("\\n'\#{cafe}' tem \#{String.length(cafe)} grafemas e \#{byte_size(cafe)} bytes")

  # Formatação de tabela usando String.pad_trailing para alinhar colunas.
  # Tuplas são usadas aqui como "registros" leves (como namedtuple em Python).
  dados = [
    {"Elixir", "2012", "José Valim"},
    {"Erlang", "1986", "Ericsson"},
    {"Ruby", "1995", "Matz"},
    {"Go", "2009", "Google"}
  ]

  IO.puts("\\n\#{String.pad_trailing("Lang", 10)} \#{String.pad_trailing("Ano", 6)} Criador")
  IO.puts(String.duplicate("-", 35))
  Enum.each(dados, fn {lang, ano, criador} ->
    IO.puts("\#{String.pad_trailing(lang, 10)} \#{String.pad_trailing(ano, 6)} \#{criador}")
  end)

  # Heredoc (triple quotes) cria strings multiline com interpolação.
  # Similar a template literals (``) em JS ou triple quotes em Python.
  template = \"""
  Nome: \#{String.upcase("alice")}
  Data: \#{Date.utc_today()}
  Status: Ativo
  \"""
  IO.puts("\\nTemplate:\\n\#{template}")
  """
})

# ── 15: Regex — Validação e Extração ────────────────────────

create_playground!.(%{
  name: "[Demo] Regex — Validação e Extração",
  description: "Named captures, scan, replace, validadores (CPF, telefone, URL)",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Regex — Validação e Extração de Dados               ║
  # ║  Expressões regulares para buscar e validar texto    ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Regex (expressões regulares) são padrões para buscar texto.
  # Em Elixir, usamos o sigil ~r/padrão/ para criar regex.
  # Funciona como /padrão/ em JS ou re.compile() em Python.

  # Regex.named_captures/2 extrai partes nomeadas (?<nome>...) como um map.
  # \\d{4} = exatamente 4 dígitos. Os nomes viram chaves do map resultado.
  regex = ~r/(?<ano>\\d{4})-(?<mes>\\d{2})-(?<dia>\\d{2})/
  captures = Regex.named_captures(regex, "2026-04-16")
  IO.puts("Named captures: \#{inspect(captures)}")

  # Regex.scan/3 encontra TODAS as ocorrências (não só a primeira).
  # capture: :all_but_first retorna só os grupos de captura (parênteses).
  texto = "Preços: R$10.50, R$25.00 e R$3.99"
  precos = Regex.scan(~r/R\\$(\\d+\\.\\d{2})/, texto, capture: :all_but_first)
  IO.puts("\\nPreços encontrados: \#{inspect(List.flatten(precos))}")

  # Criamos uma função auxiliar para validar vários formatos.
  # Regex.match?/2 retorna true/false — a regex encaixa na string?
  validar = fn nome, regex, valor ->
    valido = Regex.match?(regex, valor)
    IO.puts("  \#{nome}: '\#{valor}' => \#{if valido, do: "✓", else: "✗"}")
  end

  IO.puts("\\n--- Validações ---")

  # ^ = início da string, $ = fim. \\w = letra/dígito/underscore.
  # O /i no final torna case-insensitive (ignora maiúsculas/minúsculas).
  email_re = ~r/^[\\w.+-]+@[\\w.-]+\\.[a-z]{2,}$/i
  validar.("Email", email_re, "user@example.com")
  validar.("Email", email_re, "invalid@")

  # \\(? = parêntese opcional. \\d{2} = 2 dígitos. \\s? = espaço opcional.
  phone_re = ~r/^\\(?\\d{2}\\)?\\s?9?\\d{4}-?\\d{4}$/
  validar.("Phone", phone_re, "(11) 99876-5432")
  validar.("Phone", phone_re, "1234")

  # Validação de formato de CPF (apenas formato, não verifica dígitos).
  cpf_re = ~r/^\\d{3}\\.\\d{3}\\.\\d{3}-\\d{2}$/
  validar.("CPF", cpf_re, "123.456.789-00")
  validar.("CPF", cpf_re, "12345678900")

  # Regex.replace/3 pode receber uma função que transforma cada match.
  # [A-Z]{2,} = 2 ou mais letras maiúsculas seguidas.
  IO.puts("\\n--- Replace ---")
  texto = "O ELIXIR é uma LINGUAGEM funcional"
  resultado = Regex.replace(~r/[A-Z]{2,}/, texto, fn match ->
    String.capitalize(String.downcase(match))
  end)
  IO.puts("Original:  \#{texto}")
  IO.puts("Corrigido: \#{resultado}")

  # Exemplo prático: extrair campos de uma linha de log.
  # Named captures transformam texto não-estruturado em um map organizado.
  log = "2026-04-16 10:30:45 [INFO] User login: user_id=42 ip=192.168.1.1"
  parsed = Regex.named_captures(
    ~r/(?<date>[\\d-]+) (?<time>[\\d:]+) \\[(?<level>\\w+)\\] (?<message>.+)/,
    log
  )
  IO.puts("\\nLog parsed: \#{inspect(parsed, pretty: true)}")
  """
})

# ── 16: Access e Nested Data ────────────────────────────────

create_playground!.(%{
  name: "[Demo] Access e Nested Data",
  description: "get_in/put_in/update_in, Access.key, Access.at, estruturas profundamente aninhadas",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Access e Nested Data                                ║
  # ║  Navegar e atualizar dados profundamente aninhados   ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Em dados reais, maps e listas ficam aninhados vários níveis.
  # O módulo Access + get_in/put_in/update_in permitem acessar
  # e modificar dados profundos sem código verboso.

  # Estrutura aninhada: empresa → departamentos → membros → skills.
  empresa = %{
    nome: "Acme Corp",
    departamentos: [
      %{nome: "Engenharia", membros: [
        %{nome: "Alice", cargo: "Tech Lead", skills: ["elixir", "erlang"]},
        %{nome: "Bob", cargo: "Dev", skills: ["elixir", "javascript"]}
      ]},
      %{nome: "Produto", membros: [
        %{nome: "Carol", cargo: "PM", skills: ["analytics", "ux"]}
      ]}
    ]
  }

  # get_in/2 navega pela estrutura seguindo um "caminho" de chaves.
  # Access.at(0) acessa o elemento no índice 0 de uma lista.
  # É como empresa.departamentos[0].nome em JS, mas funcional.
  primeiro_dept = get_in(empresa, [:departamentos, Access.at(0), :nome])
  IO.puts("Primeiro departamento: \#{primeiro_dept}")

  alice_cargo = get_in(empresa, [:departamentos, Access.at(0), :membros, Access.at(0), :cargo])
  IO.puts("Cargo da Alice: \#{alice_cargo}")

  # update_in/3 atualiza um valor profundo, criando uma NOVA estrutura.
  # A função fn _ -> "Senior Dev" end recebe o valor antigo e retorna o novo.
  atualizado = update_in(empresa, [:departamentos, Access.at(0), :membros, Access.at(1), :cargo],
    fn _ -> "Senior Dev" end
  )
  novo_cargo = get_in(atualizado, [:departamentos, Access.at(0), :membros, Access.at(1), :cargo])
  IO.puts("\\nBob promovido para: \#{novo_cargo}")

  # put_in/3 insere ou substitui um valor no caminho especificado.
  com_email = put_in(empresa, [:departamentos, Access.at(0), :membros, Access.at(0), :email],
    "alice@acme.com"
  )
  email = get_in(com_email, [:departamentos, Access.at(0), :membros, Access.at(0), :email])
  IO.puts("Email adicionado: \#{email}")

  # Access.all() percorre TODOS os elementos de uma lista no caminho.
  # É como um map implícito — retorna uma lista com os valores de cada elemento.
  todos_nomes = get_in(empresa, [:departamentos, Access.all(), :nome])
  IO.puts("\\nTodos departamentos: \#{inspect(todos_nomes)}")

  todos_membros = get_in(empresa, [:departamentos, Access.all(), :membros, Access.all(), :nome])
  IO.puts("Todos membros: \#{inspect(List.flatten(todos_membros))}")

  # Access.filter/1 filtra elementos da lista durante a navegação.
  # &(&1.ativo) é syntax sugar para fn item -> item.ativo end.
  config = %{
    features: [
      %{nome: "dark_mode", ativo: true},
      %{nome: "beta_ui", ativo: false},
      %{nome: "notifications", ativo: true}
    ]
  }

  ativos = get_in(config, [:features, Access.filter(&(&1.ativo)), :nome])
  IO.puts("\\nFeatures ativas: \#{inspect(ativos)}")

  # Quando as chaves são strings (comum em JSON decodificado), use strings no caminho.
  # Maps com string keys usam ["chave"] em vez de :chave.
  json_data = %{"user" => %{"profile" => %{"avatar" => "pic.jpg", "bio" => "Dev"}}}
  avatar = get_in(json_data, ["user", "profile", "avatar"])
  IO.puts("\\nAvatar (string keys): \#{avatar}")
  """
})

# ── 17: Stream — Lazy Processing ────────────────────────────

create_playground!.(%{
  name: "[Demo] Stream — Lazy Processing",
  description: "Stream.unfold, sequências infinitas, processamento eficiente de grandes volumes",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Stream — Lazy Processing (Processamento Preguiçoso) ║
  # ║  Sequências infinitas e processamento eficiente      ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Enum é "eager" — processa TODA a coleção imediatamente.
  # Stream é "lazy" — só processa quando o resultado é necessário.
  # Isso permite trabalhar com sequências infinitas e economizar memória.

  IO.puts("=== Enum vs Stream ===")

  # Enum cria uma lista intermediária a cada passo (3 listas no total).
  resultado_enum = 1..10
    |> Enum.map(fn x -> x * 2 end)
    |> Enum.filter(fn x -> x > 10 end)
    |> Enum.take(3)
  IO.puts("Enum (eager): \#{inspect(resultado_enum)}")

  # Stream encadeia as transformações sem executar nada.
  # Só processa quando Enum.take/2 "puxa" os resultados.
  # Funciona com 1 MILHÃO de itens sem criar listas intermediárias!
  # 1_000_000 — underscores em números são só para legibilidade.
  resultado_stream = 1..1_000_000
    |> Stream.map(fn x -> x * 2 end)
    |> Stream.filter(fn x -> x > 10 end)
    |> Enum.take(3)
  IO.puts("Stream (lazy, de 1M items): \#{inspect(resultado_stream)}")

  # Stream.unfold/2 gera sequências a partir de um estado.
  # Retorna {valor_emitido, próximo_estado}. Retornar nil encerra.
  IO.puts("\\n=== Stream.unfold ===")

  # Fibonacci INFINITO — só calculamos os que pedirmos com Enum.take.
  fib_stream = Stream.unfold({0, 1}, fn {a, b} -> {a, {b, a + b}} end)
  primeiros_15 = Enum.take(fib_stream, 15)
  IO.puts("Fibonacci (15): \#{inspect(primeiros_15)}")

  # Potências de 2: estado começa em 1, cada passo dobra.
  potencias = Stream.unfold(1, fn n -> {n, n * 2} end)
  IO.puts("Potências de 2: \#{inspect(Enum.take(potencias, 10))}")

  # Sequência de Collatz — conjectura matemática famosa.
  # nil como retorno encerra o stream (quando chega em 1).
  # "when" é um guard — condição extra no pattern matching.
  collatz = fn n ->
    Stream.unfold(n, fn
      1 -> nil
      x when rem(x, 2) == 0 -> {x, div(x, 2)}
      x -> {x, x * 3 + 1}
    end)
  end
  seq = Enum.to_list(collatz.(27))
  IO.puts("\\nCollatz(27): \#{length(seq)} passos")
  IO.puts("  Início: \#{inspect(Enum.take(seq, 10))}...")
  IO.puts("  Max: \#{Enum.max(seq)}")

  # Stream.iterate/2 aplica uma função repetidamente ao resultado anterior.
  # Stream.take_while/2 continua enquanto a condição for verdadeira.
  IO.puts("\\n=== Stream.iterate ===")
  countdown = Stream.iterate(10, &(&1 - 1))
    |> Stream.take_while(&(&1 >= 0))
    |> Enum.to_list()
  IO.puts("Countdown: \#{inspect(countdown)}")

  # Stream.cycle/1 repete uma lista infinitamente (como itertools.cycle em Python).
  # Enum.zip para automaticamente quando a lista menor acaba.
  cores = Stream.cycle(["vermelho", "verde", "azul"])
  atribuicoes = Enum.zip(1..9, cores) |> Enum.map(fn {i, c} -> "Item \#{i}: \#{c}" end)
  IO.puts("\\nCycle: \#{inspect(atribuicoes)}")

  # Combinando múltiplos streams infinitos.
  IO.puts("\\n=== Combinando Streams ===")
  nomes = Stream.cycle(["Alice", "Bob", "Carol"])
  ids = Stream.iterate(1, &(&1 + 1))
  equipe = Enum.zip(ids, nomes) |> Enum.take(6)
  IO.puts("Equipe: \#{inspect(equipe)}")
  """
})

# ── 18: Enum.zip + Enum.with_index ─────────────────────────

create_playground!.(%{
  name: "[Demo] Enum.zip + Enum.with_index",
  description: "Iteração paralela, indexada, tabelas de lookup e transposição de matriz",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Enum.zip + Enum.with_index                         ║
  # ║  Iteração paralela, indexada e transposição          ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Enum.zip combina múltiplas listas em pares/tuplas (como zip() em Python).
  # Enum.with_index adiciona um índice numérico a cada elemento.

  # Enum.zip/2 pareia elementos na mesma posição: {nomes[0], idades[0]}, etc.
  # Para quando a lista mais curta acaba.
  nomes = ["Alice", "Bob", "Carol", "Diana"]
  idades = [28, 34, 22, 31]
  cidades = ["SP", "RJ", "BH", "POA"]

  pares = Enum.zip(nomes, idades)
  IO.puts("Zip (2 listas): \#{inspect(pares)}")

  # Enum.zip/1 com lista de listas — combina 3+ listas em tuplas.
  triplas = Enum.zip([nomes, idades, cidades])
  IO.puts("Zip (3 listas): \#{inspect(triplas)}")

  # Map.new/1 cria um map a partir de pares {chave, valor}.
  # Zip + Map.new é um padrão comum para criar dicionários de duas listas.
  mapa = Map.new(Enum.zip(nomes, idades))
  IO.puts("Map from zip: \#{inspect(mapa)}")

  # Enum.with_index/2 adiciona um índice a cada elemento.
  # O segundo argumento (1) define o índice inicial (padrão é 0).
  IO.puts("\\n--- with_index ---")
  frutas = ["maçã", "banana", "cereja", "damasco"]

  Enum.with_index(frutas, 1) |> Enum.each(fn {fruta, i} ->
    IO.puts("  \#{i}. \#{fruta}")
  end)

  # Criar uma lookup table: índice → valor (como um array indexado).
  # Map.new/2 com função transforma cada par antes de criar o map.
  lookup = frutas |> Enum.with_index() |> Map.new(fn {v, i} -> {i, v} end)
  IO.puts("\\nLookup[2]: \#{lookup[2]}")

  # Transposição de matriz — trocar linhas por colunas.
  # Enum.zip_with/2 "zippa" as sublistas e aplica uma função.
  # &Function.identity/1 retorna o argumento sem modificar (função identidade).
  IO.puts("\\n--- Transposição de Matriz ---")
  matriz = [
    [1, 2, 3],
    [4, 5, 6],
    [7, 8, 9]
  ]

  IO.puts("Original:")
  Enum.each(matriz, fn row -> IO.puts("  \#{inspect(row)}") end)

  transposta = Enum.zip_with(matriz, &Function.identity/1)
  IO.puts("Transposta:")
  Enum.each(transposta, fn row -> IO.puts("  \#{inspect(row)}") end)

  # Produto escalar (dot product): zip os vetores e soma os produtos.
  # É um padrão clássico de álgebra linear usando zip + reduce.
  a = [1, 2, 3]
  b = [4, 5, 6]
  dot = Enum.zip(a, b) |> Enum.reduce(0, fn {x, y}, acc -> acc + x * y end)
  IO.puts("\\nProduto escalar \#{inspect(a)} · \#{inspect(b)} = \#{dot}")

  # Ranking: ordenar por score e adicionar posição.
  # Pattern matching aninhado: {{nome, score}, pos} extrai tudo de uma vez.
  IO.puts("\\n--- Ranking ---")
  scores = [{"Alice", 95}, {"Bob", 87}, {"Carol", 92}, {"Diana", 98}]
  scores
  |> Enum.sort_by(fn {_, s} -> s end, :desc)
  |> Enum.with_index(1)
  |> Enum.each(fn {{nome, score}, pos} ->
    medalha = case pos do
      1 -> "🥇"
      2 -> "🥈"
      3 -> "🥉"
      _ -> "  "
    end
    IO.puts("  \#{medalha} \#{pos}. \#{nome} — \#{score} pts")
  end)
  """
})

# ── 19: URI e Base — Encoding ───────────────────────────────

create_playground!.(%{
  name: "[Demo] URI e Base — Encoding",
  description: "URI encode/decode, query string, Base64, hex encoding",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  URI e Base — Encoding e Decoding                    ║
  # ║  URLs, Base64, Hex e criptografia básica             ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Encoding transforma dados para formatos seguros de transporte.
  # URI encoding é essencial para URLs, Base64 para dados binários.

  # URI.encode/1 escapa caracteres especiais para uso em URLs.
  # Espaços, acentos e símbolos são convertidos para %XX.
  IO.puts("=== URI ===")
  texto = "olá mundo! café & chá"
  encoded = URI.encode(texto)
  IO.puts("Encoded: \#{encoded}")
  IO.puts("Decoded: \#{URI.decode(encoded)}")

  # URI.encode_www_form/1 é mais agressivo — escapa &, =, etc.
  # Usado para parâmetros de formulário (application/x-www-form-urlencoded).
  param = "nome=João & Maria"
  encoded_comp = URI.encode_www_form(param)
  IO.puts("\\nWWW form: \#{encoded_comp}")
  IO.puts("Decoded:  \#{URI.decode_www_form(encoded_comp)}")

  # URI.parse/1 decompõe uma URL em suas partes (struct URI).
  # Uma URL tem: scheme (https), host, port, path, query e fragment (#).
  url = "https://api.example.com:8443/v1/users?page=2&limit=10#section"
  parsed = URI.parse(url)
  IO.puts("\\nParsed URL:")
  IO.puts("  Scheme: \#{parsed.scheme}")
  IO.puts("  Host:   \#{parsed.host}")
  IO.puts("  Port:   \#{parsed.port}")
  IO.puts("  Path:   \#{parsed.path}")
  IO.puts("  Query:  \#{parsed.query}")
  IO.puts("  Fragment: \#{parsed.fragment}")

  # URI.decode_query/1 transforma "page=2&limit=10" em um map.
  params = URI.decode_query(parsed.query)
  IO.puts("  Params: \#{inspect(params)}")

  # URI.encode_query/1 faz o inverso — map → query string.
  query = URI.encode_query(%{search: "elixir phoenix", page: 1, sort: "desc"})
  IO.puts("\\nBuilt query: \#{query}")

  # Base64 codifica dados binários como texto ASCII.
  # Muito usado para enviar imagens, tokens e dados em APIs.
  IO.puts("\\n=== Base64 ===")
  original = "Hello, Elixir! 🚀"
  b64 = Base.encode64(original)
  IO.puts("Original:  \#{original}")
  IO.puts("Base64:    \#{b64}")
  IO.puts("Decoded:   \#{Base.decode64!(b64)}")

  # URL-safe Base64 substitui +/ por -_ (seguro para URLs).
  b64url = Base.url_encode64(original)
  IO.puts("\\nURL-safe Base64: \#{b64url}")
  IO.puts("Decoded:         \#{Base.url_decode64!(b64url)}")

  # Hex encoding — cada byte vira 2 caracteres hexadecimais.
  IO.puts("\\n=== Hex ===")
  data = "secret"
  hex = Base.encode16(data, case: :lower)
  IO.puts("\#{data} => hex: \#{hex}")
  IO.puts("hex => \#{Base.decode16!(String.upcase(hex))}")

  # :crypto.hash/2 é uma função do Erlang (Elixir roda na mesma VM).
  # Módulos Erlang começam com : (atom). SHA256 gera um hash de 256 bits.
  fake_hash = :crypto.hash(:sha256, "elixir") |> Base.encode16(case: :lower)
  IO.puts("\\nSHA256('elixir'): \#{fake_hash}")
  """
})

# ── 20: NaiveDateTime e Calendar ────────────────────────────

create_playground!.(%{
  name: "[Demo] NaiveDateTime e Calendar",
  description: "Aritmética temporal, Calendar.ISO, dia do ano, ano bissexto, semana do ano",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  NaiveDateTime e Calendar                            ║
  # ║  Aritmética temporal e calendário ISO                ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # NaiveDateTime = data + hora SEM timezone (sem fuso horário).
  # Use quando o timezone não importa (logs, timestamps internos).
  # Para timezone, use DateTime (com biblioteca como Tz/Tzdata).

  # NaiveDateTime.utc_now/0 retorna data+hora atual sem timezone info.
  agora = NaiveDateTime.utc_now()
  IO.puts("Agora (naive): \#{NaiveDateTime.to_string(agora)}")

  # NaiveDateTime.add/3 soma segundos (3600 = 1 hora, 86400 = 1 dia).
  # Valores negativos subtraem tempo.
  daqui_1h = NaiveDateTime.add(agora, 3600, :second)
  IO.puts("+ 1 hora: \#{NaiveDateTime.to_string(daqui_1h)}")

  ontem = NaiveDateTime.add(agora, -86400, :second)
  IO.puts("- 1 dia: \#{NaiveDateTime.to_string(ontem)}")

  # NaiveDateTime.diff/2 calcula a diferença em segundos.
  diff_seconds = NaiveDateTime.diff(daqui_1h, agora)
  IO.puts("\\nDiferença: \#{diff_seconds} segundos")

  # NaiveDateTime.compare/2 retorna :lt (menor), :eq (igual) ou :gt (maior).
  # Não use < ou > com datas — use compare/2.
  IO.puts("agora < daqui_1h? \#{NaiveDateTime.compare(agora, daqui_1h) == :lt}")

  # Calendar.ISO é o calendário padrão (gregoriano).
  # Oferece funções utilitárias como leap_year?, days_in_month, etc.
  IO.puts("\\n=== Calendar ===")
  hoje = Date.utc_today()
  IO.puts("Dia do ano: \#{Date.day_of_year(hoje)}/\#{if Calendar.ISO.leap_year?(hoje.year), do: 366, else: 365}")
  IO.puts("Ano bissexto? \#{Calendar.ISO.leap_year?(hoje.year)}")
  IO.puts("Dia da semana: \#{Date.day_of_week(hoje)} (1=seg, 7=dom)")

  # Visualizar dias em cada mês com barras.
  # O ";" permite múltiplas expressões na mesma linha (como em C/Java).
  IO.puts("\\nDias por mês em \#{hoje.year}:")
  1..12
  |> Enum.each(fn mes ->
    dias = Calendar.ISO.days_in_month(hoje.year, mes)
    nome = case mes do
      1 -> "Jan"; 2 -> "Fev"; 3 -> "Mar"; 4 -> "Abr"
      5 -> "Mai"; 6 -> "Jun"; 7 -> "Jul"; 8 -> "Ago"
      9 -> "Set"; 10 -> "Out"; 11 -> "Nov"; 12 -> "Dez"
    end
    barra = String.duplicate("█", dias)
    IO.puts("  \#{nome}: \#{barra} \#{dias}")
  end)

  # Enum.filter com capture operator — &Calendar.ISO.leap_year?/1
  # passa cada ano como argumento para a função.
  proximos = Enum.filter(hoje.year..hoje.year+20, &Calendar.ISO.leap_year?/1)
  IO.puts("\\nPróximos bissextos: \#{inspect(proximos)}")

  # Date.new/3 (sem !) retorna {:ok, data} ou {:error, razão}.
  # Usamos pattern matching para extrair o valor.
  # |> then(fn ... end) — then/2 passa o valor para uma função inline.
  {:ok, data} = Date.new(2026, 12, 31)
  IO.puts("\\nÚltimo dia de 2026: \#{data} (\#{Date.day_of_week(data) |> then(fn
    1 -> "Segunda"
    2 -> "Terça"
    3 -> "Quarta"
    4 -> "Quinta"
    5 -> "Sexta"
    6 -> "Sábado"
    7 -> "Domingo"
  end)})")
  """
})

# ── 21: Data Pipeline — ETL Completo ────────────────────────

create_playground!.(%{
  name: "[Demo] Data Pipeline — ETL Completo",
  description: "Pipeline real: parse CSV, validação, transformação, agregação e relatório",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Data Pipeline — ETL Completo                        ║
  # ║  Extract, Transform, Load: do CSV bruto ao JSON      ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # ETL é um padrão clássico de processamento de dados:
  # Extract (extrair dados brutos) → Transform (limpar/enriquecer)
  # → Load (carregar/exportar). Muito comum em data engineering.

  # 1. EXTRACT — dados brutos simulando um arquivo CSV.
  # Heredoc (\""" ... \""") cria strings multiline.
  csv_raw = \"""
  nome,departamento,salario,ativo
  Alice,Engenharia,8500,true
  Bob,Engenharia,7200,true
  Carol,Produto,9000,true
  Diana,Engenharia,8800,true
  Eve,Marketing,6500,false
  Frank,Produto,7800,true
  Grace,Marketing,7000,true
  Hank,Engenharia,9200,true
  Ivy,Produto,6800,true
  Jack,Marketing,5500,true
  \"""

  # 2. PARSE — transformar texto em dados estruturados.
  # [header | rows] separa a primeira linha (cabeçalho) das demais.
  # String.trim/1 remove espaços/newlines extras nas bordas.
  [header | rows] = csv_raw
    |> String.trim()
    |> String.split("\\n")

  campos = String.split(header, ",")
  IO.puts("Campos: \#{inspect(campos)}")

  # Enum.zip + Map.new — pareia nomes dos campos com valores de cada linha.
  # Resultado: [%{"nome" => "Alice", "salario" => "8500", ...}, ...]
  registros = Enum.map(rows, fn row ->
    valores = String.split(row, ",")
    Enum.zip(campos, valores) |> Map.new()
  end)
  IO.puts("Registros parseados: \#{length(registros)}")

  # 3. TRANSFORM — converter tipos e filtrar.
  # String.to_integer/1 converte "8500" → 8500.
  # & &1.ativo é syntax sugar: fn item -> item.ativo end.
  transformados = registros
    |> Enum.map(fn r ->
      %{
        nome: r["nome"],
        departamento: r["departamento"],
        salario: String.to_integer(r["salario"]),
        ativo: r["ativo"] == "true"
      }
    end)
    |> Enum.filter(& &1.ativo)  # só ativos

  IO.puts("Após filtro (ativos): \#{length(transformados)}")

  # 4. AGGREGATE — agrupar por departamento e calcular estatísticas.
  # Enum.group_by/2 retorna %{"Engenharia" => [...], "Produto" => [...]}.
  por_dept = Enum.group_by(transformados, & &1.departamento)

  IO.puts("\\n=== Relatório por Departamento ===")
  IO.puts(String.duplicate("─", 55))

  # Enum.map sobre o map agrupado — {dept, membros} é cada par chave-valor.
  resumo = Enum.map(por_dept, fn {dept, membros} ->
    salarios = Enum.map(membros, & &1.salario)
    total = Enum.sum(salarios)
    media = div(total, length(salarios))
    max = Enum.max(salarios)
    min = Enum.min(salarios)

    IO.puts("\#{String.pad_trailing(dept, 12)} | \#{length(membros)} pessoas | média: R$\#{media} | range: R$\#{min}-R$\#{max}")

    %{departamento: dept, count: length(membros), media: media, total: total}
  end)

  IO.puts(String.duplicate("─", 55))

  # 5. REPORT — totais gerais usando reduce para somar campos.
  total_geral = Enum.reduce(resumo, 0, fn r, acc -> acc + r.total end)
  total_pessoas = Enum.reduce(resumo, 0, fn r, acc -> acc + r.count end)
  IO.puts("TOTAL: \#{total_pessoas} pessoas, folha = R$\#{total_geral}")
  IO.puts("Média geral: R$\#{div(total_geral, total_pessoas)}")

  # 6. EXPORT — gerar JSON formatado com Jason.
  # Em produção, esse JSON seria salvo em arquivo ou enviado a uma API.
  IO.puts("\\n=== JSON Export ===")
  Jason.encode!(%{
    gerado_em: Date.to_string(Date.utc_today()),
    departamentos: resumo,
    total_folha: total_geral
  }, pretty: true) |> IO.puts()
  """
})

# ── 22: Mini Interpretador ──────────────────────────────────

create_playground!.(%{
  name: "[Demo] Mini Interpretador",
  description: "Calculadora com parser usando pattern matching e recursão — mostra o poder da plataforma",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  Mini Interpretador de Expressões Matemáticas        ║
  # ║  Tokenização + Parsing + Avaliação com recursão      ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Este é um exemplo avançado que constrói uma calculadora completa:
  # 1. Tokenizer: "2 + 3 * 4" → [{:num, 2}, {:op, :add}, {:num, 3}, ...]
  # 2. Parser: tokens → árvore de expressão (com precedência * antes de +)
  # 3. Evaluator: calcula o resultado final
  # Demonstra o poder de pattern matching + recursão em Elixir.

  # Tokenizer — transforma string em lista de tokens.
  # Cada token é um atom (:lparen) ou tupla ({:num, 42}, {:op, :add}).
  # A função se chama recursivamente para processar o resto da string.
  # String.slice(input, 1..-1//1) — pega do índice 1 até o final (remove 1º char).
  tokenize = fn tokenize_fn, input ->
    input = String.trim(input)
    cond do
      input == "" -> []
      String.starts_with?(input, " ") ->
        tokenize_fn.(tokenize_fn, String.trim_leading(input))
      String.starts_with?(input, "(") ->
        [:lparen | tokenize_fn.(tokenize_fn, String.slice(input, 1..-1//1))]
      String.starts_with?(input, ")") ->
        [:rparen | tokenize_fn.(tokenize_fn, String.slice(input, 1..-1//1))]
      String.starts_with?(input, "+") ->
        [{:op, :add} | tokenize_fn.(tokenize_fn, String.slice(input, 1..-1//1))]
      String.starts_with?(input, "-") ->
        [{:op, :sub} | tokenize_fn.(tokenize_fn, String.slice(input, 1..-1//1))]
      String.starts_with?(input, "*") ->
        [{:op, :mul} | tokenize_fn.(tokenize_fn, String.slice(input, 1..-1//1))]
      String.starts_with?(input, "/") ->
        [{:op, :div} | tokenize_fn.(tokenize_fn, String.slice(input, 1..-1//1))]
      true ->
        # Regex para capturar números inteiros ou decimais.
        case Regex.run(~r/^\\d+(\\.\\d+)?/, input) do
          [num | _] ->
            rest = String.slice(input, String.length(num)..-1//1)
            val = if String.contains?(num, "."), do: String.to_float(num), else: String.to_integer(num)
            [{:num, val} | tokenize_fn.(tokenize_fn, rest)]
          nil ->
            raise "Unexpected character: \#{String.first(input)}"
        end
    end
  end

  # Evaluator — avalia tokens respeitando precedência de operadores.
  # Usa "recursive descent parsing": parse_factor → parse_term → parse_expr.
  # Cada nível trata operadores de mesma precedência.
  eval_expr = fn eval_fn, tokens ->
    # Fator: número literal ou expressão entre parênteses.
    parse_factor = fn parse_fn, tokens ->
      case tokens do
        [{:num, n} | rest] -> {n, rest}
        [:lparen | rest] ->
          {val, rest} = eval_fn.(eval_fn, rest)
          [:rparen | rest] = rest
          {val, rest}
      end
    end

    # Termo: multiplicação e divisão (maior precedência que +/-).
    parse_term = fn parse_term_fn, tokens ->
      {left, rest} = parse_factor.(parse_factor, tokens)
      case rest do
        [{:op, :mul} | rest] ->
          {right, rest} = parse_term_fn.(parse_term_fn, rest)
          {left * right, rest}
        [{:op, :div} | rest] ->
          {right, rest} = parse_term_fn.(parse_term_fn, rest)
          {left / right, rest}
        _ -> {left, rest}
      end
    end

    # Expressão: adição e subtração (menor precedência).
    {left, rest} = parse_term.(parse_term, tokens)
    case rest do
      [{:op, :add} | rest] ->
        {right, rest} = eval_fn.(eval_fn, rest)
        {left + right, rest}
      [{:op, :sub} | rest] ->
        {right, rest} = eval_fn.(eval_fn, rest)
        {left - right, rest}
      _ -> {left, rest}
    end
  end

  # Função principal: tokeniza → avalia → retorna resultado.
  # {result, []} — o pattern matching garante que TODOS os tokens foram consumidos.
  calc = fn expr ->
    tokens = tokenize.(tokenize, expr)
    {result, []} = eval_expr.(eval_expr, tokens)
    result
  end

  # Testar com várias expressões!
  expressoes = [
    "2 + 3",
    "10 * 5",
    "100 / 4",
    "2 + 3 * 4",
    "(2 + 3) * 4",
    "10 + 20 + 30",
    "(100 - 40) / 3"
  ]

  IO.puts("=== Mini Calculadora ===\\n")
  Enum.each(expressoes, fn expr ->
    resultado = calc.(expr)
    display = if is_float(resultado) and Float.round(resultado, 0) == resultado,
      do: round(resultado), else: resultado
    IO.puts("  \#{String.pad_trailing(expr, 20)} = \#{display}")
  end)
  """
})

# ══════════════════════════════════════════════════════════════
#  HTTP / REST — Playgrounds with external API calls
# ══════════════════════════════════════════════════════════════

IO.puts("\n── Creating HTTP Playgrounds ──")

# ── 23: HTTP — APIs Públicas ─────────────────────────────────

create_playground!.(%{
  name: "[Demo] HTTP — APIs Públicas",
  description: "GET em APIs públicas, parse de JSON — usando Blackboex.Playgrounds.Http",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  HTTP — APIs Públicas (GET e POST)                   ║
  # ║  Chamar APIs REST e processar respostas JSON         ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # APIs REST são serviços web que você acessa via HTTP (o protocolo da web).
  # Os métodos mais comuns são:
  #   GET  → buscar dados (como abrir uma URL no navegador)
  #   POST → enviar dados (como submeter um formulário)
  # As respostas geralmente vêm em JSON. Status 200 = sucesso.
  #
  # O playground tem um client HTTP seguro embutido (Http module).

  # "alias" cria um atalho para o nome completo do módulo.
  # Sem alias, teríamos que escrever Blackboex.Playgrounds.Http.get(...).
  alias Blackboex.Playgrounds.Http

  IO.puts("=== JSONPlaceholder API ===\\n")

  # Http.get/1 faz uma requisição GET e retorna {:ok, resposta} ou {:error, razão}.
  # O "case" faz pattern matching na resposta para tratar cada cenário.
  # %{status: 200, body: body} — extraímos o corpo da resposta quando status é 200.
  case Http.get("https://jsonplaceholder.typicode.com/users/1") do
    {:ok, %{status: 200, body: body}} ->
      # Jason.decode!/1 transforma o JSON (string) em um map Elixir.
      user = Jason.decode!(body)
      IO.puts("Usuário:")
      IO.puts("  Nome: \#{user["name"]}")
      IO.puts("  Email: \#{user["email"]}")
      # get_in/2 navega dados aninhados (como user.address.city em JS).
      IO.puts("  Cidade: \#{get_in(user, ["address", "city"])}")
      IO.puts("  Empresa: \#{get_in(user, ["company", "name"])}")

    {:ok, %{status: status}} ->
      IO.puts("Erro HTTP: \#{status}")

    {:error, reason} ->
      IO.puts("Falha: \#{reason}")
  end

  # GET com query parameters — ?userId=1 filtra posts do usuário 1.
  # Query params vão na URL após o "?" e são separados por "&".
  IO.puts("\\n=== Posts do Usuário 1 ===\\n")

  case Http.get("https://jsonplaceholder.typicode.com/posts?userId=1") do
    {:ok, %{status: 200, body: body}} ->
      posts = Jason.decode!(body)
      IO.puts("Total de posts: \#{length(posts)}\\n")

      posts
      |> Enum.take(3)
      |> Enum.each(fn post ->
        titulo = String.slice(post["title"], 0, 50)
        IO.puts("  #\#{post["id"]} \#{titulo}")
      end)

      IO.puts("  ... e mais \#{length(posts) - 3}")

    {:error, reason} ->
      IO.puts("Falha: \#{reason}")
  end

  # POST envia dados ao servidor. O corpo é JSON codificado.
  # O header "content-type: application/json" informa o formato dos dados.
  # JSONPlaceholder é uma API fake — aceita o POST mas não salva de verdade.
  IO.puts("\\n=== POST — Criar Post ===\\n")

  novo_post = Jason.encode!(%{
    title: "Meu post via Playground",
    body: "Criado com Blackboex.Playgrounds.Http!",
    userId: 1
  })

  case Http.post("https://jsonplaceholder.typicode.com/posts", novo_post,
    [{"content-type", "application/json"}]) do
    {:ok, %{status: status, body: body}} ->
      criado = Jason.decode!(body)
      IO.puts("Status: \#{status}")
      IO.puts("Post criado com ID: \#{criado["id"]}")
      IO.puts("Título: \#{criado["title"]}")

    {:error, reason} ->
      IO.puts("Falha: \#{reason}")
  end
  """
})

# ── 24: HTTP — Busca de CEP ─────────────────────────────────

create_playground!.(%{
  name: "[Demo] HTTP — Busca de CEP",
  description: "Consulta a API pública ViaCEP para buscar endereços por CEP",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  HTTP — Busca de CEP via ViaCEP                      ║
  # ║  Consultar endereços brasileiros por CEP             ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # ViaCEP é uma API pública gratuita que retorna endereços por CEP.
  # API REST: fazemos um GET para a URL com o CEP e recebemos JSON.
  # URL: https://viacep.com.br/ws/{cep}/json/
  # Não precisa de autenticação (API aberta).

  alias Blackboex.Playgrounds.Http

  # Criamos uma função que encapsula a lógica de busca.
  # Retorna {:ok, dados} ou {:error, motivo} — o padrão Elixir para erros.
  # Map.has_key?/2 verifica se o map contém uma chave específica.
  buscar_cep = fn cep ->
    url = "https://viacep.com.br/ws/\#{cep}/json/"
    case Http.get(url) do
      {:ok, %{status: 200, body: body}} ->
        dados = Jason.decode!(body)
        if Map.has_key?(dados, "erro") do
          {:error, "CEP não encontrado"}
        else
          {:ok, dados}
        end
      {:ok, %{status: status}} ->
        {:error, "HTTP \#{status}"}
      {:error, reason} ->
        {:error, reason}
    end
  end

  # Função para formatar o endereço a partir dos dados da API.
  # <> concatena strings (como + em JS/Python).
  # Enum.reject/2 remove elementos indesejados (vazios ou nil).
  # Enum.join/2 junta a lista em uma string com separador.
  formatar_endereco = fn dados ->
    partes = [
      dados["logradouro"],
      dados["bairro"],
      dados["localidade"] <> "/" <> dados["uf"]
    ] |> Enum.reject(&(&1 == "" or is_nil(&1)))

    Enum.join(partes, ", ")
  end

  # Lista de CEPs conhecidos para testar.
  # Cada elemento é uma tupla {cep, descrição}.
  ceps = [
    {"01001-000", "Praça da Sé (SP)"},
    {"20040-020", "Centro do Rio (RJ)"},
    {"30130-000", "Centro de BH (MG)"},
    {"80010-000", "Centro de Curitiba (PR)"}
  ]

  IO.puts("=== Busca de CEP ===\\n")

  # Iteramos sobre cada CEP, chamamos a API e exibimos o resultado.
  # O pattern matching no "case" trata sucesso e erro separadamente.
  Enum.each(ceps, fn {cep, desc} ->
    IO.puts("CEP \#{cep} (\#{desc}):")
    case buscar_cep.(cep) do
      {:ok, dados} ->
        IO.puts("  Endereço: \#{formatar_endereco.(dados)}")
        IO.puts("  IBGE: \#{dados["ibge"]}\\n")
      {:error, reason} ->
        IO.puts("  Erro: \#{reason}\\n")
    end
  end)
  """
})

# ── 25: HTTP — Dados Públicos ────────────────────────────────

create_playground!.(%{
  name: "[Demo] HTTP — Dados Públicos e JSON",
  description: "Buscar dados públicos de APIs, processar e formatar resultados",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  HTTP — Dados Públicos e JSON                        ║
  # ║  Explorar APIs públicas: todos, headers e echo       ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # APIs REST seguem convenções:
  #   URL identifica o recurso (ex: /todos, /users/1)
  #   Query params filtram (?userId=1&_limit=5)
  #   Headers carregam metadados (Content-Type, Authorization)
  #   O corpo (body) traz os dados em JSON

  alias Blackboex.Playgrounds.Http

  # 1. GET com múltiplos query params — filtra tarefas do usuário 1.
  # & separa parâmetros na URL: ?userId=1&_limit=5.
  IO.puts("=== Todos & Albums ===\\n")

  case Http.get("https://jsonplaceholder.typicode.com/todos?userId=1&_limit=5") do
    {:ok, %{status: 200, body: body}} ->
      todos = Jason.decode!(body)
      # Enum.count/2 conta elementos que satisfazem a condição.
      # & &1["completed"] é syntax sugar para fn item -> item["completed"] end.
      completos = Enum.count(todos, & &1["completed"])
      IO.puts("Tarefas do Usuário 1 (primeiras 5):")
      IO.puts("  Completas: \#{completos}/\#{length(todos)}")
      Enum.each(todos, fn todo ->
        status = if todo["completed"], do: "✓", else: "○"
        IO.puts("  \#{status} \#{todo["title"]}")
      end)

    {:error, reason} ->
      IO.puts("Erro: \#{reason}")
  end

  # 2. HTTPBin é uma API de teste que retorna informações sobre sua requisição.
  # /headers mostra quais headers HTTP o servidor recebeu de você.
  # Headers são metadados invisíveis que acompanham toda requisição HTTP.
  IO.puts("\\n=== HTTPBin — Headers ===\\n")

  case Http.get("https://httpbin.org/headers") do
    {:ok, %{status: 200, body: body}} ->
      data = Jason.decode!(body)
      headers = data["headers"]
      IO.puts("Seus headers vistos pelo servidor:")
      Enum.each(headers, fn {k, v} ->
        IO.puts("  \#{k}: \#{v}")
      end)

    {:error, reason} ->
      IO.puts("Erro: \#{reason}")
  end

  # 3. POST echo — o servidor retorna exatamente o que enviamos.
  # Útil para testar se o payload está formatado corretamente.
  # Jason.encode!/1 converte o map Elixir → string JSON para enviar.
  IO.puts("\\n=== HTTPBin — POST Echo ===\\n")

  payload = Jason.encode!(%{
    playground: "blackboex",
    timestamp: DateTime.to_string(DateTime.utc_now()),
    dados: [1, 2, 3]
  })

  # O 3º argumento são headers HTTP — lista de tuplas {"nome", "valor"}.
  # "content-type: application/json" diz ao servidor que o corpo é JSON.
  case Http.post("https://httpbin.org/post", payload,
    [{"content-type", "application/json"}]) do
    {:ok, %{status: 200, body: body}} ->
      data = Jason.decode!(body)
      IO.puts("Servidor recebeu:")
      IO.puts("  JSON: \#{data["data"]}")
      IO.puts("  Content-Type: \#{get_in(data, ["headers", "Content-Type"])}")

    {:error, reason} ->
      IO.puts("Erro: \#{reason}")
  end
  """
})

# ── 26: HTTP — Iterando Lista com API ────────────────────────

create_playground!.(%{
  name: "[Demo] HTTP — Iterando Lista com API",
  description: "Iterar uma lista de IDs, chamar API para cada um, agregar resultados",
  code: """
  # ╔══════════════════════════════════════════════════════╗
  # ║  HTTP — Iterando Lista com API                       ║
  # ║  Buscar detalhes de vários recursos via REST         ║
  # ╚══════════════════════════════════════════════════════╝
  #
  # Padrão comum em APIs REST: você tem uma lista de IDs e precisa
  # buscar os detalhes de cada um com chamadas GET individuais.
  # Em REST, cada recurso tem uma URL única: /users/1, /users/2, etc.

  alias Blackboex.Playgrounds.Http

  # Lista de IDs para buscar. Cada ID será uma chamada HTTP separada.
  user_ids = [1, 2, 3, 4, 5]

  IO.puts("=== Buscando \#{length(user_ids)} usuários ===\\n")

  # Enum.map transforma cada ID em um resultado (map com dados ou erro).
  # Para cada ID, fazemos GET na URL /users/{id} e extraímos os campos.
  resultados = Enum.map(user_ids, fn id ->
    case Http.get("https://jsonplaceholder.typicode.com/users/\#{id}") do
      {:ok, %{status: 200, body: body}} ->
        user = Jason.decode!(body)
        # Construímos um map limpo com só os campos que queremos.
        %{
          id: user["id"],
          nome: user["name"],
          email: user["email"],
          empresa: get_in(user, ["company", "name"]),
          cidade: get_in(user, ["address", "city"])
        }

      {:error, reason} ->
        %{id: id, erro: reason}
    end
  end)

  # Formatar como tabela usando String.pad_trailing para alinhar colunas.
  # <> concatena strings (como + em JS/Python).
  IO.puts(String.pad_trailing("ID", 4) <>
    String.pad_trailing("Nome", 25) <>
    String.pad_trailing("Cidade", 15) <>
    "Empresa")
  IO.puts(String.duplicate("─", 70))

  # Pattern matching direto no fn: duas cláusulas para erro e sucesso.
  # %{erro: _} = r — o padrão verifica se o map tem chave :erro.
  Enum.each(resultados, fn
    %{erro: _} = r -> IO.puts("  \#{r.id}: ERRO")
    r ->
      IO.puts(
        String.pad_trailing(Integer.to_string(r.id), 4) <>
        String.pad_trailing(r.nome, 25) <>
        String.pad_trailing(r.cidade, 15) <>
        r.empresa
      )
  end)

  # Agregar: extrair empresas únicas dos resultados.
  # Enum.reject filtra fora os erros, Enum.uniq remove duplicatas.
  empresas = resultados
    |> Enum.reject(&Map.has_key?(&1, :erro))
    |> Enum.map(& &1.empresa)
    |> Enum.uniq()

  IO.puts("\\nEmpresas encontradas: \#{length(empresas)}")
  Enum.each(empresas, fn e -> IO.puts("  • \#{e}") end)

  # O playground limita a 5 chamadas HTTP por execução (segurança).
  IO.puts("\\n💡 Dica: use Api.call_flow/2 para delegar")
  IO.puts("   processamento pesado a um fluxo do projeto!")
  """
})

# ══════════════════════════════════════════════════════════════
#  FLOW + API — Demo flow + playgrounds that call it
# ══════════════════════════════════════════════════════════════

IO.puts("\n── Creating Demo Flow ──")

# Clean previous demo flows
Flows.list_flows_for_project(project.id)
|> Enum.filter(&String.starts_with?(&1.name, "[Demo]"))
|> Enum.each(fn f -> Flows.delete_flow(f) end)

# Create a simple Echo/Transform flow for playground demos
{:ok, demo_flow} = Flows.create_flow(%{
  name: "[Demo] Echo Transform",
  description: "Fluxo demo que recebe dados, transforma e retorna. Usado pelos playgrounds de API.",
  organization_id: org.id,
  project_id: project.id,
  user_id: user.id,
  definition: %{
    "version" => "1.0",
    "nodes" => [
      %{
        "id" => "n1",
        "type" => "start",
        "position" => %{"x" => 50, "y" => 200},
        "data" => %{
          "name" => "Start",
          "execution_mode" => "sync",
          "timeout" => 10_000,
          "payload_schema" => [
            %{"name" => "message", "type" => "string", "required" => false, "constraints" => %{}},
            %{"name" => "items", "type" => "string", "required" => false, "constraints" => %{}}
          ],
          "state_schema" => [
            %{"name" => "result", "type" => "string", "required" => false, "constraints" => %{}, "initial_value" => ""}
          ]
        }
      },
      %{
        "id" => "n2",
        "type" => "elixir_code",
        "position" => %{"x" => 300, "y" => 200},
        "data" => %{
          "name" => "Transform",
          "code" => ~S"""
          message = input["message"] || "no message"
          items = input["items"]

          result = cond do
            is_list(items) ->
              processed = Enum.map(items, fn item ->
                if is_map(item) do
                  Map.put(item, "processed", true)
                else
                  %{"value" => item, "processed" => true}
                end
              end)
              %{"message" => message, "items" => processed, "count" => length(processed)}

            true ->
              %{"echo" => message, "timestamp" => DateTime.to_string(DateTime.utc_now())}
          end

          {result, Map.put(state, "result", inspect(result))}
          """
        }
      },
      %{
        "id" => "n3",
        "type" => "end",
        "position" => %{"x" => 550, "y" => 200},
        "data" => %{"name" => "End"}
      }
    ],
    "edges" => [
      %{"id" => "e1", "source" => "n1", "source_port" => 0, "target" => "n2", "target_port" => 0},
      %{"id" => "e2", "source" => "n2", "source_port" => 0, "target" => "n3", "target_port" => 0}
    ]
  }
})

# Activate the flow so it can receive webhook calls
case Flows.activate_flow(demo_flow) do
  {:ok, activated_flow} ->
    IO.puts("  ✓ Flow: #{activated_flow.name} (token: #{activated_flow.webhook_token})")

    # Store the token for playground references
    flow_token = activated_flow.webhook_token

    # ── 27: API — Chamando Fluxo do Projeto ──────────────────────

    create_playground!.(%{
      name: "[Demo] API — Chamando Fluxo do Projeto",
      description: "Invocar um fluxo do projeto via webhook usando Blackboex.Playgrounds.Api",
      code: """
      # ╔══════════════════════════════════════════════════════╗
      # ║  API — Chamando Fluxo do Projeto via Webhook         ║
      # ║  Invocar um fluxo interno usando o módulo Api        ║
      # ╚══════════════════════════════════════════════════════╝
      #
      # Um "fluxo" é um pipeline de processamento que você cria no projeto.
      # Ele é acessível via webhook — uma URL que aceita requisições POST.
      # O webhook é uma forma de APIs se comunicarem: o playground envia
      # dados via POST e o fluxo processa e retorna o resultado.
      #
      # Api.call_flow/2 encapsula essa chamada HTTP POST de forma segura.

      # "alias" importa o módulo para usar com nome curto.
      alias Blackboex.Playgrounds.Api

      # O token identifica e autentica o fluxo (como uma senha de API).
      token = "#{flow_token}"

      IO.puts("=== Chamando Fluxo via Webhook ===\\n")

      # 1. Chamada simples — enviamos um map com "message" e o fluxo ecoa.
      # Api.call_flow/2 retorna {:ok, resposta} ou {:error, motivo}.
      IO.puts("1. Echo simples:")
      case Api.call_flow(token, %{"message" => "Olá do Playground!"}) do
        {:ok, %{"output" => output}} ->
          IO.puts("   Echo: \#{inspect(output)}")
        {:ok, response} ->
          IO.puts("   Resposta: \#{inspect(response)}")
        {:error, reason} ->
          IO.puts("   Erro: \#{reason}")
      end

      # 2. Chamada com lista de items — o fluxo processa cada item.
      # Maps com chaves string (=>) são usados para compatibilidade com JSON.
      IO.puts("\\n2. Processando lista de items:")
      items = [
        %{"nome" => "Widget A", "preco" => 10},
        %{"nome" => "Widget B", "preco" => 25},
        %{"nome" => "Widget C", "preco" => 15}
      ]

      case Api.call_flow(token, %{"message" => "Processar items", "items" => items}) do
        {:ok, %{"output" => output}} ->
          IO.puts("   Processados: \#{output["count"]} items")
          # || é o operador "or" — se output["items"] for nil, usa lista vazia.
          Enum.each(output["items"] || [], fn item ->
            IO.puts("   • \#{item["nome"] || item["value"]} (processed: \#{item["processed"]})")
          end)
        {:ok, response} ->
          IO.puts("   Resposta: \#{inspect(response)}")
        {:error, reason} ->
          IO.puts("   Erro: \#{reason}")
      end

      # O fluxo é acessível via POST /webhook/{token} — padrão REST.
      IO.puts("\\n💡 O fluxo é chamado via POST /webhook/\#{String.slice(token, 0, 8)}...")
      IO.puts("   Toda a autenticação e rate limiting do webhook se aplicam.")
      """
    })

    # ── 28: API — Iterando e Chamando Fluxo ──────────────────────

    create_playground!.(%{
      name: "[Demo] API — Iterando e Chamando Fluxo",
      description: "Iterar uma lista e chamar um fluxo para cada item — padrão batch processing",
      code: """
      # ╔══════════════════════════════════════════════════════╗
      # ║  API — Iterando e Chamando Fluxo (Batch Processing) ║
      # ║  Processar vários pedidos delegando a um fluxo       ║
      # ╚══════════════════════════════════════════════════════╝
      #
      # Batch processing é processar uma lista de itens em lote.
      # Aqui iteramos sobre pedidos e chamamos o fluxo para cada um.
      # Cada chamada é um POST HTTP ao webhook do fluxo.
      # Em REST: POST /webhook/{token} com o pedido no corpo (body).

      alias Blackboex.Playgrounds.Api

      # Token de autenticação do fluxo (identifica qual fluxo chamar).
      token = "#{flow_token}"

      # Lista de pedidos — cada um é um map com "message" e "items".
      # Maps com => (string keys) são compatíveis com JSON.
      pedidos = [
        %{"message" => "Pedido #001", "items" => [%{"produto" => "Notebook", "qtd" => 1}]},
        %{"message" => "Pedido #002", "items" => [%{"produto" => "Mouse", "qtd" => 3}, %{"produto" => "Teclado", "qtd" => 1}]},
        %{"message" => "Pedido #003", "items" => [%{"produto" => "Monitor", "qtd" => 2}]}
      ]

      IO.puts("=== Batch Processing via Fluxo ===\\n")
      IO.puts("Processando \#{length(pedidos)} pedidos...\\n")

      # Enum.map processa cada pedido e retorna uma lista de resultados.
      # Cada resultado é uma tupla de 3 elementos: {status, mensagem, dados}.
      resultados = Enum.map(pedidos, fn pedido ->
        case Api.call_flow(token, pedido) do
          {:ok, %{"output" => output}} ->
            # || 0 — se output["count"] for nil, usa 0 como padrão.
            count = output["count"] || 0
            IO.puts("  ✓ \#{pedido["message"]} → \#{count} item(s) processados")
            {:ok, pedido["message"], output}

          {:ok, response} ->
            IO.puts("  ✓ \#{pedido["message"]} → resposta recebida")
            {:ok, pedido["message"], response}

          {:error, reason} ->
            IO.puts("  ✗ \#{pedido["message"]} → erro: \#{reason}")
            {:error, pedido["message"], reason}
        end
      end)

      # Resumo — contar sucessos e falhas usando Enum.count com filtro.
      # O pattern matching {status, _, _} extrai só o primeiro elemento da tupla.
      sucessos = Enum.count(resultados, fn {status, _, _} -> status == :ok end)
      falhas = length(resultados) - sucessos

      IO.puts("\\n=== Resumo ===")
      IO.puts("  Total: \#{length(resultados)}")
      IO.puts("  Sucesso: \#{sucessos}")
      IO.puts("  Falhas: \#{falhas}")

      # Limite de segurança: máximo 5 chamadas HTTP por execução.
      IO.puts("\\n💡 Cada chamada a Api.call_flow/2 faz um POST HTTP")
      IO.puts("   para o webhook do fluxo. O limite é 5 chamadas por execução.")
      IO.puts("   Para volumes maiores, use o próprio fluxo com um nó de iteração.")
      """
    })

  {:error, reason} ->
    IO.puts("  ✗ Flow activation failed: #{inspect(reason)}")
    IO.puts("    (Flow-dependent playgrounds will show errors when run)")

    # Still create the playgrounds with placeholder token
    create_playground!.(%{
      name: "[Demo] API — Chamando Fluxo do Projeto",
      description: "Invocar um fluxo do projeto via webhook usando Blackboex.Playgrounds.Api",
      code: """
      # ╔══════════════════════════════════════════════════════╗
      # ║  API — Chamando Fluxo do Projeto                     ║
      # ║  Este playground precisa de um fluxo ativo            ║
      # ╚══════════════════════════════════════════════════════╝
      #
      # ⚠️ Para funcionar, crie um fluxo no projeto, ative-o,
      # e substitua o token abaixo pelo webhook_token do fluxo.
      #
      # Api.call_flow/2 faz um POST HTTP ao webhook do fluxo,
      # enviando os dados como JSON no corpo da requisição.

      # "alias" cria um atalho para o nome completo do módulo.
      alias Blackboex.Playgrounds.Api

      # Substitua pelo token real do seu fluxo.
      token = "SEU_WEBHOOK_TOKEN_AQUI"

      # O "case" trata o resultado: {:ok, _} para sucesso, {:error, _} para falha.
      case Api.call_flow(token, %{"message" => "Olá do Playground!"}) do
        {:ok, result} -> IO.inspect(result)
        {:error, reason} -> IO.puts("Erro: \#{reason}")
      end
      """
    })

    create_playground!.(%{
      name: "[Demo] API — Iterando e Chamando Fluxo",
      description: "Iterar uma lista e chamar um fluxo para cada item — padrão batch processing",
      code: """
      # ╔══════════════════════════════════════════════════════╗
      # ║  API — Iterando e Chamando Fluxo (Batch)            ║
      # ║  Este playground precisa de um fluxo ativo            ║
      # ╚══════════════════════════════════════════════════════╝
      #
      # ⚠️ Para funcionar, crie um fluxo no projeto, ative-o,
      # e substitua o token abaixo pelo webhook_token do fluxo.
      #
      # Batch processing: iterar uma lista e chamar uma API
      # (neste caso, o fluxo via webhook) para cada item.

      alias Blackboex.Playgrounds.Api

      # Substitua pelo token real do seu fluxo.
      token = "SEU_WEBHOOK_TOKEN_AQUI"

      # Enum.each/2 itera sobre a lista executando a função para cada item.
      # Cada item gera uma chamada POST HTTP ao webhook do fluxo.
      items = ["item1", "item2", "item3"]
      Enum.each(items, fn item ->
        case Api.call_flow(token, %{"message" => item}) do
          {:ok, result} -> IO.puts("✓ \#{item}: \#{inspect(result)}")
          {:error, reason} -> IO.puts("✗ \#{item}: \#{reason}")
        end
      end)
      """
    })
end

IO.puts("\n✅ Demo seed complete!")
IO.puts("   Pages: #{length(Pages.list_pages(project.id))} total")
IO.puts("   Playgrounds: #{length(Playgrounds.list_playgrounds(project.id))} total")
IO.puts("   Flows: #{length(Flows.list_flows_for_project(project.id))} total")
