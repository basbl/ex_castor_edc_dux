defmodule CastorEDC.Dux.Table do
  @moduledoc false
  # Writes rows to a Parquet file with given DuckDB types, streaming them
  # through newline-delimited JSON so they're never all in memory and no
  # type is inferred, and gives a lazy frame over it.

  alias CastorEDC.MissingValue
  alias CastorEDC.PartialDate

  @type column :: {String.t(), term(), String.t()}

  @doc false
  # The directory a call's files go in: the one given, or a new one in the
  # system's temporary directory.
  @spec dir(Path.t() | nil) :: Path.t()
  def dir(nil), do: dir(Path.join(System.tmp_dir!(), "castor_edc_dux-#{System.unique_integer([:positive])}"))

  def dir(dir) do
    File.mkdir_p!(dir)
    dir
  end

  @doc false
  # Writes the rows (maps, read by each column's key, or functions of the
  # row) to <dir>/<name>.parquet.
  @spec write(Enumerable.t(), [column()], Path.t(), String.t()) :: Dux.t()
  def write(rows, columns, dir, name) do
    json = Path.join(dir, name <> ".ndjson")
    parquet = Path.join(dir, name <> ".parquet")

    rows
    |> Stream.map(fn row -> [JSON.encode!(Map.new(columns, &cell(row, &1))), ?\n] end)
    |> Stream.into(File.stream!(json))
    |> Stream.run()

    types = Enum.map_join(columns, ", ", fn {column, _key, type} -> "#{literal(column)}: #{literal(type)}" end)
    names = Enum.map_join(columns, ", ", fn {column, _key, _type} -> identifier(column) end)

    "SELECT #{names} FROM read_json(#{literal(json)}, format = 'newline_delimited', columns = {#{types}})"
    |> Dux.from_query()
    |> Dux.to_parquet(parquet)

    File.rm!(json)
    Dux.from_parquet(parquet)
  end

  defp cell(row, {column, key, type}) do
    value = if is_function(key, 1), do: key.(row), else: Map.get(row, key)
    {column, json(value, type)}
  end

  @doc false
  # A value as JSON that DuckDB reads as the type: missing and encrypted
  # values become null, and anything that isn't of the type becomes text.
  @spec json(term(), String.t()) :: term()
  def json(%MissingValue{}, _type), do: nil
  def json(:encrypted, _type), do: nil
  def json(nil, _type), do: nil
  def json(value, "DOUBLE") when is_number(value), do: value / 1
  def json(value, type) when type in ["BIGINT", "SMALLINT"] and is_integer(value), do: value
  def json(value, "BOOLEAN") when is_boolean(value), do: value
  def json(%Date{} = value, "DATE"), do: Date.to_iso8601(value)
  def json(%Time{} = value, "TIME"), do: Time.to_iso8601(value)
  def json(%NaiveDateTime{} = value, "TIMESTAMP"), do: NaiveDateTime.to_iso8601(value)
  def json(%DateTime{} = value, "TIMESTAMPTZ"), do: DateTime.to_iso8601(value)
  def json(value, "VARCHAR"), do: text(value)
  def json(_value, _type), do: nil

  @doc false
  # The text of a decoded value: ISO 8601 for dates and times, `;` between
  # the parts of a checkbox, number-with-date or location, and JSON for a
  # grid.
  @spec text(term()) :: String.t() | nil
  def text(nil), do: nil
  def text(%MissingValue{}), do: nil
  def text(:encrypted), do: nil
  def text(value) when is_binary(value), do: value
  def text(value) when is_number(value) or is_atom(value), do: to_string(value)
  def text(%PartialDate{} = date), do: PartialDate.to_iso8601(date)
  def text(%module{} = value) when module in [Date, Time, NaiveDateTime, DateTime], do: module.to_iso8601(value)
  def text({:upload, name}), do: name
  def text({first, second}), do: Enum.map_join([first, second], ";", &(text(&1) || ""))
  def text(values) when is_list(values), do: Enum.map_join(values, ";", &text/1)

  def text(grid) when is_map(grid),
    do: grid |> Map.new(fn {row, cells} -> {row, Map.new(cells, &grid_cell/1)} end) |> JSON.encode!()

  defp grid_cell({column, %MissingValue{} = missing}), do: {column, MissingValue.to_wire(missing)}
  defp grid_cell(cell), do: cell

  @doc false
  # The missing-value code of a value, if it's marked missing.
  @spec missing(term()) :: 95..99 | nil
  def missing(%MissingValue{code: code}), do: code
  def missing(_value), do: nil

  @doc false
  @spec identifier(String.t()) :: String.t()
  def identifier(name), do: ~s("#{String.replace(name, ~s("), ~s(""))}")

  @doc false
  @spec literal(String.t()) :: String.t()
  def literal(text), do: "'#{String.replace(text, "'", "''")}'"
end
