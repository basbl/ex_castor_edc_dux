# CastorEDC.Dux

[![Package](https://img.shields.io/hexpm/v/ex_castor_edc_dux.svg)](https://hex.pm/packages/ex_castor_edc_dux) [![Documentation](http://img.shields.io/badge/hex.pm-docs-green.svg?style=flat)](https://hexdocs.pm/ex_castor_edc_dux) ![CI](https://github.com/basbl/ex_castor_edc_dux/actions/workflows/ci.yml/badge.svg)

Castor EDC study data as [Dux](https://hexdocs.pm/dux) dataframes, backed by DuckDB.

It builds on [ex_castor_edc](https://hexdocs.pm/ex_castor_edc).
Data streams from the API into Parquet files, so it never has to fit in memory, and every frame's column types come from the study's structure instead of being inferred from the data.

## Installation

```elixir
def deps do
  [
    {:ex_castor_edc_dux, "~> 0.2.0"}
  ]
end
```

## Usage

```elixir
client = CastorEDC.new(client_id: "...", client_secret: "...")

# A row per value: the study's, repeating data's and surveys' values alike.
{:ok, values} = CastorEDC.Dux.data_points(client, study_id, dir: "data")

# With the names of the chosen options, as the user saw them, next to their values.
{:ok, values} = CastorEDC.Dux.data_points(client, study_id, labels: true, dir: "data")

# A frame per study, repeating data and survey, with a column per variable.
{:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
  CastorEDC.Dux.data_points(client, study_id, format: :wide, dir: "data")

# The same frames over a batch export's files: a few requests however big the study.
{:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
  CastorEDC.Dux.participant_data(client, study_id, dir: "data")

# Or from an export already downloaded: the struct, or the path to its zip or directory.
{:ok, frames} = CastorEDC.Dux.participant_data(client, study_id, from: "exports/study.zip", dir: "data")

# A frame per domain, from the export grouped by the study's domains.
{:ok, %{"DM" => demographics}} = CastorEDC.Dux.domains(client, study_id, labels: true, dir: "data")

# The study's participants, fields, sites and options.
{:ok, participants} = CastorEDC.Dux.participants(client, study_id, dir: "data")
{:ok, fields} = CastorEDC.Dux.fields(client, study_id, dir: "data")
{:ok, sites} = CastorEDC.Dux.sites(client, study_id, dir: "data")
{:ok, options} = CastorEDC.Dux.option_groups(client, study_id, dir: "data")

# The survey packages sent, the repeating data instances made, and the queries raised.
{:ok, packages} = CastorEDC.Dux.survey_package_instances(client, study_id, dir: "data")
{:ok, instances} = CastorEDC.Dux.repeating_data_instances(client, study_id, dir: "data")
{:ok, queries} = CastorEDC.Dux.queries(client, study_id, dir: "data")

# Anything else the client returns, from a list, page or stream of its structs.
countries = client |> CastorEDC.Countries.list_countries!() |> CastorEDC.Dux.from_structs(dir: "data")
```

## Contributing

See [CONTRIBUTING.md](https://github.com/basbl/ex_castor_edc_dux/blob/main/CONTRIBUTING.md).

## License

MIT; see [LICENSE.md](https://github.com/basbl/ex_castor_edc_dux/blob/main/LICENSE.md).
