defmodule CastorEDC.Dux do
  @moduledoc """
  A Castor EDC study's data as lazy `Dux` frames, backed by DuckDB.

  The data is written to Parquet files as it streams in from the API, so
  it never has to fit in memory, and each frame is a lazy query over its
  file. Column types come from the study's structure, not from inferring
  them from the data, so a column has the same type whatever values it
  happens to hold, and an empty study gives frames with the same columns
  as a full one.

      client = CastorEDC.new(client_id: "...", client_secret: "...")
      {:ok, frame} = CastorEDC.Dux.data_points(client, study_id)

  The files go in a new directory in the system's temporary directory, or
  in the one given as `:dir`. They stay there for as long as the frames
  need them; remove the directory when you're done.

  Functions return `{:ok, result}`, or `{:error, %CastorEDC.Error{}}` when
  a request fails.
  """

  alias CastorEDC.Dux.Table
  alias CastorEDC.Tabular

  @typedoc """
  A study's values in the wide format: a frame for its own values, and one
  per repeating data and per survey, keyed by their names (or their IDs,
  when two share a name).
  """
  @type wide :: %{study: Dux.t(), repeating_data: %{String.t() => Dux.t()}, surveys: %{String.t() => Dux.t()}}

  @sources [:study, :repeating_data, :survey]

  @long [
    {"participant_id", :participant_id, "VARCHAR"},
    {"site_id", :site_id, "VARCHAR"},
    {"source", :source, "VARCHAR"},
    {"instance_id", :instance_id, "VARCHAR"},
    {"parent_id", :parent_id, "VARCHAR"},
    {"field_id", :field_id, "VARCHAR"},
    {"variable_name", :variable_name, "VARCHAR"},
    {"value", :value, "VARCHAR"},
    {"missing", :missing, "SMALLINT"},
    {"raw_value", :raw_value, "VARCHAR"},
    {"updated_on", :updated_on, "TIMESTAMP"}
  ]

  @doc """
  The values the study collected, from `CastorEDC.Tabular.data_points/3`.

  By default, a single frame with a row per value, holding the study's,
  repeating data's and surveys' values alike, written to Parquet page by
  page as the values come in:

  | Column | Type | |
  | --- | --- | --- |
  | `participant_id`, `site_id` | `VARCHAR` | whose value it is |
  | `source` | `VARCHAR` | `study`, `repeating_data` or `survey` |
  | `instance_id`, `parent_id` | `VARCHAR` | the repeating data or survey instance, and the repeating data or survey; null for the study's values |
  | `field_id`, `variable_name` | `VARCHAR` | the field |
  | `value` | `VARCHAR` | the decoded value as text: ISO 8601 for dates and times, `;` between checked options |
  | `missing` | `SMALLINT` | the code of a value marked missing (95 to 99), whose `value` is null |
  | `raw_value` | `VARCHAR` | the value as the API sent it |
  | `updated_on` | `TIMESTAMP` | when it last changed |

  With `format: :wide`, a `t:wide/0` map of frames: one for the study's
  values, with a row per participant, and one for each repeating data and
  survey, with a row per instance. After `participant_id` and `site_id`
  (and `instance_id` for repeating data and surveys) comes a column per
  variable, in the order the study shows them, typed by its field:

  | Field type | Type |
  | --- | --- |
  | `numeric`, `slider` | `DOUBLE` |
  | `year` | `BIGINT` |
  | `date` | `DATE` |
  | `time` | `TIME` |
  | `datetime` | `TIMESTAMP` |
  | `checkbox` | a `BOOLEAN` column per option, `<variable>_<option value>` |
  | others | `VARCHAR`, as text as in the long format |

  Values marked missing and encrypted values are null. With
  `missing_columns: true`, each variable also gets a `<variable>_missing`
  column of `SMALLINT` holding the code. The wide format needs every value
  before it can build a row, so it holds the values in memory first.

  ## Options

    * `:format` - `:long` (the default) or `:wide`
    * `:missing_columns` - add the missing-value columns to wide frames;
      `false` by default
    * `:dir` - where to write the files
    * `:sources` and `:schema` - as for `CastorEDC.Tabular.data_points/3`
  """
  @spec data_points(CastorEDC.client(), String.t(), keyword()) ::
          {:ok, Dux.t() | wide()} | {:error, CastorEDC.Error.t()}
  def data_points(client, study_id, opts \\ []) do
    {missing_columns, opts} = Keyword.pop(opts, :missing_columns, false)
    {dir, opts} = Keyword.pop(opts, :dir)

    case Keyword.get(opts, :format, :long) do
      :long -> {:ok, long(client, study_id, opts, Table.dir(dir))}
      :wide -> {:ok, wide(client, study_id, opts, missing_columns, Table.dir(dir))}
      other -> raise ArgumentError, "expected :format to be :long or :wide, got: #{inspect(other)}"
    end
  rescue
    error in CastorEDC.Error -> {:error, error}
  end

  defp long(client, study_id, opts, dir) do
    client
    |> Tabular.data_points(study_id, opts)
    |> Stream.map(&%{&1 | source: Atom.to_string(&1.source)})
    |> Stream.map(&Map.put(&1, :missing, Table.missing(&1.value)))
    |> Table.write(@long, dir, "data_points")
  end

  defp wide(client, study_id, opts, missing_columns, dir) do
    schema = Keyword.get_lazy(opts, :schema, fn -> schema!(client, study_id) end)
    sources = Keyword.get(opts, :sources, @sources)

    rows =
      client
      |> Tabular.data_points(study_id, Keyword.put(opts, :schema, schema))
      |> Enum.group_by(&{&1.source, &1.parent_id})

    frames =
      for {{{context, parent_id} = key, columns}, index} <- Enum.with_index(groups(schema, sources)) do
        rows = Map.get(rows, key, [])
        frame = frame(context, columns, rows, missing_columns, dir, "#{context}_#{index}")
        {context, parent_id, parent_name(columns), frame}
      end

    %{
      study: Enum.find_value(frames, &study_frame/1) || frame(:study, [], [], missing_columns, dir, "study"),
      repeating_data: named(frames, :repeating_data),
      surveys: named(frames, :survey)
    }
  end

  defp study_frame({:study, _id, _name, frame}), do: frame
  defp study_frame(_other), do: nil

  # The schema's columns by the frame they belong to.
  defp groups(schema, sources) do
    schema
    |> Map.values()
    |> Enum.filter(&(&1.context in sources))
    |> Enum.group_by(&{&1.context, if(&1.context != :study, do: &1.parent_id)})
    |> Enum.sort()
  end

  defp schema!(client, study_id) do
    case Tabular.schema(client, study_id) do
      {:ok, schema} -> schema
      {:error, error} -> raise error
    end
  end

  defp parent_name(columns), do: Enum.find_value(columns, & &1.parent_name)

  defp named(frames, context) do
    entries = for {^context, id, name, frame} <- frames, do: {id, name || id, frame}
    shared = entries |> Enum.frequencies_by(&elem(&1, 1)) |> Map.filter(fn {_name, count} -> count > 1 end)

    Map.new(entries, fn {id, name, frame} -> {if(Map.has_key?(shared, name), do: id, else: name), frame} end)
  end

  defp frame(context, columns, rows, missing_columns, dir, name) do
    fixed =
      [{"participant_id", :participant_id, "VARCHAR"}, {"site_id", :site_id, "VARCHAR"}] ++
        if context == :study, do: [], else: [{"instance_id", :instance_id, "VARCHAR"}]

    variables =
      columns
      |> Enum.sort_by(&{&1.position, variable_name(&1)})
      |> Enum.flat_map(&variable_columns(&1, missing_columns))

    rows
    |> Enum.sort_by(&{&1.participant_id, &1.instance_id})
    |> Table.write(fixed ++ variables, dir, name)
  end

  # The frame columns of a field: {name, a function reading the column's
  # value from a wide row, type}.
  defp variable_columns(column, missing_columns) do
    names = for {name, _value} <- Tabular.wide_cells([column], %{}), do: name
    values = for name <- names, do: {name, &Map.get(&1, name), type(column)}

    if missing_columns do
      first = hd(names)
      values ++ [{"#{variable_name(column)}_missing", &Table.missing(Map.get(&1, first)), "SMALLINT"}]
    else
      values
    end
  end

  defp variable_name(%{variable_name: name}) when is_binary(name) and name != "", do: name
  defp variable_name(%{field_id: id}), do: id

  # A checkbox field has a boolean column per option; one without options
  # keeps its list, as text.
  defp type(%{field_type: "checkbox", option_group: %{options: [_option | _more]}}), do: "BOOLEAN"
  defp type(%{type: :number}), do: "DOUBLE"
  defp type(%{type: :integer}), do: "BIGINT"
  defp type(%{type: :date}), do: "DATE"
  defp type(%{type: :time}), do: "TIME"
  defp type(%{type: :naive_datetime}), do: "TIMESTAMP"
  defp type(_column), do: "VARCHAR"
end
