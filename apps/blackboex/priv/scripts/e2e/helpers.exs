defmodule E2E.Helpers do
  @base_url "http://localhost:4000"

  # ── Colours ──────────────────────────────────────────────────

  def green(text), do: IO.ANSI.green() <> text <> IO.ANSI.reset()
  def red(text), do: IO.ANSI.red() <> text <> IO.ANSI.reset()
  def cyan(text), do: IO.ANSI.cyan() <> text <> IO.ANSI.reset()
  def yellow(text), do: IO.ANSI.yellow() <> text <> IO.ANSI.reset()
  def bold(text), do: IO.ANSI.bright() <> text <> IO.ANSI.reset()

  # Start a dedicated high-concurrency Finch pool for stress testing.
  # Call once at script startup before any stress tests run.
  def start_stress_pool do
    case Finch.start_link(
           name: E2E.StressFinch,
           pools: %{
             "http://localhost:4000" => [size: 500, count: 2]
           }
         ) do
      {:ok, _} -> :ok
      {:error, {:already_started, _}} -> :ok
    end
  end

  def webhook_post(token, body, opts \\ []) do
    finch = Keyword.get(opts, :finch, nil)

    req_opts =
      [
        json: body,
        receive_timeout: 60_000,
        retry: false
      ]
      |> then(fn o -> if finch, do: Keyword.put(o, :finch, finch), else: o end)

    Req.post("#{@base_url}/webhook/#{token}", req_opts)
  end

  def run_test(name, fun) do
    case fun.() do
      :ok ->
        IO.puts(green("  ✓ #{name}"))
        {:pass, name}

      {:error, reason} ->
        IO.puts(red("  ✗ #{name}: #{reason}"))
        {:fail, name, reason}
    end
  rescue
    e ->
      reason = Exception.message(e)
      IO.puts(red("  ✗ #{name}: #{reason}"))
      {:fail, name, reason}
  end

  def assert_status!(resp, expected) do
    if resp.status != expected do
      raise "Expected HTTP #{expected}, got #{resp.status}: #{inspect(resp.body)}"
    end
  end

  def assert_eq!(actual, expected, label) do
    if actual != expected do
      raise "#{label}: expected #{inspect(expected)}, got #{inspect(actual)}"
    end
  end

  def assert_contains!(string, substring, label) when is_binary(string) do
    unless String.contains?(string, substring) do
      raise "#{label}: expected to contain #{inspect(substring)}, got #{inspect(string)}"
    end
  end

  def assert_contains!(other, _substring, label) do
    raise "#{label}: expected a string, got #{inspect(other)}"
  end

  def assert_present!(nil, label), do: raise("#{label}: expected non-nil value")
  def assert_present!(_, _label), do: :ok

  def assert_gte!(actual, min, _label) when is_number(actual) and actual >= min, do: :ok

  def assert_gte!(actual, min, label) do
    raise "#{label}: expected >= #{min}, got #{inspect(actual)}"
  end

  def report(results) do
    passed = Enum.count(results, &match?({:pass, _}, &1))
    failed = Enum.count(results, &match?({:fail, _, _}, &1))
    total = length(results)

    IO.puts(bold("\n══════════════════════════════════════════════"))

    if failed == 0 do
      IO.puts(green("  All #{total} tests passed ✓"))
    else
      IO.puts(yellow("  #{passed}/#{total} passed, #{failed} failed"))

      for {:fail, name, reason} <- results do
        IO.puts(red("    ✗ #{name}: #{reason}"))
      end
    end

    IO.puts(bold("══════════════════════════════════════════════\n"))

    if failed > 0, do: System.halt(1)
  end

  def create_and_activate_template(template_id, name_prefix, user, org) do
    ts = System.system_time(:second)
    name = "#{name_prefix} #{ts}"

    {:ok, flow} =
      Blackboex.Flows.create_flow_from_template(
        %{name: name, organization_id: org.id, project_id: Blackboex.Projects.get_default_project(org.id).id, user_id: user.id},
        template_id
      )

    {:ok, flow} = Blackboex.Flows.activate_flow(flow)
    IO.puts("  Created+activated: #{flow.name} (token: #{flow.webhook_token})")
    flow
  end
end
