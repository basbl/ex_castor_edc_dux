# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- `CastorEDC.Dux.survey_package_instances/3`, `repeating_data_instances/3` and `queries/3` write those resources to Parquet and give frames over them, a row each, with fixed types.
  A survey package instance's `parent_type` is named (`visit` or `repeating_data_instance`) instead of the API's code, and a query's `remarks` counts its remarks.
- `from:` on `CastorEDC.Dux.participant_data/3` reads an export already made instead of running one: the `CastorEDC.Export` struct a download returned (in memory, saved or unzipped), or the path to its zip or the directory it was unzipped into.
- `labels: true` on `CastorEDC.Dux.data_points/3` gives the names of the chosen options, which the user saw, next to their values: a `label` column in the long frame, and the names instead of the values in the wide frames' radio and dropdown columns.

### Changed

- Builds on ex_castor_edc 1.0 (`~> 1.0`) instead of its release candidate.

### Fixed

- `CastorEDC.Dux.participant_data/3` reads the export's -95 to -99 as missing values in every field but dates and checkboxes, not only in numeric and year fields.
  A missing datetime became null without its code, and a missing radio, dropdown or text value came through as the text `-98`; they're now nulls, and with `missing_columns: true` those fields get a `<variable>_missing` column too.

## [0.1.0] - 2026-10-15

### Added

- `CastorEDC.Dux.data_points/3` writes the values a study collected to Parquet as they stream in, and gives a lazy frame with a row per value, or with `format: :wide` a frame per study, repeating data and survey with a column per variable, typed by its field.
  Values marked missing are null, with their codes in a column of their own.
- `CastorEDC.Dux.participants/3`, `fields/3`, `sites/3` and `option_groups/3` give those resources as frames, a row each (a row per option for option groups), with fixed types.
- `CastorEDC.Dux.participant_data/3` runs a participant data export (CSV) and gives lazy frames over its files, a frame per study, repeating data and survey, typed by the export's own variable lists, with checkbox columns named after their options' values and the export's codes for missing values turned into nulls (and, if asked, codes in columns of their own).
  It takes a few requests however big the study is.
- A Livebook, `notebook/analysis.livemd`, that loads a study into frames and takes a first look at it.

[0.1.0]: https://hex.pm/packages/ex_castor_edc_dux/0.1.0
