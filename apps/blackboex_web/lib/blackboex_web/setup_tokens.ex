defmodule BlackboexWeb.SetupTokens do
  @moduledoc """
  One-time, short-TTL tokens that bridge `BlackboexWeb.SetupLive`
  (no session access) to `BlackboexWeb.SetupController.finish/2`
  (full conn, can call `UserAuth.log_in_user/3`).

  Tokens are stored in a public ETS table keyed by token, with
  `{user_id, expires_at}` value. `consume/1` is a take-or-fail
  operation, so a token is single-use.

  TTL defaults to 60 seconds and is configurable via
  `Application.put_env(:blackboex_web, :setup_token_ttl_seconds, n)`.
  """
  use GenServer

  @table __MODULE__
  @default_ttl_seconds 60
  @cleanup_interval :timer.seconds(60)

  @spec start_link(any()) :: GenServer.on_start()
  def start_link(_opts), do: GenServer.start_link(__MODULE__, [], name: __MODULE__)

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :set, :public, read_concurrency: true])
    schedule_cleanup()
    {:ok, %{}}
  end

  @doc "Stores the user_id and returns a single-use opaque token."
  @spec issue(integer() | binary()) :: String.t()
  def issue(user_id) do
    token = :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
    :ets.insert(@table, {token, user_id, now() + ttl_seconds()})
    token
  end

  @doc "Consumes the token. Returns `{:ok, user_id}` or `:error`."
  @spec consume(String.t() | any()) :: {:ok, integer() | binary()} | :error
  def consume(token) when is_binary(token) do
    case :ets.take(@table, token) do
      [{^token, user_id, expires_at}] ->
        if expires_at >= now(), do: {:ok, user_id}, else: :error

      _ ->
        :error
    end
  end

  def consume(_), do: :error

  @impl true
  def handle_info(:cleanup, state) do
    cutoff = now()
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", cutoff}], [true]}])
    schedule_cleanup()
    {:noreply, state}
  end

  defp schedule_cleanup, do: Process.send_after(self(), :cleanup, @cleanup_interval)

  defp now, do: System.system_time(:second)

  defp ttl_seconds,
    do: Application.get_env(:blackboex_web, :setup_token_ttl_seconds, @default_ttl_seconds)
end
