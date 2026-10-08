# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## Unreleased

### Added

- `CastorEDC.Dux.data_points/3` writes the values a study collected to Parquet as they stream in, and gives a lazy frame with a row per value, or with `format: :wide` a frame per study, repeating data and survey with a column per variable, typed by its field. Values marked missing are null, with their codes in a column of their own.
