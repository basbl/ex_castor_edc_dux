defmodule CastorEDC.Dux.TableTest do
  use ExUnit.Case, async: true

  alias CastorEDC.Dux.Table
  alias CastorEDC.MissingValue
  alias CastorEDC.PartialDate

  test "writes every kind of decoded value as text" do
    assert Table.text(nil) == nil
    assert Table.text(MissingValue.new(97)) == nil
    assert Table.text(:encrypted) == nil
    assert Table.text("text") == "text"
    assert Table.text(4.5) == "4.5"
    assert Table.text(true) == "true"
    assert Table.text(~D[2026-10-07]) == "2026-10-07"
    assert Table.text(~T[12:30:00]) == "12:30:00"
    assert Table.text(~N[2026-10-07 12:30:00]) == "2026-10-07T12:30:00"
    assert Table.text(%PartialDate{year: 2020, month: 5}) == "2020-05"
    assert Table.text({:upload, "scan.pdf"}) == "scan.pdf"
    assert Table.text({5, ~D[2026-10-07]}) == "5;2026-10-07"
    assert Table.text({nil, ~D[2026-10-07]}) == ";2026-10-07"
    assert Table.text(["0", "2"]) == "0;2"

    assert JSON.decode!(Table.text(%{0 => %{0 => "5", 1 => MissingValue.new(95)}})) ==
             %{"0" => %{"0" => "5", "1" => "##USER_MISSING_95##"}}
  end

  test "writes values as JSON DuckDB reads as the column's type" do
    assert Table.json(3, "DOUBLE") === 3.0
    assert Table.json(3, "SMALLINT") == 3
    assert Table.json(~T[12:30:00], "TIME") == "12:30:00"
    assert Table.json(~U[2026-10-07 12:30:00Z], "TIMESTAMPTZ") == "2026-10-07T12:30:00Z"
    assert Table.json(false, "BOOLEAN") == false
    assert Table.json(MissingValue.new(95), "BOOLEAN") == nil
    assert Table.json("not a number", "DOUBLE") == nil
  end

  test "quotes identifiers and literals" do
    assert Table.identifier(~s(a"b)) == ~s("a""b")
    assert Table.literal("it's") == "'it''s'"
  end
end
