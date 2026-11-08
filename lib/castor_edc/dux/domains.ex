defmodule CastorEDC.Dux.Domains do
  @moduledoc false
  # Lazy frames over the CSV files of a grouped participant data export,
  # which has a file per domain, typed by the domain's own variable list,
  # for DuckDB to read directly.

  import CastorEDC.Dux.Table, only: [identifier: 1, literal: 1]

  # Metadata columns whose variable list type doesn't suit them: an ID that
  # isn't a number to compute with, and a visit's number.
  @metadata %{
    "randomization_id" => {"randomization_id", :string},
    "visit_number" => {"visit_number", :integer},
    "participant_creation_date" => {"created_on", :datetime},
    "randomized_on" => {"randomized_on", :datetime}
  }

  @missing 95..99

  @doc false
  # Whether the paths are a grouped export's files.
  @spec grouped?([Path.t()]) :: boolean()
  def grouped?(paths), do: Enum.any?(paths, &(Path.basename(&1) == "domain_mapping.csv"))

  @doc false
  # A frame per domain, keyed by its abbreviation, with the missing codes'
  # and the options' names columns when asked.
  @spec read([Path.t()], boolean(), boolean()) :: %{String.t() => Dux.t()}
  def read(paths, missing_columns, labels) do
    files = Map.new(paths, &{Path.basename(&1), &1})

    for {name, path} <- files, String.ends_with?(name, "_variablelist.csv"), into: %{} do
      domain = String.replace_suffix(name, "_variablelist.csv", "")

      frame =
        case files["#{domain}.csv"] do
          nil -> Dux.from_query("SELECT NULL AS participant_id LIMIT 0")
          data -> frame(data, variables(path), {missing_columns, labels})
        end

      {domain, frame}
    end
  end

  defp csv(path), do: "read_csv(#{literal(path)}, delim = ';', quote = '\"', header = true, all_varchar = true)"

  # A variable list's rows end early when their last fields are empty.
  defp variable_list(path),
    do: "read_csv(#{literal(path)}, delim = ';', quote = '\"', header = true, all_varchar = true, null_padding = true)"

  defp headers(path) do
    ("DESCRIBE SELECT * FROM " <> csv(path))
    |> Dux.from_query()
    |> Dux.to_rows()
    |> Enum.map(& &1["column_name"])
  end

  # Each column's kind, from the variable list: {name in the frame, kind},
  # with a checkbox's columns named after their options' values and the
  # missing-code and name columns marked as such.
  defp variables(path) do
    rows = ("SELECT * FROM " <> variable_list(path)) |> Dux.from_query() |> Dux.to_rows()
    names = MapSet.new(rows, & &1["Domain variable name"])

    Map.new(rows, fn row ->
      column = row["Domain variable name"]
      {column, kind(row, column, names)}
    end)
  end

  defp kind(%{"Domain abbreviation" => "Metadata"} = row, column, _names) do
    {name, kind} = Map.get(@metadata, column, {column, metadata_kind(row["Field type"])})
    {:metadata, name, kind}
  end

  defp kind(row, column, names) do
    base = String.replace_suffix(column, "_U", "")
    named = String.replace_suffix(column, "_N", "")

    cond do
      String.ends_with?(column, "_U") and MapSet.member?(names, base) -> {:missing, base}
      String.ends_with?(column, "_N") and MapSet.member?(names, named) -> {:label, named}
      row["Field type"] == "checkbox" -> {checkbox_name(row, column), :boolean}
      true -> {column, value_kind(row["Field type"], row["SAS field type"])}
    end
  end

  defp metadata_kind("datetime"), do: :datetime
  defp metadata_kind(_type), do: :string

  defp value_kind(_type, "YYMMDD10"), do: :date
  defp value_kind(type, _sas) when type in ["numeric", "slider", "numberdate"], do: :number
  defp value_kind("year", _sas), do: :integer
  defp value_kind("date", _sas), do: :date
  defp value_kind("time", _sas), do: :time
  defp value_kind("datetime", _sas), do: :datetime
  defp value_kind(_type, _sas), do: :string

  # A checkbox's columns are named after its options' names, cut short;
  # the frame names them `<variable>_<option value>`, as the data points
  # have them. The variable list names the variable only in its info.
  defp checkbox_name(row, column) do
    case {Regex.run(~r/related to the (\S+) domain variable/, row["Variable info"] || ""), row["Option value"]} do
      {[_match, variable], value} when is_binary(value) -> "#{variable}_#{value}"
      _other -> column
    end
  end

  defp frame(path, variables, options) do
    headers = headers(path)
    codes = for header <- headers, {:missing, base} <- [variables[header]], into: %{}, do: {base, header}

    columns =
      headers
      |> Enum.flat_map(&columns(&1, variables, codes, options))
      |> Enum.uniq_by(&elem(&1, 0))
      |> Enum.map(fn {name, sql} -> "#{sql} AS #{identifier(name)}" end)

    Dux.from_query("SELECT #{Enum.join(columns, ", ")} FROM #{csv(path)}")
  end

  defp columns(header, variables, codes, {missing_columns, labels}) do
    column = identifier(header)

    case Map.get(variables, header, {:metadata, header, :string}) do
      {:missing, _base} ->
        []

      {:metadata, name, kind} ->
        [{name, value(column, kind)}]

      {:label, base} ->
        if labels, do: [{base <> "_label", column}], else: []

      {name, :boolean} ->
        variable = name |> String.split("_") |> Enum.drop(-1) |> Enum.join("_")
        [{name, "(#{column} <> '0')"}] ++ missing_column(variable, header, codes, missing_columns)

      {name, kind} ->
        [{name, missing_free(column, kind)}] ++ missing_column(name, header, codes, missing_columns)
    end
  end

  # The missing codes of a variable, from its `_U` column, or from values
  # written as codes in its own column.
  defp missing_column(_name, _header, _codes, false), do: []

  defp missing_column(name, header, codes, true) do
    source = identifier(Map.get(codes, header, header))
    whens = Enum.map_join(@missing, " ", &"WHEN '-#{&1}' THEN #{&1}")
    [{name <> "_missing", "CAST(CASE #{source} #{whens} END AS SMALLINT)"}]
  end

  defp missing_free(column, :date), do: value(column, :date)

  defp missing_free(column, kind) do
    codes = Enum.map_join(@missing, ", ", &"'-#{&1}'")
    "CASE WHEN #{column} IN (#{codes}) THEN NULL ELSE #{value(column, kind)} END"
  end

  defp value(column, :string), do: column
  defp value(column, :number), do: "TRY_CAST(#{column} AS DOUBLE)"
  defp value(column, :integer), do: "TRY_CAST(#{column} AS BIGINT)"
  defp value(column, :date), do: "TRY_CAST(#{column} AS DATE)"
  defp value(column, :time), do: "CAST(try_strptime(#{column}, ['%H:%M:%S', '%H:%M']) AS TIME)"
  defp value(column, :datetime), do: "try_strptime(#{column}, ['%Y-%m-%d %H:%M:%S', '%Y-%m-%d %H:%M'])"
end
