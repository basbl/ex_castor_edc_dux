defmodule CastorEDC.Dux.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/basbl/ex_castor_edc_dux"

  # Decimal 2.x, which adbc (under Dux) requires, has an advisory fixed only
  # in Decimal 3: unbounded exponents in Decimal.new. This package never
  # builds decimals from what the API sends; the list goes when adbc moves
  # to Decimal 3.
  @ignored_advisories ~w(GHSA-rhv4-8758-jx7v)

  def project do
    [
      app: :ex_castor_edc_dux,
      version: @version,
      elixir: "~> 1.20",
      elixirc_paths: elixirc_paths(Mix.env()),
      description: "Castor EDC study data as Dux dataframes, backed by DuckDB.",
      start_permanent: Mix.env() == :prod,
      test_coverage: [tool: ExCoveralls],
      dialyzer: [
        plt_local_path: "priv/plts",
        plt_core_path: "priv/plts",
        ignore_warnings: ".dialyzer_ignore.exs"
      ],
      hex: [ignore_advisories: @ignored_advisories],
      aliases: aliases(),
      docs: docs(),
      package: package(),
      deps: deps()
    ]
  end

  def cli do
    [
      preferred_envs: [
        precommit: :test,
        quality: :dev,
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test
      ]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp package do
    [
      files: ~w(lib .formatter.exs mix.exs README.md CHANGELOG.md LICENSE.md),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "CastorEDC.Dux",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_env), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      castor_edc(),
      {:dux, "~> 0.3.0"},
      {:excoveralls, "~> 0.18.5", only: :test},
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4.8", only: [:dev, :test], runtime: false},
      {:mix_audit, "~> 2.1.5", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.40.4", only: :dev, runtime: false}
    ]
  end

  # CASTOR_EDC_PATH points at a checkout of ex_castor_edc, to develop both
  # together; without it, the package builds on the released core.
  defp castor_edc do
    case System.get_env("CASTOR_EDC_PATH") do
      blank when blank in [nil, ""] -> {:ex_castor_edc, "~> 1.0.0-rc.1"}
      path -> {:ex_castor_edc, path: path}
    end
  end

  defp aliases do
    [
      "deps.audit": ["deps.audit --ignore-advisory-ids #{Enum.join(@ignored_advisories, ",")}"],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "credo --strict", "coveralls"],
      quality: [
        # hex.audit has to run first: once another task has loaded the
        # project's code paths, Mix no longer finds tasks from the Hex archive
        "hex.audit",
        "format --check-formatted",
        "credo --strict",
        "dialyzer",
        "deps.audit",
        "docs --warnings-as-errors"
      ]
    ]
  end
end
