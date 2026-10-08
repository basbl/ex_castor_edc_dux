# CastorEDC.Dux

Castor EDC study data as [Dux](https://hexdocs.pm/dux) dataframes, backed by DuckDB.

It builds on [ex_castor_edc](https://github.com/basbl/ex_castor_edc). Data streams from the API into Parquet files, so it never has to fit in memory, and every frame's column types come from the study's structure instead of being inferred from the data.

## Installation

```elixir
def deps do
  [
    {:ex_castor_edc_dux, "~> 0.1.0"}
  ]
end
```

## Usage

```elixir
client = CastorEDC.new(client_id: "...", client_secret: "...")

# A row per value: the study's, repeating data's and surveys' values alike.
{:ok, values} = CastorEDC.Dux.data_points(client, study_id, dir: "data")

# A frame per study, repeating data and survey, with a column per variable.
{:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
  CastorEDC.Dux.data_points(client, study_id, format: :wide, dir: "data")

# The study's participants, fields, sites and options.
{:ok, participants} = CastorEDC.Dux.participants(client, study_id, dir: "data")
{:ok, fields} = CastorEDC.Dux.fields(client, study_id, dir: "data")
{:ok, sites} = CastorEDC.Dux.sites(client, study_id, dir: "data")
{:ok, options} = CastorEDC.Dux.option_groups(client, study_id, dir: "data")
```
