defmodule Mosaic.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MosaicWeb.Telemetry,
      Mosaic.Repo,
      {DNSCluster, query: Application.get_env(:mosaic, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mosaic.PubSub},
      # Start a worker by calling: Mosaic.Worker.start_link(arg)
      # {Mosaic.Worker, arg},
      # Start to serve requests, typically the last entry
      MosaicWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mosaic.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MosaicWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
