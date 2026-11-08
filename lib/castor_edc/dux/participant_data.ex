defmodule CastorEDC.Dux.ParticipantData do
  @moduledoc false
  # Lazy frames over the CSV files of a participant data export, typed by
  # the export's own variable lists, for DuckDB to read directly.

  import CastorEDC.Dux.Table, only: [identifier: 1, literal: 1]

  @variable_lists ~w(study_variablelist.csv report_variablelist.csv survey_variablelist.csv)

  # The columns before the variables, by their header: their name in the
  # frame, and how to read them.
  @fixed %{
    "Participant Id" => {"participant_id", :string},
    "Castor Participant ID" => {"participant_id", :string},
    "Participant Status" => {"participant_status", :string},
    "Castor Participant Status" => {"participant_status", :string},
    "Site Abbreviation" => {"site_abbreviation", :string},
    "Participant Creation Date" => {"created_on", :timestamp},
    "Repeating Data Creation Date" => {"created_on", :timestamp},
    "Repeating data Name Custom" => {"instance_name", :string},
    "Repeating data Parent" => {"parent", :string},
    "Survey Instance Id" => {"instance_id", :string},
    "Survey Creation Date" => {"created_on", :timestamp},
    "Survey Sent Date" => {"sent_on", :timestamp},
    "Survey Progress" => {"progress", :integer},
    "Survey Completed On" => {"completed_on", :timestamp},
    "Survey Parent" => {"parent", :string},
    "Survey Package Name" => {"survey_package_name", :string},
    "Survey Package Id" => {"survey_package_id", :string}
  }

  @missing 95..99

  @doc false
  # The paths of the files of an export already made: a CastorEDC.Export
  # struct holding the zip in memory, its saved path or its unzipped files,
  # or the path to a zip or to the directory it was unzipped into. Files
  # that aren't on disk yet go in `into`.
  @spec paths(CastorEDC.Export.t() | Path.t(), Path.t()) :: [Path.t()]
  def paths(%CastorEDC.Export{type: type, format: format}, _into) when type != :participant_data or format != :csv,
    do: raise(ArgumentError, "expected a participant data export in CSV, got #{inspect(type)} in #{inspect(format)}")

  def paths(%CastorEDC.Export{files: [_file | _more] = files}, into) do
    for file <- files do
      case file do
        {name, contents} -> write(into, to_string(name), contents)
        path -> path
      end
    end
  end

  def paths(%CastorEDC.Export{data: data}, into) when is_binary(data), do: unzip(data, into)
  def paths(%CastorEDC.Export{path: path}, into) when is_binary(path), do: paths(path, into)

  def paths(%CastorEDC.Export{id: id}, _into),
    do: raise(ArgumentError, "export #{id} hasn't been downloaded; download it, or pass the path it was saved to")

  def paths(path, into) when is_binary(path) do
    if File.dir?(path),
      do: path |> Path.join("*.csv") |> Path.wildcard(),
      else: path |> File.read!() |> unzip(into)
  end

  defp write(dir, name, contents) do
    path = Path.join(dir, Path.basename(name))
    File.mkdir_p!(dir)
    File.write!(path, contents)
    path
  end

  defp unzip(zip, into) do
    File.mkdir_p!(into)

    case :zip.unzip(zip, cwd: String.to_charlist(into)) do
      {:ok, paths} -> Enum.map(paths, &to_string/1)
      {:error, reason} -> raise ArgumentError, "couldn't unzip the export: #{inspect(reason)}"
    end
  end

  @doc false
  # The frames of the export's files, given as paths, with the names of the
  # study's repeating data and surveys.
  @spec read([Path.t()], [String.t()], [String.t()], boolean()) :: CastorEDC.Dux.wide()
  def read(paths, repeating_data_names, survey_names, missing_columns) do
    files = Map.new(paths, &{Path.basename(&1), &1})
    variables = variables(files)

    frames =
      for {name, path} <- files, name not in ["field_options.csv" | @variable_lists], String.ends_with?(name, ".csv") do
        headers = headers(path)
        {source(headers), name, frame(path, headers, variables, missing_columns)}
      end

    {study_file, study} =
      Enum.find_value(frames, {nil, Dux.from_query("SELECT NULL AS participant_id LIMIT 0")}, fn {source, file, frame} ->
        if source == :study, do: {file, frame}
      end)

    prefix = if study_file, do: base(study_file) <> "_", else: ""

    %{
      study: study,
      repeating_data: named(frames, :repeating_data, repeating_data_names, prefix),
      surveys: named(frames, :survey, survey_names, prefix)
    }
  end

  defp csv(path), do: "read_csv(#{literal(path)}, delim = ';', quote = '\"', header = true, all_varchar = true)"

  defp headers(path) do
    ("DESCRIBE SELECT * FROM " <> csv(path))
    |> Dux.from_query()
    |> Dux.to_rows()
    |> Enum.map(& &1["column_name"])
  end

  defp source(headers) do
    cond do
      "Survey Instance Id" in headers -> :survey
      "Repeating data Name Custom" in headers -> :repeating_data
      true -> :study
    end
  end

  # Files are named <study>_<repeating data or survey>_export_<date>.csv,
  # with the name's spaces as underscores and some punctuation dropped. A
  # file that matches none of the names keeps the part of its own.
  defp named(frames, source, names, prefix) do
    for {^source, file, frame} <- frames, into: %{} do
      base = base(file)
      key = normalize(base)

      name =
        names
        |> Enum.filter(&String.ends_with?(key, normalize(&1)))
        |> Enum.max_by(&String.length/1, fn -> String.replace_prefix(base, prefix, "") end)

      {name, frame}
    end
  end

  defp base(file), do: String.replace(file, ~r/_export_\d+\.csv$/, "")

  defp normalize(name), do: name |> String.downcase() |> String.replace(~r/[^\p{L}\p{N}]/u, "")

  # Each variable's original field type and options, from the variable
  # lists and field_options.csv.
  defp variables(files) do
    options =
      case files do
        %{"field_options.csv" => path} ->
          path |> rows() |> Enum.group_by(& &1["Option group name"], &{&1["Option name"], &1["Option value"]})

        _none ->
          %{}
      end

    for list <- @variable_lists, path = files[list], row <- rows(path), into: %{} do
      # A checkbox has a row per option, as `<variable>#<option name>`.
      variable = row["Variable name"] |> String.split("#", parts: 2) |> hd()
      {variable, %{type: row["Original field type"], options: Map.get(options, row["Optiongroup name"], [])}}
    end
  end

  defp rows(path), do: ("SELECT * FROM " <> csv(path)) |> Dux.from_query() |> Dux.to_rows()

  defp frame(path, headers, variables, missing_columns) do
    columns = Enum.flat_map(headers, &columns(&1, variables, missing_columns))
    Dux.from_query("SELECT #{Enum.join(columns, ", ")} FROM #{csv(path)}")
  end

  defp columns(header, variables, missing_columns) do
    column = identifier(header)

    case {@fixed[header], String.split(header, "#", parts: 2)} do
      {{name, kind}, _parts} ->
        ["#{value(column, kind)} AS #{identifier(name)}"]

      {nil, [variable, option]} ->
        ["(#{column} <> '0') AS #{identifier(checkbox_name(variable, option, variables))}"]

      {nil, [variable]} ->
        kind = kind(variables[variable])
        value = "#{missing_free(column, kind)} AS #{identifier(variable)}"

        if missing_columns and kind != :string,
          do: [value, "#{missing(column, kind)} AS #{identifier(variable <> "_missing")}"],
          else: [value]
    end
  end

  # A checkbox's columns are named after its options' names; the frame
  # names them after their values, as the data points have them.
  defp checkbox_name(variable, option, variables) do
    options = get_in(variables, [variable, :options]) || []

    case List.keyfind(options, option, 0) do
      {_name, value} -> "#{variable}_#{value}"
      nil -> "#{variable}_#{option}"
    end
  end

  defp kind(%{type: type}) when type in ["numeric", "slider"], do: :number
  defp kind(%{type: "year"}), do: :integer
  defp kind(%{type: "date"}), do: :date
  defp kind(%{type: "datetime"}), do: :datetime
  defp kind(%{type: "time"}), do: :time
  defp kind(_other), do: :string

  # Values marked missing are written as -95 to -99 in numbers and as the
  # dates 1 January 2995 to 2999.
  defp missing(column, kind) do
    whens = Enum.map_join(@missing, " ", &"WHEN #{literal(code_text(&1, kind))} THEN #{&1}")
    "CAST(CASE #{missing_part(column, kind)} #{whens} END AS SMALLINT)"
  end

  defp missing_free(column, :string), do: column

  defp missing_free(column, kind) do
    codes = Enum.map_join(@missing, ", ", &literal(code_text(&1, kind)))
    "CASE WHEN #{missing_part(column, kind)} IN (#{codes}) THEN NULL ELSE #{value(column, kind)} END"
  end

  defp missing_part(column, kind) when kind in [:date, :datetime], do: "left(#{column}, 10)"
  defp missing_part(column, _kind), do: column

  defp code_text(code, kind) when kind in [:date, :datetime], do: "01-01-29#{code}"
  defp code_text(code, _kind), do: "-#{code}"

  defp value(column, :string), do: column
  defp value(column, :number), do: "TRY_CAST(#{column} AS DOUBLE)"
  defp value(column, :integer), do: "TRY_CAST(#{column} AS BIGINT)"
  defp value(column, :date), do: "CAST(try_strptime(#{column}, '%d-%m-%Y') AS DATE)"
  defp value(column, :time), do: "CAST(try_strptime(#{column}, ['%H:%M:%S', '%H:%M']) AS TIME)"
  defp value(column, :datetime), do: "try_strptime(#{column}, ['%d-%m-%Y %H:%M:%S', '%d-%m-%Y %H:%M'])"
  defp value(column, :timestamp), do: value(column, :datetime)
end
