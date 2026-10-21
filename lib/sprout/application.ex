defmodule Sprout.Application do
  # See https://elixir.hexdocs.pm/Application.html
  # for more information on OTP Applications
  @moduledoc """
  Supervises persistence, PubSub, the HTTP endpoint, and optional adapter-driven telemetry.

  `:sensor_feed` configures a per-node polling adapter; it is disabled in tests
  and production. The one-for-one strategy restarts failed children independently.
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      SproutWeb.Telemetry,
      Sprout.Repo,
      {DNSCluster, query: Application.get_env(:sprout, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Sprout.PubSub},
      {Task.Supervisor, name: Sprout.Monitoring.Tasks},
      # Start a worker by calling: Sprout.Worker.start_link(arg)
      # {Sprout.Worker, arg},
      # Start to serve requests, typically the last entry
      SproutWeb.Endpoint
    ]

    # See https://elixir.hexdocs.pm/Supervisor.html
    # for other strategies and supported options
    children =
      case Application.get_env(:sprout, :sensor_feed) do
        nil -> children
        options -> children ++ [{Sprout.Monitoring.Feed, options}]
      end

    opts = [strategy: :one_for_one, name: Sprout.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    SproutWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
