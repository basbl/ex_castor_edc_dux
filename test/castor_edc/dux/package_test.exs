defmodule CastorEDC.Dux.PackageTest do
  use ExUnit.Case, async: true

  # The docs can't read the version from mix.exs, so this keeps the
  # requirement they tell users to install with in step with it: the
  # version itself for a pre-release (which "~> 0.1.0" doesn't match), the
  # minor version before 1.0, as minor versions may break, and the major
  # version after.
  test "the docs install the version mix.exs gives" do
    version = Version.parse!(Mix.Project.config()[:version])

    expected =
      cond do
        version.pre != [] -> "~> #{version}"
        version.major == 0 -> "~> 0.#{version.minor}.0"
        true -> "~> #{version.major}.#{version.minor}"
      end

    assert Version.match?(version, expected, allow_pre: true)

    for doc <- ["README.md", "notebook/analysis.livemd", "notebook/charts.livemd"] do
      requirements = Regex.scan(~r/\{:ex_castor_edc_dux, "([^"]+)"\}/, File.read!(doc), capture: :all_but_first)

      assert requirements != [], "#{doc} doesn't say how to install the package"

      for [requirement] <- requirements do
        assert requirement == expected, "#{doc} installs #{inspect(requirement)} instead of #{inspect(expected)}"
      end
    end
  end
end
