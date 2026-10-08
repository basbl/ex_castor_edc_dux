defmodule CastorEDC.Dux.MixProject do
  use Mix.Project

  @version "0.1.0-dev"
  @source_url "https://github.com/basbl/ex_castor_edc_dux"

  def project do
    [
      app: :ex_castor_edc_dux,
      version: @version,
      elixir: "~> 1.20",
      description: "Castor EDC study data as Dux dataframes, backed by DuckDB.",
      start_permanent: Mix.env() == :prod,
      package: package(),
      deps: deps()
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

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:styler, "~> 1.12", only: [:dev, :test], runtime: false},
      {:credo, "~> 1.7.19", only: [:dev, :test], runtime: false}
    ]
  end
end
