ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Blackboex.Repo, :manual)

# Suppress Postgrex disconnect noise from LiveView tests.
# When the Ecto sandbox owner exits before in-flight async queries complete,
# Postgrex.Protocol logs an :error disconnect. This is not a real error —
# it's an expected race between test cleanup and Task.async DB operations.
:logger.add_handler_filter(:default, :suppress_postgrex_disconnect, {
  fn
    %{msg: {:string, msg}}, _extra ->
      if IO.iodata_to_binary(msg) =~ ~r/Postgrex\.Protocol.*disconnected/ do
        :stop
      else
        :ignore
      end

    %{msg: {:report, %{label: {Postgrex.Protocol, :disconnected}}}}, _extra ->
      :stop

    _event, _extra ->
      :ignore
  end,
  %{}
})
