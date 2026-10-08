defmodule CastorEDC.Dux.ParticipantDataTest do
  use ExUnit.Case, async: true

  import CastorEDC.Dux.Frames

  alias CastorEDC.Dux.ParticipantData
  alias CastorEDC.Dux.Study
  alias CastorEDC.Test

  @moduletag :tmp_dir

  @bom "\uFEFF"

  @study_csv @bom <>
               ~s("Participant Id";"Participant Status";"Site Abbreviation";"Participant Creation Date";weight;year;visit;seen;time;sex;"family#Renal disease";family#Deafness;note\n) <>
               ~s(P1;"Not Set";AMS;"07-10-2026 21:06:33";72.5;1980;07-10-2026;"07-10-2026 12:30";12:30;1;1;0;"fine; thanks"\n) <>
               ~s(P2;"Not Set";UTR;"08-10-2026 10:00:33";-98;-95;01-01-2997;;;;0;0;\n)

  @repeating_csv @bom <>
                   ~s("Participant Id";"Participant Status";"Repeating Data Creation Date";"Repeating data Name Custom";"Repeating data Parent";sys\n) <>
                   ~s(P1;"Not Set";"07-10-2026 21:46:26";"Blood pressure - 1";"No parent";120\n)

  @survey_csv @bom <>
                ~s("Survey Instance Id";"Castor Participant ID";"Castor Participant Status";"Survey Creation Date";"Survey Sent Date";"Survey Progress";"Survey Completed On";"Survey Parent";"Survey Package Name";"Survey Package Id";gad\n) <>
                ~s(si-1;P2;"Not Set";"07-10-2026 21:50:13";;100;"07-10-2026 22:00:00";"No parent";Anxiety;pkg-1;3\n)

  @empty_survey_csv @bom <>
                      ~s("Survey Instance Id";"Castor Participant ID";"Castor Participant Status";"Survey Creation Date";"Survey Sent Date";"Survey Progress";"Survey Completed On";"Survey Parent";"Survey Package Name";"Survey Package Id";sf1\n)

  @variables ~s("Visit name";"Form name";"Form number";"Field number";"Exported field type";"Original field type";"Variable name";"Field label";"Optiongroup name"\n)

  @study_variables @bom <>
                     @variables <>
                     ~s(V;F;1;1;numeric;numeric;weight;Weight;\n) <>
                     ~s(V;F;1;2;year;year;year;Year;\n) <>
                     ~s(V;F;1;3;date;date;visit;Visit;\n) <>
                     ~s(V;F;1;4;datetime;datetime;seen;Seen;\n) <>
                     ~s(V;F;1;5;time;time;time;Time;\n) <>
                     ~s(V;F;1;6;radio;radio;sex;Sex;Sex\n) <>
                     ~s(V;F;1;7;checkbox;checkbox;"family#Renal disease";Family;Family\n) <>
                     ~s(V;F;1;7;checkbox;checkbox;family#Deafness;Family;Family\n) <>
                     ~s(V;F;1;8;string;string;note;Note;\n)

  @report_variables @bom <> @variables <> ~s("Blood pressure";M;1;1;numeric;numeric;sys;Systolic;\n)
  @survey_variables @bom <> @variables <> ~s|"GAD-7 (short)";Q;1;1;radio;radio;gad;GAD;\n|

  @options @bom <>
             ~s("Option group name";"Option name";"Option value"\n) <>
             ~s(Sex;Male;0\nSex;Female;1\nFamily;"Renal disease";0\nFamily;Deafness;1\n)

  @files [
    {"Study_export_20261008.csv", @study_csv},
    {"Study_Blood_pressure_export_20261008.csv", @repeating_csv},
    {"Study_GAD-7_short_export_20261008.csv", @survey_csv},
    {"Study_Unknown_survey_export_20261008.csv", @empty_survey_csv},
    {"study_variablelist.csv", @study_variables},
    {"report_variablelist.csv", @report_variables},
    {"survey_variablelist.csv", @survey_variables},
    {"field_options.csv", @options}
  ]

  describe "participant_data/3" do
    test "reads the export's files into typed frames", %{tmp_dir: dir} do
      assert {:ok, %{study: study, repeating_data: repeating_data, surveys: surveys}} =
               CastorEDC.Dux.participant_data(client(), Study.id(), poll_interval: 0, dir: dir)

      assert types(study) == [
               {"participant_id", "VARCHAR"},
               {"participant_status", "VARCHAR"},
               {"site_abbreviation", "VARCHAR"},
               {"created_on", "TIMESTAMP"},
               {"weight", "DOUBLE"},
               {"year", "BIGINT"},
               {"visit", "DATE"},
               {"seen", "TIMESTAMP"},
               {"time", "TIME"},
               {"sex", "VARCHAR"},
               {"family_0", "BOOLEAN"},
               {"family_1", "BOOLEAN"},
               {"note", "VARCHAR"}
             ]

      assert [p1, p2] = rows(study)

      assert %{
               "participant_id" => "P1",
               "created_on" => ~N[2026-10-07 21:06:33.000000],
               "weight" => 72.5,
               "year" => 1980,
               "visit" => ~D[2026-10-07],
               "seen" => ~N[2026-10-07 12:30:00.000000],
               "sex" => "1",
               "family_0" => true,
               "family_1" => false,
               "note" => "fine; thanks"
             } = p1

      assert %{"weight" => nil, "year" => nil, "visit" => nil, "seen" => nil, "sex" => nil, "note" => nil} = p2

      assert %{"Blood pressure" => blood_pressure} = repeating_data

      assert rows(blood_pressure) == [
               %{
                 "participant_id" => "P1",
                 "participant_status" => "Not Set",
                 "created_on" => ~N[2026-10-07 21:46:26.000000],
                 "instance_name" => "Blood pressure - 1",
                 "parent" => "No parent",
                 "sys" => 120.0
               }
             ]

      assert %{"GAD-7 (short)" => gad, "Unknown_survey" => unknown} = surveys

      assert [
               %{
                 "instance_id" => "si-1",
                 "progress" => 100,
                 "completed_on" => ~N[2026-10-07 22:00:00.000000],
                 "gad" => "3"
               }
             ] =
               rows(gad)

      assert Dux.n_rows(unknown) == 0
      assert {"sf1", "VARCHAR"} in types(unknown)
      assert dir |> Path.join("participant_data") |> File.ls!() |> length() == 8
    end

    test "adds the codes of missing values when asked", %{tmp_dir: dir} do
      assert {:ok, %{study: study}} =
               CastorEDC.Dux.participant_data(client(), Study.id(), poll_interval: 0, missing_columns: true, dir: dir)

      assert study |> rows() |> Enum.map(&{&1["weight_missing"], &1["year_missing"], &1["visit_missing"]}) ==
               [{nil, nil, nil}, {98, 95, 97}]

      assert {"visit_missing", "SMALLINT"} in types(study)
      refute "sex_missing" in names(study)
    end

    test "queues a CSV export with the filters given", %{tmp_dir: dir} do
      assert {:ok, _frames} =
               CastorEDC.Dux.participant_data(client(), Study.id(),
                 poll_interval: 0,
                 filters: [site_ids: ["site-1"]],
                 dir: dir
               )

      queue = Test.requested()

      assert queue.body |> IO.iodata_to_binary() |> JSON.decode!() == %{
               "exports" => %{"participant_data" => [%{"format" => "csv", "filters" => %{"site_ids" => ["site-1"]}}]}
             }
    end

    test "returns the error of a failed export", %{tmp_dir: dir} do
      client = client(%{"/export" => Test.json(%{"description" => "No visible participants found"}, status: 403)})

      assert {:error, %CastorEDC.Error{status: 403}} =
               CastorEDC.Dux.participant_data(client, Study.id(), poll_interval: 0, dir: dir)
    end

    test "leaves out a value it can't read", %{tmp_dir: dir} do
      File.write!(Path.join(dir, "Study_export_1.csv"), "\"Participant Id\";weight\nP1;heavy\n")
      File.write!(Path.join(dir, "study_variablelist.csv"), @variables <> "V;F;1;1;numeric;numeric;weight;W;\n")

      assert %{study: study} = dir |> File.ls!() |> Enum.map(&Path.join(dir, &1)) |> ParticipantData.read([], [], false)
      assert rows(study) == [%{"participant_id" => "P1", "weight" => nil}]
    end
  end

  defp client(overrides \\ %{}) do
    routes =
      Map.merge(
        %{
          "/export" => Test.json(%{"queued_exports" => ["export-1"]}, status: 201),
          "/export/export-1/download" =>
            Req.Response.new(status: 200, body: zip(@files), headers: %{"content-type" => ["application/zip"]}),
          "/repeating-data" => Study.page("repeatingData", [%{"id" => "rd-1", "name" => "Blood pressure"}]),
          "/survey" =>
            Study.page("surveys", [%{"id" => "s-1", "name" => "GAD-7 (short)"}, %{"id" => "s-2", "name" => "GAD-7"}])
        },
        overrides
      )

    Test.client(fn request ->
      path = String.replace_prefix(request.url.path, "/api/study/#{Study.id()}", "")

      if path == "/export" and request.method == :get,
        do: export_list(),
        else: Map.fetch!(routes, path)
    end)
  end

  defp export_list do
    now = DateTime.utc_now() |> DateTime.to_naive() |> NaiveDateTime.to_string()
    later = DateTime.utc_now() |> DateTime.shift(week: 1) |> DateTime.to_naive() |> NaiveDateTime.to_string()

    Test.json(%{
      "_embedded" => %{
        "items" => [
          %{
            "id" => "export-1",
            "status" => "ready",
            "export_name" => "participant_data",
            "export_type" => "csv",
            "created_on" => %{"date" => now, "timezone_type" => 3, "timezone" => "UTC"},
            "expires_on" => %{"date" => later, "timezone_type" => 3, "timezone" => "UTC"},
            "file_name" => "Study_participant_data.zip"
          }
        ]
      },
      "page" => 1,
      "page_count" => 1
    })
  end

  defp zip(files) do
    {:ok, {_name, zip}} =
      :zip.create(~c"export.zip", for({name, contents} <- files, do: {String.to_charlist(name), contents}), [:memory])

    zip
  end
end
