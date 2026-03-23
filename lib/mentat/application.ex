defmodule Mentat.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MentatWeb.Telemetry,
      Mentat.Repo,
      {DNSCluster, query: Application.get_env(:mentat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mentat.PubSub},
      {Registry, keys: :unique, name: Mentat.NationRegistry},
      Mentat.World,
      Mentat.PersistenceWorker,
      {DynamicSupervisor, name: Mentat.NationSupervisor, strategy: :one_for_one},
      Mentat.SimulationState,
      MentatWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Mentat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MentatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
