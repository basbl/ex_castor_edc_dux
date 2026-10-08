defmodule CastorEDC.Dux.Frames do
  @moduledoc """
  Reading frames back in tests.
  """

  @doc "The frame's columns and their DuckDB types, in order."
  def types(frame) do
    ("DESCRIBE " <> Dux.sql_preview(frame))
    |> Dux.from_query()
    |> Dux.to_rows()
    |> Enum.map(&{&1["column_name"], &1["column_type"]})
  end

  @doc "The frame's column names, in order."
  def names(frame), do: frame |> types() |> Enum.map(&elem(&1, 0))

  @doc "The frame's rows, sorted by the given columns."
  def rows(frame, by \\ ["participant_id"]) do
    frame |> Dux.to_rows() |> Enum.sort_by(fn row -> Enum.map(by, &row[&1]) end)
  end
end
