defmodule Blackboex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Blackboex.Telemetry.Events

  @impl true
  @spec prep_stop(term()) :: term()
  def prep_stop(state) do
    Blackboex.Apis.Registry.shutdown()
    state
  end

  @impl true
  def start(_type, _args) do
    attach_telemetry_handlers()

    children = [
      # Vault MUST start before Repo — Cloak.Ecto field types call the vault
      # on load/save, so any schema read before the vault is up would crash.
      Blackboex.Vault,
      Blackboex.Repo,
      {Oban, Application.fetch_env!(:blackboex, Oban)},
      {DNSCluster, query: Application.get_env(:blackboex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Blackboex.PubSub},
      {Task.Supervisor, name: Blackboex.TaskSupervisor},
      {Task.Supervisor, name: Blackboex.SandboxTaskSupervisor},
      {Task.Supervisor, name: Blackboex.LoggingSupervisor, max_children: 1000},
      Blackboex.Apis.Registry,
      Blackboex.LLM.CircuitBreaker,
      {Registry, keys: :unique, name: Blackboex.Agent.SessionRegistry},
      {DynamicSupervisor, name: Blackboex.Agent.SessionSupervisor, strategy: :one_for_one},
      {Registry, keys: :unique, name: Blackboex.PlaygroundAgent.SessionRegistry},
      {DynamicSupervisor,
       name: Blackboex.PlaygroundAgent.SessionSupervisor, strategy: :one_for_one},
      {Registry, keys: :unique, name: Blackboex.PageAgent.SessionRegistry},
      {DynamicSupervisor,
       name: Blackboex.PageAgent.SessionSupervisor, strategy: :one_for_one, max_children: 100},
      {Registry, keys: :unique, name: Blackboex.FlowAgent.SessionRegistry},
      {DynamicSupervisor,
       name: Blackboex.FlowAgent.SessionSupervisor, strategy: :one_for_one, max_children: 100}
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Blackboex.Supervisor)
  end

  defp attach_telemetry_handlers do
    :telemetry.attach(
      "blackboex-req-llm-token-usage",
      [:req_llm, :token_usage],
      &__MODULE__.handle_req_llm_token_usage/4,
      %{}
    )

    :telemetry.attach(
      "blackboex-ecto-pool-saturation",
      [:blackboex, :repo, :query, :stop],
      &__MODULE__.handle_ecto_query/4,
      %{}
    )
  end

  @doc false
  @spec handle_req_llm_token_usage([atom()], map(), map(), map()) :: :ok
  def handle_req_llm_token_usage(_event, measurements, metadata, _config) do
    Events.emit_llm_call(%{
      duration_ms: Map.get(measurements, :duration_ms, 0),
      input_tokens: Map.get(measurements, :input_tokens, 0),
      output_tokens: Map.get(measurements, :output_tokens, 0),
      provider: Map.get(metadata, :provider, "unknown"),
      model: Map.get(metadata, :model, "unknown")
    })
  end

  @pool_saturation_threshold_ms 50

  @doc false
  @spec handle_ecto_query([atom()], map(), map(), map()) :: :ok
  def handle_ecto_query(_event, measurements, _metadata, _config) do
    queue_time_ms =
      Map.get(measurements, :queue_time, 0) |> System.convert_time_unit(:native, :millisecond)

    if queue_time_ms > @pool_saturation_threshold_ms do
      Events.emit_pool_saturation(%{queue_time_ms: queue_time_ms})
    end

    :ok
  end
end
