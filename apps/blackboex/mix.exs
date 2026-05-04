defmodule Blackboex.MixProject do
  use Mix.Project

  def project do
    [
      app: :blackboex,
      version: "0.1.0",
      description: "Domain application for Blackboex — business logic, schemas, and workers",
      licenses: ["MIT"],
      links: %{"GitHub" => "https://github.com/rodrigomarchi/blackboex"},
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      xref: [exclude: [ExRated]]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Blackboex.Application, []},
      extra_applications: [:logger, :runtime_tools, :ex_rated]
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
      {:bcrypt_elixir, "~> 3.0"},
      {:dns_cluster, "~> 0.2.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:jason, "~> 1.2"},
      {:swoosh, "~> 1.5"},
      {:let_me, "~> 1.2"},
      {:req_llm, "~> 1.7"},
      {:instructor_lite, "~> 1.2"},
      {:req, "~> 0.5"},
      {:plug, "~> 1.16"},
      {:ex_rated, "~> 2.1"},
      {:oban, "~> 2.20"},
      {:fun_with_flags, "~> 1.13"},
      {:ex_audit, "~> 0.10"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry_ecto, "~> 1.2"},
      {:logger_json, "~> 7.0"},
      {:open_api_spex, "~> 3.22"},
      {:ex_json_schema, "~> 0.11"},
      {:ymlr, "~> 5.1"},
      {:mox, "~> 1.0", only: :test},
      {:langchain, "~> 0.6.2"},
      {:reactor, "~> 1.0"},
      {:nanoid, "~> 2.1"},
      {:cloak_ecto, "~> 1.3"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate", "run #{__DIR__}/priv/repo/seeds.exs"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      test: [
        "ecto.drop --quiet --force --force-drop",
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test"
      ]
    ]
  end
end
