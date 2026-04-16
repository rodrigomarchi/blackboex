defmodule BlackboexWeb.MixProject do
  use Mix.Project

  def project do
    [
      app: :blackboex_web,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader],
      test_coverage: [
        ignore_modules: [
          # Backpex admin panels — library-generated code, tested by Backpex itself
          ~r/BlackboexWeb\.Admin\./,
          # SaladUI wrapper components with no custom logic
          ~r/BlackboexWeb\.Components\.(Input|Label|Separator|Sheet|Sidebar|Skeleton|Spinner|Table|Tabs|Tooltip|DropdownMenu|Card|FormField|Avatar)$/,
          BlackboexWeb.Logo,
          # Infrastructure modules — Prometheus metrics, telemetry, error templates
          ~r/BlackboexWeb\.PromEx/,
          BlackboexWeb.Telemetry,
          BlackboexWeb.ErrorHTML,
          BlackboexWeb.PageHTML,
          BlackboexWeb.PublicApiHTML,
          BlackboexWeb.Application,
          BlackboexWeb.BeamMonitor
        ]
      ]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {BlackboexWeb.Application, []},
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
      {:earmark, "~> 1.4"},
      {:html_sanitize_ex, "~> 1.5"},
      {:phoenix, "~> 1.8.3"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.4", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:opentelemetry, "~> 1.7"},
      {:opentelemetry_api, "~> 1.5"},
      {:opentelemetry_exporter, "~> 1.10"},
      {:opentelemetry_semantic_conventions, "~> 1.27"},
      {:opentelemetry_phoenix, "~> 2.0"},
      {:opentelemetry_bandit, "~> 0.3"},
      {:opentelemetry_logger_metadata, "~> 0.2"},
      {:prom_ex, "~> 1.11"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:blackboex, in_umbrella: true},
      {:makeup, "~> 1.2"},
      {:makeup_elixir, "~> 1.0"},
      {:mdex, "~> 0.11"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:swoosh, "~> 1.5"},
      {:salad_ui, "~> 0.14"},
      {:hammer, "~> 7.2"},
      {:open_api_spex, "~> 3.22"},
      {:backpex, "~> 0.17"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      test: ["ecto.create --quiet", "ecto.migrate --quiet", "test"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": [
        "compile",
        "tailwind blackboex_web",
        "tailwind blackboex_admin",
        "esbuild blackboex_web",
        "esbuild blackboex_admin"
      ],
      "assets.deploy": [
        "tailwind blackboex_web --minify",
        "tailwind blackboex_admin --minify",
        "esbuild blackboex_web --minify",
        "esbuild blackboex_admin --minify",
        "phx.digest"
      ]
    ]
  end
end
