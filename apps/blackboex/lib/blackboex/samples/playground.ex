defmodule Blackboex.Samples.Playground do
  @moduledoc """
  Playground samples in the platform-wide sample catalogue.

  Cada exemplo é um snippet Elixir single-cell que respeita o sandbox do
  `Blackboex.Playgrounds.Executor`: usa apenas módulos do allowlist, captura
  saída via `IO.puts`/`IO.inspect`, e respeita os limites de tempo/heap/HTTP.
  """

  alias Blackboex.Samples.Flow
  alias Blackboex.Samples.Id

  @spec list() :: [map()]
  def list do
    echo_flow_uuid = Flow.echo_transform().sample_uuid

    [
      enum_basics(),
      call_echo_flow(echo_flow_uuid),
      pipe_operator(),
      pattern_matching(),
      with_clauses(),
      comprehensions(),
      map_keyword(),
      streams_lazy(),
      string_manipulation(),
      date_time_math(),
      regex_validation(),
      range_basics(),
      tuple_basics(),
      read_env_vars(),
      http_get(),
      http_post_json(),
      jason_parsing(),
      error_handling(),
      base64_encoding(),
      atom_safety()
    ]
    |> Enum.with_index()
    |> Enum.map(fn {sample, index} -> Map.put(sample, :position, index) end)
  end

  defp enum_basics do
    %{
      kind: :playground,
      id: "enum_basics",
      sample_uuid: Id.uuid(:playground, "enum_basics"),
      name: "[Demo] Enum - Transformacoes Basicas",
      description: "Map, filter and reduce examples with Enum.",
      category: "Elixir",
      code: """
      lista = [1, 2, 3, 4, 5]

      dobrados = Enum.map(lista, fn x -> x * 2 end)
      pares = Enum.filter(lista, fn x -> rem(x, 2) == 0 end)
      soma = Enum.reduce(lista, 0, fn x, acc -> x + acc end)

      IO.puts("Dobrados: \#{inspect(dobrados)}")
      IO.puts("Pares: \#{inspect(pares)}")
      IO.puts("Soma: \#{soma}")
      """
    }
  end

  defp call_echo_flow(echo_flow_uuid) do
    %{
      kind: :playground,
      id: "call_echo_flow",
      sample_uuid: Id.uuid(:playground, "call_echo_flow"),
      flow_sample_uuid: echo_flow_uuid,
      name: "[Demo] API - Chamando Fluxo do Projeto",
      description: "Calls the managed Echo Transform flow from playground code.",
      category: "Blackboex",
      code: """
      alias Blackboex.Playgrounds.Api

      token = "{{flow:#{echo_flow_uuid}:webhook_token}}"

      case Api.call_flow(token, %{"message" => "Ola do Playground!"}) do
        {:ok, response} -> IO.inspect(response, label: "Resposta")
        {:error, reason} -> IO.puts("Erro: \#{reason}")
      end
      """
    }
  end

  defp pipe_operator do
    %{
      kind: :playground,
      id: "pipe_operator",
      sample_uuid: Id.uuid(:playground, "pipe_operator"),
      name: "[Demo] Pipe Operator |>",
      description: "Encadeando transformações com o operador pipe.",
      category: "Elixir",
      code: """
      # Sem pipe — leitura de dentro pra fora, difícil de seguir
      sem_pipe = Enum.sum(Enum.map(Enum.filter([1, 2, 3, 4, 5], &(&1 > 2)), &(&1 * 10)))
      IO.puts("Sem pipe: \#{sem_pipe}")

      # Com pipe — leitura linear, do dado bruto até o resultado
      com_pipe =
        [1, 2, 3, 4, 5]
        |> Enum.filter(&(&1 > 2))
        |> Enum.map(&(&1 * 10))
        |> Enum.sum()

      IO.puts("Com pipe: \#{com_pipe}")

      # Idiomatico: cada etapa é uma transformação clara
      """
    }
  end

  defp pattern_matching do
    %{
      kind: :playground,
      id: "pattern_matching",
      sample_uuid: Id.uuid(:playground, "pattern_matching"),
      name: "[Demo] Pattern Matching com case",
      description: "Casamento de padrões em tuplas, mapas e listas.",
      category: "Elixir",
      code: """
      # Tuple match comum em Elixir: {:ok, valor} | {:error, motivo}
      resultado = {:ok, %{user_id: 42, role: :admin}}

      case resultado do
        {:ok, %{role: :admin} = user} ->
          IO.puts("Admin id=\#{user.user_id}")

        {:ok, %{role: role}} ->
          IO.puts("Usuario com role \#{role}")

        {:error, motivo} ->
          IO.puts("Falhou: \#{motivo}")
      end

      # Pattern em listas: head | tail
      [primeiro | resto] = [10, 20, 30]
      IO.puts("Primeiro=\#{primeiro}, resto=\#{inspect(resto)}")

      # Pin operator (^) para casar com valor de variavel
      esperado = 5
      case 5 do
        ^esperado -> IO.puts("igual ao esperado")
        outro -> IO.puts("diferente: \#{outro}")
      end
      """
    }
  end

  defp with_clauses do
    %{
      kind: :playground,
      id: "with_clauses",
      sample_uuid: Id.uuid(:playground, "with_clauses"),
      name: "[Demo] with - Encadeando ok/error",
      description: "Compor operações que retornam {:ok, _} | {:error, _}.",
      category: "Elixir",
      code: """
      # Funcoes auxiliares simulando steps que podem falhar
      parse_int = fn str ->
        case Integer.parse(str) do
          {n, ""} -> {:ok, n}
          _ -> {:error, "nao eh inteiro"}
        end
      end

      validar_positivo = fn n ->
        if n > 0, do: {:ok, n}, else: {:error, "precisa ser > 0"}
      end

      dobrar = fn n -> {:ok, n * 2} end

      # `with` para no primeiro {:error, _} e devolve esse erro.
      # Sem `with`, isso seria 3 cases aninhados.
      processar = fn entrada ->
        with {:ok, n} <- parse_int.(entrada),
             {:ok, n} <- validar_positivo.(n),
             {:ok, dobrado} <- dobrar.(n) do
          {:ok, dobrado}
        end
      end

      IO.inspect(processar.("10"), label: "10")
      IO.inspect(processar.("-5"), label: "-5")
      IO.inspect(processar.("abc"), label: "abc")
      """
    }
  end

  defp comprehensions do
    %{
      kind: :playground,
      id: "comprehensions",
      sample_uuid: Id.uuid(:playground, "comprehensions"),
      name: "[Demo] Comprehensions com for",
      description: "Geradores, filtros e produto cartesiano com for.",
      category: "Elixir",
      code: """
      # Comprehension simples: gerar quadrados de pares
      quadrados_de_pares =
        for x <- 1..10, rem(x, 2) == 0, do: x * x

      IO.inspect(quadrados_de_pares, label: "quadrados de pares")

      # Multiplos geradores = produto cartesiano
      tabuada =
        for a <- 1..3, b <- 1..3, do: {a, b, a * b}

      IO.inspect(tabuada, label: "tabuada 1..3")

      # `:into` para construir mapa
      por_indice =
        for {item, idx} <- Enum.with_index(["a", "b", "c"]), into: %{}, do: {idx, item}

      IO.inspect(por_indice, label: "por indice")
      """
    }
  end

  defp map_keyword do
    %{
      kind: :playground,
      id: "map_keyword",
      sample_uuid: Id.uuid(:playground, "map_keyword"),
      name: "[Demo] Map vs Keyword List",
      description: "Quando usar map e quando usar keyword list.",
      category: "Elixir",
      code: """
      # Map: chaves UNICAS, ordem nao garantida, acesso O(log n)
      usuario = %{nome: "Ana", idade: 30, role: :admin}
      IO.puts("Nome: \#{usuario.nome}")
      atualizado = %{usuario | idade: 31}
      IO.inspect(atualizado, label: "map atualizado")

      # Keyword: lista de tuplas {atom, valor}, mantem ordem,
      # permite duplicatas, ideal para opcoes de funcao
      opts = [timeout: 5_000, retries: 3, label: "primary"]
      IO.puts("Timeout: \#{Keyword.get(opts, :timeout)}")
      IO.puts("Retries: \#{Keyword.fetch!(opts, :retries)}")

      # Estilo Elixir: opts como ultimo argumento de funcao
      get_opt = fn lista, chave, padrao -> Keyword.get(lista, chave, padrao) end
      IO.puts("Default ausente: \#{get_opt.(opts, :missing, "padrao")}")
      """
    }
  end

  defp streams_lazy do
    %{
      kind: :playground,
      id: "streams_lazy",
      sample_uuid: Id.uuid(:playground, "streams_lazy"),
      name: "[Demo] Stream - Avaliacao Preguicosa",
      description: "Pipelines lazy com Stream — terminam só ao consumir.",
      category: "Elixir",
      code: """
      # Stream nao executa nada ate alguem consumir.
      # Aqui montamos um pipeline gigante mas paramos no primeiro `take`.
      pipeline =
        1..1_000_000
        |> Stream.map(fn x ->
          # se isto rodasse pra todos, gastaria muita CPU.
          x * x
        end)
        |> Stream.filter(fn x -> rem(x, 7) == 0 end)
        |> Stream.take(5)

      # Consumir converte stream em lista
      resultado = Enum.to_list(pipeline)
      IO.inspect(resultado, label: "5 quadrados divisíveis por 7")

      # Comparativo: o mesmo com Enum geraria a lista intermediaria inteira.
      # Stream eh ideal para fontes potencialmente infinitas ou grandes.
      """
    }
  end

  defp string_manipulation do
    %{
      kind: :playground,
      id: "string_manipulation",
      sample_uuid: Id.uuid(:playground, "string_manipulation"),
      name: "[Demo] String - Split, Replace, Capitalize",
      description: "Operações comuns de manipulação de strings UTF-8.",
      category: "Elixir",
      code: """
      frase = "  Blackboex roda Elixir no Playground  "

      normalizada =
        frase
        |> String.trim()
        |> String.downcase()
        |> String.replace(" ", "-")

      IO.puts("Slug: \#{normalizada}")

      # Split + capitalize palavra a palavra (titlecase)
      titulo =
        "ola mundo da programacao"
        |> String.split(" ")
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

      IO.puts("Titulo: \#{titulo}")

      # Strings em Elixir sao binarios UTF-8
      IO.puts("Bytes: \#{byte_size("café")}")
      IO.puts("Graphemes: \#{String.length("café")}")
      """
    }
  end

  defp date_time_math do
    %{
      kind: :playground,
      id: "date_time_math",
      sample_uuid: Id.uuid(:playground, "date_time_math"),
      name: "[Demo] DateTime - Diferencas e Comparacoes",
      description: "Aritmética de datas e formatação ISO 8601.",
      category: "Elixir",
      code: """
      agora = DateTime.utc_now()
      IO.puts("Agora UTC: \#{DateTime.to_iso8601(agora)}")

      uma_hora_atras = DateTime.add(agora, -3600, :second)
      IO.puts("Uma hora atras: \#{DateTime.to_iso8601(uma_hora_atras)}")

      diff_segundos = DateTime.diff(agora, uma_hora_atras, :second)
      IO.puts("Diferenca: \#{diff_segundos}s")

      # Date para o dia atual + 30
      hoje = Date.utc_today()
      em_30_dias = Date.add(hoje, 30)
      IO.puts("Hoje: \#{hoje}, em 30 dias: \#{em_30_dias}")

      # Comparacoes retornam :lt | :eq | :gt
      IO.puts("Comparando: \#{Date.compare(hoje, em_30_dias)}")
      """
    }
  end

  defp regex_validation do
    %{
      kind: :playground,
      id: "regex_validation",
      sample_uuid: Id.uuid(:playground, "regex_validation"),
      name: "[Demo] Regex - Validar e Extrair",
      description: "Match, capturas nomeadas e replace com Regex.",
      category: "Elixir",
      code: """
      # Validacao simples de email
      email_regex = ~r/^[\\w.+-]+@[\\w-]+\\.[\\w.-]+$/

      Enum.each(["ok@example.com", "sem-arroba", "a@b.co"], fn entrada ->
        if Regex.match?(email_regex, entrada) do
          IO.puts("OK: \#{entrada}")
        else
          IO.puts("FAIL: \#{entrada}")
        end
      end)

      # Capturas nomeadas
      log = "2026-05-04 12:30:45 [error] timeout"
      padrao = ~r/^(?<data>[\\d-]+) (?<hora>[\\d:]+) \\[(?<nivel>\\w+)\\] (?<msg>.+)$/

      case Regex.named_captures(padrao, log) do
        nil -> IO.puts("nao casou")
        capturas -> IO.inspect(capturas, label: "log estruturado")
      end

      # Replace com captura
      texto_anonimizado = Regex.replace(~r/(\\d{3})\\d{3}(\\d{3})/, "12345-678901", "\\\\1***\\\\2")
      IO.puts("anonimizado: \#{texto_anonimizado}")
      """
    }
  end

  defp range_basics do
    %{
      kind: :playground,
      id: "range_basics",
      sample_uuid: Id.uuid(:playground, "range_basics"),
      name: "[Demo] Range - Sequencias Eficientes",
      description: "Range é um Enumerable barato — nada de listar tudo.",
      category: "Elixir",
      code: """
      # Range nao materializa a lista — fica como {:range, first, last, step}
      r = 1..1_000_000
      IO.puts("Tipo: \#{inspect(r.__struct__)}")
      IO.puts("Primeiro: \#{r.first}, ultimo: \#{r.last}")

      # Operacoes Enum funcionam, mas alocam quando precisa
      soma = Enum.sum(1..100)
      IO.puts("Soma 1..100 = \#{soma}")

      # Range com passo (step) negativo
      decrescente = 10..1//-2
      IO.inspect(Enum.to_list(decrescente), label: "10..1 com passo -2")

      # Junto com Stream para ficar lazy
      primeiros_pares =
        1..1_000
        |> Stream.filter(&(rem(&1, 2) == 0))
        |> Enum.take(5)

      IO.inspect(primeiros_pares, label: "5 primeiros pares")
      """
    }
  end

  defp tuple_basics do
    %{
      kind: :playground,
      id: "tuple_basics",
      sample_uuid: Id.uuid(:playground, "tuple_basics"),
      name: "[Demo] Tuples - Quando usar",
      description: "Tuples para retornos fixos; mapas para dados nomeados.",
      category: "Elixir",
      code: """
      # Tuple eh ideal para retornos com aridade fixa: {:ok, valor} | {:error, _}
      dividir = fn
        _, 0 -> {:error, :divisao_por_zero}
        a, b -> {:ok, a / b}
      end

      IO.inspect(dividir.(10, 2), label: "10/2")
      IO.inspect(dividir.(10, 0), label: "10/0")

      # Acesso por indice (raro): elem/2
      coord = {3.5, 7.2}
      IO.puts("x=\#{elem(coord, 0)}, y=\#{elem(coord, 1)}")

      # Atualizar tuple cria nova
      atualizada = put_elem(coord, 0, 99.9)
      IO.inspect(atualizada, label: "coord atualizada")

      # Para dados crescentes/nomeados, prefira maps
      ponto_map = %{x: 3.5, y: 7.2, z: 0.0}
      IO.inspect(%{ponto_map | x: 99.9}, label: "ponto como map")
      """
    }
  end

  defp read_env_vars do
    %{
      kind: :playground,
      id: "read_env_vars",
      sample_uuid: Id.uuid(:playground, "read_env_vars"),
      name: "[Demo] Project Env Vars",
      description: "Lendo variáveis configuradas em Project Settings.",
      category: "Blackboex",
      code: """
      # `env` eh um binding automatico no Playground.
      # Configure variaveis em Project Settings -> Env Vars.

      api_url = env["API_URL"]
      api_key = env["API_KEY"]

      cond do
        is_nil(api_url) ->
          IO.puts("API_URL nao configurada — defina em Project Settings")

        is_nil(api_key) ->
          IO.puts("API_KEY nao configurada — defina em Project Settings")

        true ->
          # Mascara a key no log para nao vazar
          mascarada = String.slice(api_key, 0, 4) <> "****"
          IO.puts("Pronto para chamar \#{api_url} com key \#{mascarada}")
      end

      # Tamanho do mapa (zero quando nada configurado)
      IO.puts("Total de variaveis: \#{map_size(env)}")
      """
    }
  end

  defp http_get do
    %{
      kind: :playground,
      id: "http_get",
      sample_uuid: Id.uuid(:playground, "http_get"),
      name: "[Demo] HTTP GET com Playgrounds.Http",
      description: "GET externo com SSRF protection e timeout de 3s.",
      category: "Blackboex",
      code: """
      alias Blackboex.Playgrounds.Http

      # Limites: max 5 chamadas/execucao, timeout 3s, IPs privados bloqueados.
      url = "https://httpbin.org/get?demo=blackboex"

      case Http.get(url, headers: [{"accept", "application/json"}]) do
        {:ok, %{status: 200, body: body}} ->
          # body vem truncado em 64KB
          IO.puts("OK 200, \#{byte_size(body)} bytes")
          IO.puts(String.slice(body, 0, 200) <> "...")

        {:ok, %{status: status}} ->
          IO.puts("HTTP \#{status} — nao 2xx")

        {:error, reason} ->
          IO.puts("Erro: \#{inspect(reason)}")
      end
      """
    }
  end

  defp http_post_json do
    %{
      kind: :playground,
      id: "http_post_json",
      sample_uuid: Id.uuid(:playground, "http_post_json"),
      name: "[Demo] HTTP POST JSON",
      description: "POST com body JSON e parsing da resposta.",
      category: "Blackboex",
      code: """
      alias Blackboex.Playgrounds.Http

      payload = Jason.encode!(%{nome: "Ana", idade: 30, ativo: true})

      headers = [
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ]

      case Http.post("https://httpbin.org/post", payload, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          # httpbin.org devolve o que enviamos em "json"
          case Jason.decode(body) do
            {:ok, %{"json" => echo}} -> IO.inspect(echo, label: "echo do servidor")
            {:ok, decoded} -> IO.inspect(decoded, label: "resposta")
            {:error, _} -> IO.puts("body nao era JSON valido")
          end

        {:ok, %{status: status}} ->
          IO.puts("Status inesperado: \#{status}")

        {:error, reason} ->
          IO.puts("Falha: \#{inspect(reason)}")
      end
      """
    }
  end

  defp jason_parsing do
    %{
      kind: :playground,
      id: "jason_parsing",
      sample_uuid: Id.uuid(:playground, "jason_parsing"),
      name: "[Demo] Jason - Encode e Decode",
      description: "Serializar/desserializar JSON com Jason.",
      category: "Dados",
      code: """
      # Encode: map -> string JSON
      pedido = %{
        id: "ord_123",
        cliente: %{nome: "Maria", email: "maria@example.com"},
        itens: [
          %{sku: "SKU-1", qty: 2, preco: 19.90},
          %{sku: "SKU-2", qty: 1, preco: 49.00}
        ]
      }

      json = Jason.encode!(pedido, pretty: true)
      IO.puts(json)

      # Decode: string JSON -> map (chaves string por padrao)
      texto = ~s({"name":"Joao","tags":["a","b"],"active":true})

      case Jason.decode(texto) do
        {:ok, parsed} ->
          IO.inspect(parsed, label: "parsed (chaves string)")
          IO.puts("Tags: \#{Enum.join(parsed["tags"], ", ")}")

        {:error, %Jason.DecodeError{} = err} ->
          IO.puts("JSON invalido: \#{Exception.message(err)}")
      end
      """
    }
  end

  defp error_handling do
    %{
      kind: :playground,
      id: "error_handling",
      sample_uuid: Id.uuid(:playground, "error_handling"),
      name: "[Demo] Tratamento de Erros",
      description: "try/rescue, pattern em {:error, _} e raise.",
      category: "Elixir",
      code: """
      # Estilo idiomatico: retornar {:ok, _} | {:error, motivo}
      seguro = fn ->
        case Integer.parse("nao-eh-numero") do
          {n, ""} -> {:ok, n}
          :error -> {:error, :nao_eh_inteiro}
          _ -> {:error, :tem_lixo}
        end
      end

      IO.inspect(seguro.(), label: "resultado seguro")

      # Quando algo MUITO excepcional acontece, raise pode ser apropriado
      arriscado = fn entrada ->
        if entrada == nil do
          raise ArgumentError, "entrada nao pode ser nil"
        else
          String.upcase(entrada)
        end
      end

      try do
        arriscado.(nil)
      rescue
        e in ArgumentError ->
          IO.puts("Capturei: \#{Exception.message(e)}")
      end

      # Estilo pipeline: with + retornos taggeados eh quase sempre melhor
      # que try/rescue para fluxo de negocio normal.
      """
    }
  end

  defp base64_encoding do
    %{
      kind: :playground,
      id: "base64_encoding",
      sample_uuid: Id.uuid(:playground, "base64_encoding"),
      name: "[Demo] Base64 e URI Encoding",
      description: "Codificações comuns para tokens, query strings e mais.",
      category: "Dados",
      code: """
      # Base64 padrao
      texto = "blackboex secret"
      codificado = Base.encode64(texto)
      IO.puts("encoded: \#{codificado}")

      decodificado = Base.decode64!(codificado)
      IO.puts("decoded: \#{decodificado}")

      # URL-safe (sem + / =) — ideal para query string e cookies
      urlsafe = Base.url_encode64("hello world?", padding: false)
      IO.puts("url-safe: \#{urlsafe}")

      # URI.encode_query para query strings
      params = %{q: "ola mundo", page: 2, lang: "pt-BR"}
      query = URI.encode_query(params)
      IO.puts("query: \#{query}")

      # Decode pra map
      decoded = URI.decode_query(query)
      IO.inspect(decoded, label: "query decoded")
      """
    }
  end

  defp atom_safety do
    %{
      kind: :playground,
      id: "atom_safety",
      sample_uuid: Id.uuid(:playground, "atom_safety"),
      name: "[Demo] Atoms - Seguranca e Boas Praticas",
      description: "Por que NUNCA usar String.to_atom com input externo.",
      category: "Elixir",
      code: """
      # Atoms NAO sao garbage-collected. Cada novo atom consome memoria
      # permanente. Limite global eh ~1M (pode derrubar a VM se atingido).

      # SEGURO: atom literal no codigo
      status = :active
      IO.puts("status: \#{status}")

      # SEGURO: to_existing_atom — falha se nao existe, evita criar novo
      try do
        existente = String.to_existing_atom("active")
        IO.puts("encontrado: \#{existente}")
      rescue
        ArgumentError -> IO.puts("atom nao existe — recusado")
      end

      # PADRAO RECOMENDADO: lookup em map estatico
      mapeamento = %{
        "active" => :active,
        "paused" => :paused,
        "stopped" => :stopped
      }

      converter = fn entrada ->
        case Map.fetch(mapeamento, entrada) do
          {:ok, atom} -> {:ok, atom}
          :error -> {:error, :status_invalido}
        end
      end

      IO.inspect(converter.("active"), label: "active")
      IO.inspect(converter.("malicious-string-to-blow-atom-table"), label: "lixo")
      """
    }
  end
end
