defmodule CastorEDC.DuxTest do
  use ExUnit.Case, async: true

  import CastorEDC.Dux.Frames

  alias CastorEDC.Dux.Study

  @moduletag :tmp_dir

  describe "data_points/3" do
    test "writes a row per value, with fixed types", %{tmp_dir: dir} do
      assert {:ok, frame} = CastorEDC.Dux.data_points(Study.client(), Study.id(), dir: dir)

      assert types(frame) == [
               {"participant_id", "VARCHAR"},
               {"site_id", "VARCHAR"},
               {"source", "VARCHAR"},
               {"instance_id", "VARCHAR"},
               {"parent_id", "VARCHAR"},
               {"field_id", "VARCHAR"},
               {"variable_name", "VARCHAR"},
               {"value", "VARCHAR"},
               {"missing", "SMALLINT"},
               {"raw_value", "VARCHAR"},
               {"updated_on", "TIMESTAMP"}
             ]

      assert File.ls!(dir) == ["data_points.parquet"]

      rows = Dux.to_rows(frame)
      assert length(rows) == 15

      assert %{"value" => "72.5", "missing" => nil, "site_id" => "site-1", "source" => "study", "instance_id" => nil} =
               value(rows, "P1", "weight")

      assert %{"value" => "2026-10-07T12:30:00", "updated_on" => ~N[2026-10-07 21:49:55.000000]} =
               value(rows, "P1", "seen")

      assert %{"value" => "0;2"} = value(rows, "P1", "family")
      assert %{"value" => nil, "missing" => 98, "raw_value" => "##USER_MISSING_98##"} = value(rows, "P2", "weight")
      assert %{"value" => nil, "missing" => nil, "raw_value" => "*encrypted*"} = value(rows, "P2", "note")

      assert %{"source" => "repeating_data", "instance_id" => "rdi-1", "parent_id" => "rd-1", "value" => "118"} =
               Enum.find(rows, &(&1["instance_id"] == "rdi-1"))
    end

    test "writes a frame per study, repeating data and survey in the wide format", %{tmp_dir: dir} do
      assert {:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
               CastorEDC.Dux.data_points(Study.client(), Study.id(), format: :wide, dir: dir)

      assert types(study) == [
               {"participant_id", "VARCHAR"},
               {"site_id", "VARCHAR"},
               {"weight", "DOUBLE"},
               {"year", "BIGINT"},
               {"visit", "DATE"},
               {"seen", "TIMESTAMP"},
               {"time", "TIME"},
               {"sex", "VARCHAR"},
               {"family_0", "BOOLEAN"},
               {"family_1", "BOOLEAN"},
               {"family_2", "BOOLEAN"},
               {"note", "VARCHAR"},
               {"bmi", "VARCHAR"}
             ]

      assert [p1, p2] = rows(study)

      assert %{
               "participant_id" => "P1",
               "site_id" => "site-1",
               "weight" => 72.5,
               "year" => 1980,
               "visit" => ~D[2026-10-07],
               "seen" => ~N[2026-10-07 12:30:00.000000],
               "sex" => "1",
               "family_0" => true,
               "family_1" => false,
               "family_2" => true,
               "note" => "fine; thanks",
               "bmi" => "22.4"
             } = p1

      assert %{"weight" => nil, "note" => nil, "family_0" => nil, "year" => nil} = p2

      assert %{"Blood pressure" => blood_pressure} = repeating_data
      assert names(blood_pressure) == ~w(participant_id site_id instance_id sys)
      assert blood_pressure |> rows(["instance_id"]) |> Enum.map(& &1["sys"]) == [118.0, 120.0]

      assert %{"GAD-7" => gad} = surveys
      assert rows(gad) == [%{"participant_id" => "P2", "site_id" => "site-2", "instance_id" => "si-1", "gad" => "3"}]

      assert dir |> File.ls!() |> Enum.sort() ==
               ~w(repeating_data_rd-1.parquet study.parquet survey_survey-1.parquet)
    end

    test "adds a column with the missing-value code of each variable when asked", %{tmp_dir: dir} do
      assert {:ok, %{study: study}} =
               CastorEDC.Dux.data_points(Study.client(), Study.id(), format: :wide, missing_columns: true, dir: dir)

      assert {"weight_missing", "SMALLINT"} in types(study)
      assert study |> rows() |> Enum.map(&{&1["weight_missing"], &1["family_missing"]}) == [{nil, nil}, {98, 95}]
      refute "family_0_missing" in names(study)
    end

    test "keeps the columns of a study without values", %{tmp_dir: dir} do
      client = Study.client(%{"/data-points/study" => Study.page("items", [])})

      assert {:ok, %{study: study, repeating_data: %{"Blood pressure" => blood_pressure}}} =
               CastorEDC.Dux.data_points(client, Study.id(), format: :wide, dir: dir)

      assert Dux.n_rows(study) == 0
      assert {"visit", "DATE"} in types(study)
      assert Dux.n_rows(blood_pressure) == 2
    end

    test "keeps to the sources asked for", %{tmp_dir: dir} do
      assert {:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
               CastorEDC.Dux.data_points(Study.client(), Study.id(), format: :wide, sources: [:survey], dir: dir)

      assert names(study) == ~w(participant_id site_id)
      assert repeating_data == %{}
      assert Map.keys(surveys) == ["GAD-7"]
    end

    test "writes to a new temporary directory by default" do
      assert {:ok, frame} = CastorEDC.Dux.data_points(Study.client(), Study.id())
      assert Dux.n_rows(frame) == 15
      assert Dux.sql_preview(frame) =~ System.tmp_dir!()
    end

    test "returns the error of a failed request", %{tmp_dir: dir} do
      client = Study.client(%{"/field" => CastorEDC.Test.json(%{"detail" => "Forbidden"}, status: 403)})

      assert {:error, %CastorEDC.Error{status: 403}} = CastorEDC.Dux.data_points(client, Study.id(), dir: dir)

      assert {:error, %CastorEDC.Error{status: 403}} =
               CastorEDC.Dux.data_points(client, Study.id(), format: :wide, dir: dir)
    end

    test "refuses an unknown format" do
      assert_raise ArgumentError, ~r/:format to be :long or :wide/, fn ->
        CastorEDC.Dux.data_points(Study.client(), Study.id(), format: :tall)
      end
    end
  end

  defp value(rows, participant, variable) do
    Enum.find(rows, &(&1["participant_id"] == participant and &1["variable_name"] == variable))
  end

  describe "participants/3" do
    test "writes a row per participant", %{tmp_dir: dir} do
      assert {:ok, frame} = CastorEDC.Dux.participants(Study.client(), Study.id(), dir: dir)

      assert {"created_on", "TIMESTAMP WITH TIME ZONE"} in types(frame)
      assert {"progress", "DOUBLE"} in types(frame)

      assert [p1, p2] = rows(frame)

      assert %{
               "participant_id" => "P1",
               "site_id" => "site-1",
               "site_name" => "Amsterdam",
               "status" => "open",
               "participant_status" => "Included",
               "progress" => 100.0,
               "locked" => false,
               "randomization_group" => 2
             } = p1

      assert p1["created_on"] == ~N[2026-10-07 19:06:33.000000]
      assert %{"participant_id" => "P2", "site_name" => nil, "participant_status" => nil, "progress" => 12.5} = p2
    end
  end

  describe "fields/3" do
    test "writes a row per field that holds values, in the study's order", %{tmp_dir: dir} do
      assert {:ok, frame} = CastorEDC.Dux.fields(Study.client(), Study.id(), dir: dir)

      assert frame |> Dux.to_columns() |> Map.fetch!("variable_name") ==
               ~w(weight year visit seen time sex family note bmi sys gad)

      assert %{
               "field_id" => "f-weight",
               "value_type" => "number",
               "context" => "study",
               "parent_name" => "Screening",
               "field_number" => 1,
               "required" => true,
               "hidden" => false,
               "units" => "kg",
               "min" => 30.0,
               "max" => 250.5
             } = frame |> Dux.to_rows() |> hd()

      assert %{"value_type" => "list(string)", "option_group_id" => "og-family"} =
               frame |> Dux.to_rows() |> Enum.find(&(&1["variable_name"] == "family"))
    end

    test "returns the error of a failed request", %{tmp_dir: dir} do
      client = Study.client(%{"/form" => CastorEDC.Test.json(%{"detail" => "Forbidden"}, status: 403)})
      assert {:error, %CastorEDC.Error{status: 403}} = CastorEDC.Dux.fields(client, Study.id(), dir: dir)
    end
  end

  describe "sites/3" do
    test "writes a row per site", %{tmp_dir: dir} do
      assert {:ok, frame} = CastorEDC.Dux.sites(Study.client(), Study.id(), dir: dir)

      assert rows(frame, ["site_id"]) == [
               %{
                 "site_id" => "site-1",
                 "name" => "Amsterdam",
                 "abbreviation" => "AMS",
                 "code" => nil,
                 "country_id" => 169,
                 "order" => 0,
                 "deleted" => nil
               },
               %{
                 "site_id" => "site-2",
                 "name" => "Utrecht",
                 "abbreviation" => nil,
                 "code" => nil,
                 "country_id" => nil,
                 "order" => nil,
                 "deleted" => true
               }
             ]
    end

    test "returns the error of a failed request", %{tmp_dir: dir} do
      client = Study.client(%{"/site" => CastorEDC.Test.json(%{"detail" => "Forbidden"}, status: 403)})
      assert {:error, %CastorEDC.Error{status: 403}} = CastorEDC.Dux.sites(client, Study.id(), dir: dir)
    end
  end

  describe "option_groups/3" do
    test "writes a row per option", %{tmp_dir: dir} do
      assert {:ok, frame} = CastorEDC.Dux.option_groups(Study.client(), Study.id(), dir: dir)

      assert rows(frame, ["value"]) == [
               %{
                 "option_group_id" => "og-sex",
                 "option_group_name" => "Sex",
                 "value" => "0",
                 "name" => "Male",
                 "order" => 0
               },
               %{
                 "option_group_id" => "og-sex",
                 "option_group_name" => "Sex",
                 "value" => "1",
                 "name" => "Female",
                 "order" => 1
               }
             ]
    end
  end
end
