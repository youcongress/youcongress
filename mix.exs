defmodule YouCongress.MixProject do
  use Mix.Project

  def project do
    [
      app: :you_congress,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:yecc, :leex] ++ Mix.compilers()
    ]
  end

  def cli do
    [preferred_envs: [check: :test, precommit: :test, ci: :test]]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {YouCongress.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:bcrypt_elixir, "~> 4.0"},
      {:phoenix, "~> 1.8.17"},
      {:phoenix_ecto, "~> 4.7"},
      {:ecto_sql, "~> 3.14"},
      {:postgrex, "~> 0.23"},
      {:phoenix_html, "~> 4.4"},
      {:phoenix_live_reload, "~> 1.7", only: :dev},
      {:phoenix_live_view, "~> 1.2.15"},
      {:flop, "~> 0.29.2"},
      {:nimble_csv, "~> 1.2"},
      {:floki, ">= 0.36.3", only: :test},
      {:phoenix_live_dashboard, "~> 0.9.1"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.5", runtime: Mix.env() == :dev},
      {:swoosh, "~> 1.30"},
      {:finch, "~> 0.25"},
      {:telemetry_metrics, "~> 1.2"},
      {:telemetry_poller, "~> 1.3"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.15"},
      {:faker, "~> 0.19", only: [:test, :dev]},
      {:mock, "~> 0.3.8", only: :test},
      {:meck, "~> 1.2", only: :test, override: true},
      {:pgvector, "~> 0.4"},
      {:oban, "~> 2.24"},
      {:oban_web, "~> 2.13"},
      {:igniter, "~> 0.5", only: [:dev]},
      {:credo, "~> 1.7.5", only: [:dev, :test], runtime: false},
      {:sobelow, "~> 0.19", only: [:dev, :test], runtime: false},
      {:slugify, "~> 1.3.1"},
      {:appsignal, "~> 2.18"},
      {:appsignal_phoenix, "~> 2.8.2"},
      {:libcluster, "~> 3.6"},
      {:ancestry, "~> 0.1.3"},
      {:lazy_html, ">= 0.1.8", only: :test},
      {:tidewave, "~> 0.9", only: :dev},
      {:castore, "~> 1.0"},
      {:req, "~> 0.7.4"},
      {:redix, "~> 1.10"},
      {:anubis_mcp,
       github: "hectorperez/anubis-mcp", ref: "da3fb5e665f0677a5a5376bd84466117b88c5dc2"},
      {:dotenvy, "~> 1.2", only: [:dev, :test]}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup", "assets.setup", "assets.build"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["tailwind default", "esbuild default"],
      "assets.deploy": ["tailwind default --minify", "esbuild default --minify", "phx.digest"],
      # Fast local feedback; external dependency audits belong in precommit.
      check: [
        "format",
        "compile --warnings-as-errors",
        "assets.build",
        "credo --strict",
        "test",
        "sobelow --config"
      ],
      # Hex 2.5.1+ checks retirements and advisories before application tasks run.
      precommit: [
        "hex.audit",
        "format --check-formatted",
        "compile --warnings-as-errors",
        "assets.build",
        "credo --strict",
        "test --cover",
        "sobelow --config"
      ],
      ci: ["precommit"]
    ]
  end
end
