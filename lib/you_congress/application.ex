defmodule YouCongress.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    Appsignal.Phoenix.LiveView.attach()
    Appsignal.Logger.Handler.add("phoenix")
    topologies = Application.get_env(:libcluster, :topologies) || []

    children = [
      # Start the Telemetry supervisor
      YouCongressWeb.Telemetry,
      # Start the Swoosh supervisor
      # Start the Swoosh supervisor
      {Finch,
       name: Swoosh.Finch,
       pools: %{
         :default => [
           conn_opts: [
             transport_opts: [
               cacertfile: CAStore.file_path()
             ]
           ]
         ]
       }},
      # Start the Ecto repository
      YouCongress.Repo,
      # Start the PubSub system
      {Phoenix.PubSub, name: YouCongress.PubSub},
      # Start the Endpoint (http/https)
      YouCongressWeb.Endpoint,
      # Oban
      {Oban, Application.fetch_env!(:you_congress, Oban)},
      # MCP Server
      Anubis.Server.Registry,
      {YouCongressWeb.MCPServer, transport: {:streamable_http, port: 8080}},
      # Setup for clustering
      {Cluster.Supervisor, [topologies, [name: YouCongress.ClusterSupervisor]]}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: YouCongress.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    YouCongressWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
