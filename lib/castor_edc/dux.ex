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

  alias CastorEDC.Dux.ParticipantData
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

  @participants [
    {"participant_id", :participant_id, "VARCHAR"},
    {"site_id", :site_id, "VARCHAR"},
    {"site_name", :site_name, "VARCHAR"},
    {"status", :status, "VARCHAR"},
    {"participant_status", :participant_status, "VARCHAR"},
    {"progress", :progress, "DOUBLE"},
    {"locked", :locked, "BOOLEAN"},
    {"archived", :archived, "BOOLEAN"},
    {"archived_reason", :archived_reason, "VARCHAR"},
    {"randomization_group", :randomization_group, "BIGINT"},
    {"randomization_group_name", :randomization_group_name, "VARCHAR"},
    {"randomized_id", :randomized_id, "VARCHAR"},
    {"randomized_on", :randomized_on, "TIMESTAMPTZ"},
    {"created_by", :created_by, "VARCHAR"},
    {"created_on", :created_on, "TIMESTAMPTZ"},
    {"updated_by", :updated_by, "VARCHAR"},
    {"updated_on", :updated_on, "TIMESTAMPTZ"}
  ]

  @fields [
    {"field_id", :field_id, "VARCHAR"},
    {"variable_name", :variable_name, "VARCHAR"},
    {"label", :label, "VARCHAR"},
    {"field_type", :field_type, "VARCHAR"},
    {"value_type", :value_type, "VARCHAR"},
    {"context", :context, "VARCHAR"},
    {"parent_id", :parent_id, "VARCHAR"},
    {"parent_name", :parent_name, "VARCHAR"},
    {"form_id", :form_id, "VARCHAR"},
    {"form_name", :form_name, "VARCHAR"},
    {"field_number", :field_number, "BIGINT"},
    {"option_group_id", :option_group_id, "VARCHAR"},
    {"required", :required, "BOOLEAN"},
    {"hidden", :hidden, "BOOLEAN"},
    {"units", :units, "VARCHAR"},
    {"min", :field_min, "DOUBLE"},
    {"max", :field_max, "DOUBLE"}
  ]

  @sites [
    {"site_id", :id, "VARCHAR"},
    {"name", :name, "VARCHAR"},
    {"abbreviation", :abbreviation, "VARCHAR"},
    {"code", :code, "VARCHAR"},
    {"country_id", :country_id, "BIGINT"},
    {"order", :order, "BIGINT"},
    {"deleted", :deleted, "BOOLEAN"}
  ]

  @option_groups [
    {"option_group_id", :option_group_id, "VARCHAR"},
    {"option_group_name", :option_group_name, "VARCHAR"},
    {"value", :value, "VARCHAR"},
    {"name", :name, "VARCHAR"},
    {"order", :order, "BIGINT"}
  ]

  @doc """
  The study's participants, a row each.

  Columns: `participant_id`, `site_id` and `site_name`, `status`,
  `participant_status` (the name of the study's own status, if it has
  them), `progress` (`DOUBLE`, a percentage), `locked` and `archived`
  (`BOOLEAN`), `archived_reason`, `randomization_group` (`BIGINT`),
  `randomization_group_name`, `randomized_id`, `randomized_on`,
  `created_by`, `created_on`, `updated_by` and `updated_on`. Dates and
  times are `TIMESTAMPTZ` (which Dux reads back as UTC), the rest
  `VARCHAR`.

  Takes `:dir`, as `data_points/3` does.
  """
  @spec participants(CastorEDC.client(), String.t(), keyword()) :: {:ok, Dux.t()} | {:error, CastorEDC.Error.t()}
  def participants(client, study_id, opts \\ []) do
    resource(@participants, opts, "participants", fn ->
      for participant <- CastorEDC.Participants.stream_participants(client, study_id) do
        Map.merge(Map.from_struct(participant), %{
          site_id: participant.site && participant.site.id,
          site_name: participant.site && participant.site.name,
          participant_status: participant.participant_status && participant.participant_status.name
        })
      end
    end)
  end

  @doc """
  The study's fields that hold values, a row each, in the order the study
  shows them, from `CastorEDC.Tabular.schema/2`.

  Columns: `field_id`, `variable_name`, `label`, `field_type`,
  `value_type` (as `CastorEDC.Tabular.value_type/1` gives it, such as
  `number` or `list(string)`), `context` (`study`, `repeating_data` or
  `survey`), `parent_id` and `parent_name` (the visit, repeating data or
  survey), `form_id`, `form_name`, `field_number` (`BIGINT`),
  `option_group_id`, `required` and `hidden` (`BOOLEAN`), `units`, and
  `min` and `max` (`DOUBLE`).

  Join `option_group_id` with `option_groups/3` for the options. Takes
  `:dir`, as `data_points/3` does.
  """
  @spec fields(CastorEDC.client(), String.t(), keyword()) :: {:ok, Dux.t()} | {:error, CastorEDC.Error.t()}
  def fields(client, study_id, opts \\ []) do
    resource(@fields, opts, "fields", fn ->
      for column <- client |> schema!(study_id) |> Map.values() |> Enum.sort_by(& &1.position) do
        Map.merge(column, %{
          value_type: value_type(column.type),
          context: column.context && Atom.to_string(column.context),
          field_number: column.field.field_number,
          option_group_id: column.option_group && column.option_group.id,
          required: flag(column.field.field_required),
          hidden: flag(column.field.field_hidden),
          units: column.field.field_units,
          field_min: column.field.field_min,
          field_max: column.field.field_max
        })
      end
    end)
  end

  @doc """
  The study's sites, a row each.

  Columns: `site_id`, `name`, `abbreviation`, `code`, `country_id` and
  `order` (`BIGINT`) and `deleted` (`BOOLEAN`). Takes `:dir`, as
  `data_points/3` does.
  """
  @spec sites(CastorEDC.client(), String.t(), keyword()) :: {:ok, Dux.t()} | {:error, CastorEDC.Error.t()}
  def sites(client, study_id, opts \\ []) do
    resource(@sites, opts, "sites", fn -> CastorEDC.Sites.stream_sites(client, study_id) end)
  end

  @doc """
  The options of the study's option groups, a row per option.

  Columns: `option_group_id`, `option_group_name`, `value` (what a data
  point stores), `name` (what the user saw) and `order` (`BIGINT`, the
  option's place in its group). Takes `:dir`, as `data_points/3` does.
  """
  @spec option_groups(CastorEDC.client(), String.t(), keyword()) :: {:ok, Dux.t()} | {:error, CastorEDC.Error.t()}
  def option_groups(client, study_id, opts \\ []) do
    resource(@option_groups, opts, "option_groups", fn ->
      for group <- CastorEDC.OptionGroups.stream_option_groups(client, study_id), option <- group.options || [] do
        %{
          option_group_id: group.id,
          option_group_name: group.name,
          value: option.value,
          name: option.name,
          order: option.group_order
        }
      end
    end)
  end

  @doc """
  The study's data from a participant data export, as a `t:wide/0` map of
  lazy frames over the export's CSV files: one for the study's values, and
  one per repeating data and per survey.

  It runs `CastorEDC.Export.participant_data/3` in CSV, which takes a few
  requests however big the study is, where `data_points/3` pages through
  every value, and unzips it into `<dir>/participant_data`. DuckDB reads
  the files directly, typed by the export's own variable lists, with the
  same types per field type as `data_points/3` in the wide format, and a
  checkbox's columns are named after its options' values
  (`<variable>_<option value>`), as there. Values that don't read as their
  type are null.

  The fixed columns come first, named in snake case: `participant_id`,
  `participant_status`, `site_abbreviation` and `created_on` for the
  study; `participant_id`, `participant_status`, `created_on`,
  `instance_name` and `parent` for repeating data; `instance_id`,
  `participant_id`, `participant_status`, `created_on`, `sent_on`,
  `progress`, `completed_on`, `parent`, `survey_package_name` and
  `survey_package_id` for surveys. Their times are `TIMESTAMP`, in the
  server's time zone.

  The export writes values marked missing as -95 to -99 in numeric and
  year fields and as the dates 1 January 2995 to 2999 in date fields;
  they become nulls, and with `missing_columns: true` their codes go in a
  `<variable>_missing` column of `SMALLINT`. In other fields, and in
  checkboxes, the export leaves them empty, so the frames can't tell them
  from values never entered.

  ## Options

    * `:filters` - as for `CastorEDC.Export.participant_data/3`, such as
      `site_ids: [...]`
    * `:missing_columns` - add the missing-value columns; `false` by
      default
    * `:dir` - where to put the export's files
    * `:timeout` and `:poll_interval` - how long to wait for the export,
      and how soon to check on it first, as for
      `CastorEDC.Export.participant_data/3`
  """
  @spec participant_data(CastorEDC.client(), String.t(), keyword()) :: {:ok, wide()} | {:error, CastorEDC.Error.t()}
  def participant_data(client, study_id, opts \\ []) do
    {missing_columns, opts} = Keyword.pop(opts, :missing_columns, false)
    into = Path.join(Table.dir(opts[:dir]), "participant_data") <> "/"
    export_opts = [format: :csv, unzip: true, into: into] ++ Keyword.take(opts, [:filters, :timeout, :poll_interval])

    with {:ok, export} <- CastorEDC.Export.participant_data(client, study_id, export_opts) do
      repeating_data = Enum.map(CastorEDC.RepeatingData.stream_repeating_data(client, study_id), & &1.name)
      surveys = Enum.map(CastorEDC.Surveys.stream_surveys(client, study_id), & &1.name)

      {:ok, ParticipantData.read(export.files, repeating_data, surveys, missing_columns)}
    end
  rescue
    error in CastorEDC.Error -> {:error, error}
  end

  defp resource(columns, opts, name, rows) do
    {:ok, Table.write(rows.(), columns, Table.dir(opts[:dir]), name)}
  rescue
    error in CastorEDC.Error -> {:error, error}
  end

  defp value_type({list, of}), do: "#{list}(#{of})"
  defp value_type(type), do: Atom.to_string(type)

  defp flag(nil), do: nil
  defp flag(value), do: value not in [0, false]

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
