defmodule Blackboex.Samples.Playground do
  @moduledoc """
  Playground samples in the platform-wide sample catalogue.

  Each example is a single-cell Elixir snippet that respects the
  `Blackboex.Playgrounds.Executor` sandbox: it uses only allowlisted modules,
  captures output through `IO.puts`/`IO.inspect`, and respects time, heap and
  HTTP limits.
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
      name: "[Demo] Enum - Basic Transformations",
      description: "Map, filter and reduce examples with Enum.",
      category: "Elixir",
      code: """
      numbers = [1, 2, 3, 4, 5]

      doubled = Enum.map(numbers, fn x -> x * 2 end)
      even = Enum.filter(numbers, fn x -> rem(x, 2) == 0 end)
      sum = Enum.reduce(numbers, 0, fn x, acc -> x + acc end)

      IO.puts("Doubled: \#{inspect(doubled)}")
      IO.puts("Even: \#{inspect(even)}")
      IO.puts("Sum: \#{sum}")
      """
    }
  end

  defp call_echo_flow(echo_flow_uuid) do
    %{
      kind: :playground,
      id: "call_echo_flow",
      sample_uuid: Id.uuid(:playground, "call_echo_flow"),
      flow_sample_uuid: echo_flow_uuid,
      name: "[Demo] API - Calling a Project Flow",
      description: "Calls the managed Echo Transform flow from playground code.",
      category: "Blackboex",
      code: """
      alias Blackboex.Playgrounds.Api

      token = "{{flow:#{echo_flow_uuid}:webhook_token}}"

      case Api.call_flow(token, %{"message" => "Hello from Playground!"}) do
        {:ok, response} -> IO.inspect(response, label: "Response")
        {:error, reason} -> IO.puts("Error: \#{reason}")
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
      description: "Chaining transformations with the pipe operator.",
      category: "Elixir",
      code: """
      # Without pipe: reads from inside out, harder to follow.
      without_pipe = Enum.sum(Enum.map(Enum.filter([1, 2, 3, 4, 5], &(&1 > 2)), &(&1 * 10)))
      IO.puts("Without pipe: \#{without_pipe}")

      # With pipe: linear reading, from raw data to result.
      with_pipe =
        [1, 2, 3, 4, 5]
        |> Enum.filter(&(&1 > 2))
        |> Enum.map(&(&1 * 10))
        |> Enum.sum()

      IO.puts("With pipe: \#{with_pipe}")

      # Idiomatic: each step is a clear transformation.
      """
    }
  end

  defp pattern_matching do
    %{
      kind: :playground,
      id: "pattern_matching",
      sample_uuid: Id.uuid(:playground, "pattern_matching"),
      name: "[Demo] Pattern Matching with case",
      description: "Pattern matching in tuples, maps and lists.",
      category: "Elixir",
      code: """
      # Common Elixir tuple match: {:ok, value} | {:error, reason}
      result = {:ok, %{user_id: 42, role: :admin}}

      case result do
        {:ok, %{role: :admin} = user} ->
          IO.puts("Admin id=\#{user.user_id}")

        {:ok, %{role: role}} ->
          IO.puts("User with role \#{role}")

        {:error, reason} ->
          IO.puts("Failed: \#{reason}")
      end

      # List pattern: head | tail
      [first | rest] = [10, 20, 30]
      IO.puts("First=\#{first}, rest=\#{inspect(rest)}")

      # Pin operator (^) matches against an existing variable value.
      expected = 5
      case 5 do
        ^expected -> IO.puts("matches expected")
        other -> IO.puts("different: \#{other}")
      end
      """
    }
  end

  defp with_clauses do
    %{
      kind: :playground,
      id: "with_clauses",
      sample_uuid: Id.uuid(:playground, "with_clauses"),
      name: "[Demo] with - Chaining ok/error",
      description: "Composing operations that return {:ok, _} | {:error, _}.",
      category: "Elixir",
      code: """
      # Helper functions simulating steps that can fail.
      parse_int = fn str ->
        case Integer.parse(str) do
          {n, ""} -> {:ok, n}
          _ -> {:error, "not an integer"}
        end
      end

      validate_positive = fn n ->
        if n > 0, do: {:ok, n}, else: {:error, "must be > 0"}
      end

      double = fn n -> {:ok, n * 2} end

      # `with` stops at the first {:error, _} and returns that error.
      # Without `with`, this would be three nested cases.
      process = fn input ->
        with {:ok, n} <- parse_int.(input),
             {:ok, n} <- validate_positive.(n),
             {:ok, doubled} <- double.(n) do
          {:ok, doubled}
        end
      end

      IO.inspect(process.("10"), label: "10")
      IO.inspect(process.("-5"), label: "-5")
      IO.inspect(process.("abc"), label: "abc")
      """
    }
  end

  defp comprehensions do
    %{
      kind: :playground,
      id: "comprehensions",
      sample_uuid: Id.uuid(:playground, "comprehensions"),
      name: "[Demo] Comprehensions with for",
      description: "Generators, filters and Cartesian products with for.",
      category: "Elixir",
      code: """
      # Simple comprehension: generate squares of even numbers.
      even_squares =
        for x <- 1..10, rem(x, 2) == 0, do: x * x

      IO.inspect(even_squares, label: "even squares")

      # Multiple generators = Cartesian product.
      multiplication_table =
        for a <- 1..3, b <- 1..3, do: {a, b, a * b}

      IO.inspect(multiplication_table, label: "multiplication table 1..3")

      # `:into` builds a map.
      by_index =
        for {item, idx} <- Enum.with_index(["a", "b", "c"]), into: %{}, do: {idx, item}

      IO.inspect(by_index, label: "by index")
      """
    }
  end

  defp map_keyword do
    %{
      kind: :playground,
      id: "map_keyword",
      sample_uuid: Id.uuid(:playground, "map_keyword"),
      name: "[Demo] Map vs Keyword List",
      description: "When to use maps and when to use keyword lists.",
      category: "Elixir",
      code: """
      # Map: unique keys, order not guaranteed, O(log n) access.
      user = %{name: "Ana", age: 30, role: :admin}
      IO.puts("Name: \#{user.name}")
      updated = %{user | age: 31}
      IO.inspect(updated, label: "updated map")

      # Keyword: list of {atom, value} tuples, preserves order,
      # allows duplicates, ideal for function options.
      opts = [timeout: 5_000, retries: 3, label: "primary"]
      IO.puts("Timeout: \#{Keyword.get(opts, :timeout)}")
      IO.puts("Retries: \#{Keyword.fetch!(opts, :retries)}")

      # Elixir style: options as the last function argument.
      get_opt = fn list, key, default -> Keyword.get(list, key, default) end
      IO.puts("Missing default: \#{get_opt.(opts, :missing, "default")}")
      """
    }
  end

  defp streams_lazy do
    %{
      kind: :playground,
      id: "streams_lazy",
      sample_uuid: Id.uuid(:playground, "streams_lazy"),
      name: "[Demo] Stream - Lazy Evaluation",
      description: "Lazy pipelines with Stream only finish when consumed.",
      category: "Elixir",
      code: """
      # Stream executes nothing until something consumes it.
      # Here we build a huge pipeline but stop at the first `take`.
      pipeline =
        1..1_000_000
        |> Stream.map(fn x ->
          # If this ran for every item, it would spend a lot of CPU.
          x * x
        end)
        |> Stream.filter(fn x -> rem(x, 7) == 0 end)
        |> Stream.take(5)

      # Consuming converts the stream into a list.
      result = Enum.to_list(pipeline)
      IO.inspect(result, label: "5 squares divisible by 7")

      # Comparison: the same work with Enum would create the whole intermediate list.
      # Stream is ideal for potentially infinite or large sources.
      """
    }
  end

  defp string_manipulation do
    %{
      kind: :playground,
      id: "string_manipulation",
      sample_uuid: Id.uuid(:playground, "string_manipulation"),
      name: "[Demo] String - Split, Replace, Capitalize",
      description: "Common UTF-8 string manipulation operations.",
      category: "Elixir",
      code: """
      phrase = "  Blackboex runs Elixir in the Playground  "

      normalized =
        phrase
        |> String.trim()
        |> String.downcase()
        |> String.replace(" ", "-")

      IO.puts("Slug: \#{normalized}")

      # Split + capitalize each word (title case).
      title =
        "hello world from programming"
        |> String.split(" ")
        |> Enum.map(&String.capitalize/1)
        |> Enum.join(" ")

      IO.puts("Title: \#{title}")

      # Elixir strings are UTF-8 binaries.
      IO.puts("Bytes: \#{byte_size("resume")}")
      IO.puts("Graphemes: \#{String.length("resume")}")
      """
    }
  end

  defp date_time_math do
    %{
      kind: :playground,
      id: "date_time_math",
      sample_uuid: Id.uuid(:playground, "date_time_math"),
      name: "[Demo] DateTime - Differences and Comparisons",
      description: "Date arithmetic and ISO 8601 formatting.",
      category: "Elixir",
      code: """
      now = DateTime.utc_now()
      IO.puts("UTC now: \#{DateTime.to_iso8601(now)}")

      one_hour_ago = DateTime.add(now, -3600, :second)
      IO.puts("One hour ago: \#{DateTime.to_iso8601(one_hour_ago)}")

      diff_seconds = DateTime.diff(now, one_hour_ago, :second)
      IO.puts("Difference: \#{diff_seconds}s")

      # Date for current day + 30.
      today = Date.utc_today()
      in_30_days = Date.add(today, 30)
      IO.puts("Today: \#{today}, in 30 days: \#{in_30_days}")

      # Comparisons return :lt | :eq | :gt.
      IO.puts("Comparing: \#{Date.compare(today, in_30_days)}")
      """
    }
  end

  defp regex_validation do
    %{
      kind: :playground,
      id: "regex_validation",
      sample_uuid: Id.uuid(:playground, "regex_validation"),
      name: "[Demo] Regex - Validate and Extract",
      description: "Match, named captures and replace with Regex.",
      category: "Elixir",
      code: """
      # Simple email validation.
      email_regex = ~r/^[\\w.+-]+@[\\w-]+\\.[\\w.-]+$/

      Enum.each(["ok@example.com", "missing-at", "a@b.co"], fn input ->
        if Regex.match?(email_regex, input) do
          IO.puts("OK: \#{input}")
        else
          IO.puts("FAIL: \#{input}")
        end
      end)

      # Named captures.
      log = "2026-05-04 12:30:45 [error] timeout"
      pattern = ~r/^(?<date>[\\d-]+) (?<time>[\\d:]+) \\[(?<level>\\w+)\\] (?<msg>.+)$/

      case Regex.named_captures(pattern, log) do
        nil -> IO.puts("no match")
        captures -> IO.inspect(captures, label: "structured log")
      end

      # Replace with capture.
      anonymized_text = Regex.replace(~r/(\\d{3})\\d{3}(\\d{3})/, "12345-678901", "\\\\1***\\\\2")
      IO.puts("anonymized: \#{anonymized_text}")
      """
    }
  end

  defp range_basics do
    %{
      kind: :playground,
      id: "range_basics",
      sample_uuid: Id.uuid(:playground, "range_basics"),
      name: "[Demo] Range - Efficient Sequences",
      description: "Range is a cheap Enumerable; no need to list everything.",
      category: "Elixir",
      code: """
      # Range does not materialize the list; it stays as {:range, first, last, step}.
      r = 1..1_000_000
      IO.puts("Type: \#{inspect(r.__struct__)}")
      IO.puts("First: \#{r.first}, last: \#{r.last}")

      # Enum operations work, but allocate when needed.
      sum = Enum.sum(1..100)
      IO.puts("Sum 1..100 = \#{sum}")

      # Range with a negative step.
      descending = 10..1//-2
      IO.inspect(Enum.to_list(descending), label: "10..1 with step -2")

      # Combine with Stream to stay lazy.
      first_even =
        1..1_000
        |> Stream.filter(&(rem(&1, 2) == 0))
        |> Enum.take(5)

      IO.inspect(first_even, label: "first 5 even numbers")
      """
    }
  end

  defp tuple_basics do
    %{
      kind: :playground,
      id: "tuple_basics",
      sample_uuid: Id.uuid(:playground, "tuple_basics"),
      name: "[Demo] Tuples - When to Use",
      description: "Tuples for fixed returns; maps for named data.",
      category: "Elixir",
      code: """
      # Tuple is ideal for fixed-arity returns: {:ok, value} | {:error, _}
      divide = fn
        _, 0 -> {:error, :division_by_zero}
        a, b -> {:ok, a / b}
      end

      IO.inspect(divide.(10, 2), label: "10/2")
      IO.inspect(divide.(10, 0), label: "10/0")

      # Index access (rare): elem/2.
      coord = {3.5, 7.2}
      IO.puts("x=\#{elem(coord, 0)}, y=\#{elem(coord, 1)}")

      # Updating a tuple creates a new tuple.
      updated = put_elem(coord, 0, 99.9)
      IO.inspect(updated, label: "updated coord")

      # For growing/named data, prefer maps.
      point_map = %{x: 3.5, y: 7.2, z: 0.0}
      IO.inspect(%{point_map | x: 99.9}, label: "point as map")
      """
    }
  end

  defp read_env_vars do
    %{
      kind: :playground,
      id: "read_env_vars",
      sample_uuid: Id.uuid(:playground, "read_env_vars"),
      name: "[Demo] Project Env Vars",
      description: "Reading variables configured in Project Settings.",
      category: "Blackboex",
      code: """
      # `env` is an automatic binding in the Playground.
      # Configure variables in Project Settings -> Env Vars.

      api_url = env["API_URL"]
      api_key = env["API_KEY"]

      cond do
        is_nil(api_url) ->
          IO.puts("API_URL is not configured; define it in Project Settings")

        is_nil(api_key) ->
          IO.puts("API_KEY is not configured; define it in Project Settings")

        true ->
          # Mask the key in logs to avoid leaking it.
          masked = String.slice(api_key, 0, 4) <> "****"
          IO.puts("Ready to call \#{api_url} with key \#{masked}")
      end

      # Map size is zero when nothing is configured.
      IO.puts("Total variables: \#{map_size(env)}")
      """
    }
  end

  defp http_get do
    %{
      kind: :playground,
      id: "http_get",
      sample_uuid: Id.uuid(:playground, "http_get"),
      name: "[Demo] HTTP GET with Playgrounds.Http",
      description: "External GET with SSRF protection and a 3s timeout.",
      category: "Blackboex",
      code: """
      alias Blackboex.Playgrounds.Http

      # Limits: max 5 calls per execution, 3s timeout, private IPs blocked.
      url = "https://httpbin.org/get?demo=blackboex"

      case Http.get(url, headers: [{"accept", "application/json"}]) do
        {:ok, %{status: 200, body: body}} ->
          # body is truncated at 64KB.
          IO.puts("OK 200, \#{byte_size(body)} bytes")
          IO.puts(String.slice(body, 0, 200) <> "...")

        {:ok, %{status: status}} ->
          IO.puts("HTTP \#{status}; not 2xx")

        {:error, reason} ->
          IO.puts("Error: \#{inspect(reason)}")
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
      description: "POST with JSON body and response parsing.",
      category: "Blackboex",
      code: """
      alias Blackboex.Playgrounds.Http

      payload = Jason.encode!(%{name: "Ana", age: 30, active: true})

      headers = [
        {"content-type", "application/json"},
        {"accept", "application/json"}
      ]

      case Http.post("https://httpbin.org/post", payload, headers: headers) do
        {:ok, %{status: 200, body: body}} ->
          # httpbin.org returns what we sent under "json".
          case Jason.decode(body) do
            {:ok, %{"json" => echo}} -> IO.inspect(echo, label: "server echo")
            {:ok, decoded} -> IO.inspect(decoded, label: "response")
            {:error, _} -> IO.puts("body was not valid JSON")
          end

        {:ok, %{status: status}} ->
          IO.puts("Unexpected status: \#{status}")

        {:error, reason} ->
          IO.puts("Failure: \#{inspect(reason)}")
      end
      """
    }
  end

  defp jason_parsing do
    %{
      kind: :playground,
      id: "jason_parsing",
      sample_uuid: Id.uuid(:playground, "jason_parsing"),
      name: "[Demo] Jason - Encode and Decode",
      description: "Serialize and deserialize JSON with Jason.",
      category: "Data",
      code: """
      # Encode: map -> string JSON
      order = %{
        id: "ord_123",
        customer: %{name: "Mary", email: "mary@example.com"},
        items: [
          %{sku: "SKU-1", qty: 2, price: 19.90},
          %{sku: "SKU-2", qty: 1, price: 49.00}
        ]
      }

      json = Jason.encode!(order, pretty: true)
      IO.puts(json)

      # Decode: JSON string -> map (string keys by default).
      text = ~s({"name":"John","tags":["a","b"],"active":true})

      case Jason.decode(text) do
        {:ok, parsed} ->
          IO.inspect(parsed, label: "parsed (string keys)")
          IO.puts("Tags: \#{Enum.join(parsed["tags"], ", ")}")

        {:error, %Jason.DecodeError{} = err} ->
          IO.puts("Invalid JSON: \#{Exception.message(err)}")
      end
      """
    }
  end

  defp error_handling do
    %{
      kind: :playground,
      id: "error_handling",
      sample_uuid: Id.uuid(:playground, "error_handling"),
      name: "[Demo] Error Handling",
      description: "try/rescue, {:error, _} patterns and raise.",
      category: "Elixir",
      code: """
      # Idiomatic style: return {:ok, _} | {:error, reason}
      safe = fn ->
        case Integer.parse("not-a-number") do
          {n, ""} -> {:ok, n}
          :error -> {:error, :not_an_integer}
          _ -> {:error, :has_trailing_garbage}
        end
      end

      IO.inspect(safe.(), label: "safe result")

      # When something truly exceptional happens, raise can be appropriate.
      risky = fn input ->
        if input == nil do
          raise ArgumentError, "input cannot be nil"
        else
          String.upcase(input)
        end
      end

      try do
        risky.(nil)
      rescue
        e in ArgumentError ->
          IO.puts("Caught: \#{Exception.message(e)}")
      end

      # Pipeline style: with + tagged returns is almost always better
      # than try/rescue for normal business flow.
      """
    }
  end

  defp base64_encoding do
    %{
      kind: :playground,
      id: "base64_encoding",
      sample_uuid: Id.uuid(:playground, "base64_encoding"),
      name: "[Demo] Base64 and URI Encoding",
      description: "Common encodings for tokens, query strings and more.",
      category: "Data",
      code: """
      # Standard Base64.
      text = "blackboex secret"
      encoded = Base.encode64(text)
      IO.puts("encoded: \#{encoded}")

      decoded = Base.decode64!(encoded)
      IO.puts("decoded: \#{decoded}")

      # URL-safe (without + / =), ideal for query strings and cookies.
      urlsafe = Base.url_encode64("hello world?", padding: false)
      IO.puts("url-safe: \#{urlsafe}")

      # URI.encode_query for query strings.
      params = %{q: "hello world", page: 2, lang: "en-US"}
      query = URI.encode_query(params)
      IO.puts("query: \#{query}")

      # Decode into a map.
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
      name: "[Demo] Atoms - Safety and Best Practices",
      description: "Why you should NEVER use String.to_atom with external input.",
      category: "Elixir",
      code: """
      # Atoms are NOT garbage-collected. Each new atom consumes permanent memory.
      # The global limit is around 1M and can bring the VM down if reached.

      # SAFE: literal atom in code.
      status = :active
      IO.puts("status: \#{status}")

      # SAFE: to_existing_atom fails if the atom does not exist and avoids creating a new one.
      try do
        existing = String.to_existing_atom("active")
        IO.puts("found: \#{existing}")
      rescue
        ArgumentError -> IO.puts("atom does not exist; rejected")
      end

      # RECOMMENDED PATTERN: lookup in a static map.
      mapping = %{
        "active" => :active,
        "paused" => :paused,
        "stopped" => :stopped
      }

      convert = fn input ->
        case Map.fetch(mapping, input) do
          {:ok, atom} -> {:ok, atom}
          :error -> {:error, :invalid_status}
        end
      end

      IO.inspect(convert.("active"), label: "active")
      IO.inspect(convert.("malicious-string-to-blow-atom-table"), label: "junk")
      """
    }
  end
end
