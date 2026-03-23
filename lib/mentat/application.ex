defmodule Mentat.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MentatWeb.Telemetry,
      Mentat.Repo,
      {DNSCluster, query: Application.get_env(:mentat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mentat.PubSub},
      # Start a worker by calling: Mentat.Worker.start_link(arg)
      # {Mentat.Worker, arg},
      # Start to serve requests, typically the last entry
      MentatWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mentat.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MentatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
