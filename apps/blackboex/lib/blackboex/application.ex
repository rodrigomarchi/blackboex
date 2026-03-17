defmodule Blackboex.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Blackboex.Repo,
      {DNSCluster, query: Application.get_env(:blackboex, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Blackboex.PubSub},
      {Task.Supervisor, name: Blackboex.SandboxTaskSupervisor},
      Blackboex.Apis.Registry
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Blackboex.Supervisor)
  end
end
