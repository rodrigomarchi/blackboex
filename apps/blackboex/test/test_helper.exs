ExUnit.configure(exclude: [slow: true])
ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Blackboex.Repo, :manual)

# Suppress noise from processes that outlive the Ecto sandbox owner.
# When the sandbox owner (test process) exits, GenServers and Postgrex
# connections that were mid-operation log errors. These are not real bugs —
# they're an expected race between test cleanup and async DB operations.
:logger.add_handler_filter(:default, :suppress_sandbox_noise, {
  fn
    %{msg: {:string, msg}}, _extra ->
      bin = IO.iodata_to_binary(msg)

      if bin =~ ~r/Postgrex\.Protocol.*disconnected/ or
           bin =~ ~r/GenServer.*SessionRegistry/ do
        :stop
      else
        :ignore
      end

    %{msg: {:report, report}}, _extra when is_map(report) ->
      label = Map.get(report, :label, nil)

      if label == {:gen_server, :terminate} do
        case Map.get(report, :name, nil) do
          {Blackboex.Agent.SessionRegistry, _} -> :stop
          _ -> :ignore
        end
      else
        :ignore
      end

    %{msg: {fmt, args}}, _extra when is_list(args) ->
      bin = :io_lib.format(fmt, args) |> IO.iodata_to_binary()

      if bin =~ ~r/GenServer.*SessionRegistry/ do
        :stop
      else
        :ignore
      end

    _event, _extra ->
      :ignore
  end,
  %{}
})
