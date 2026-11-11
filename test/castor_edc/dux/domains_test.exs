defmodule CastorEDC.Dux.DomainsTest do
  use ExUnit.Case, async: true

  import CastorEDC.Dux.Frames

  alias CastorEDC.Dux.Study
  alias CastorEDC.Test

  @moduletag :tmp_dir

  @bom "﻿"

  @metadata_header ~s(participant_id;participant_status;site_abbreviation;randomization_id;randomization_group;randomized_on;participant_creation_date;parent_type;parent_name;visit_name;visit_number;type;name)

  @dm_csv @bom <>
            @metadata_header <>
            ~s(;sex;sex_U;sex_N;sex_N_U;weight;weight_U\n) <>
            ~s(P1;"Not Set";AMS;;;;"2026-10-30 15:48:00";;;Baseline;;Visit;Baseline;1;;Female;;72.5;\n) <>
            ~s(P1;"Not Set";AMS;;;;"2026-10-30 15:48:00";;;;;"Repeating data";"Unscheduled visit - 1";;;;;80;\n) <>
            ~s(P2;"Not Set";UTR;;;;"2026-10-31 09:00:00";;;Baseline;;Visit;Baseline;;-98;;-98;;-95\n)

  @em_csv @bom <>
            @metadata_header <>
            ~s(;seen;seen_U;at;at_U;nd_number;nd_number_U;nd_date;nd_date_U;year;year_U;family_renal;family_renal_U;family_deafness;family_deafness_U;note;note_U\n) <>
            ~s(P1;"Not Set";AMS;;;;"2026-10-30 15:48:00";;;Baseline;;Visit;Baseline;2026-05-08;;"2026-05-08 12:30:00";;7;;2026-05-01;;1980;;1;;0;;"fine; thanks";\n) <>
            ~s(P2;"Not Set";UTR;;;;"2026-10-31 09:00:00";;;Baseline;;Visit;Baseline;;-97;;;;-99;;-99;;-96;;-95;;-95;;-98\n)

  @variables_header ~s(Domain abbreviation;Domain name;Field type;SAS field type;Domain variable name;Option group name;Variable info;Option name;Option value\n)

  @metadata_variables Enum.map_join(
                        [
                          {"string", "participant_id"},
                          {"string", "participant_status"},
                          {"string", "site_abbreviation"},
                          {"numeric", "randomization_id"},
                          {"string", "randomization_group"},
                          {"datetime", "randomized_on"},
                          {"datetime", "participant_creation_date"},
                          {"string", "visit_name"},
                          {"numeric", "visit_number"},
                          {"string", "type"},
                          {"string", "name"},
                          {"string", "parent_name"},
                          {"string", "parent_type"}
                        ],
                        fn {type, name} -> ~s(Metadata;Metadata;#{type};#{type};#{name};;"Always exported."\n) end
                      )

  @dm_variables @bom <>
                  @variables_header <>
                  @metadata_variables <>
                  ~s(DM;Demographics;radio;string;sex;\n) <>
                  ~s(DM;Demographics;radio;numeric;sex_U;;"Missing data codes for sex."\n) <>
                  ~s(DM;Demographics;radio;string;sex_N;\n) <>
                  ~s(DM;Demographics;radio;numeric;sex_N_U;;"Missing data codes for sex_N."\n) <>
                  ~s(DM;Demographics;numeric;numeric;weight;\n) <>
                  ~s(DM;Demographics;numeric;numeric;weight_U;;"Missing data codes for weight."\n)

  @em_variables @bom <>
                  @variables_header <>
                  @metadata_variables <>
                  ~s(EM;More;date;YYMMDD10;seen;\n) <>
                  ~s(EM;More;date;numeric;seen_U;;"Missing data codes for seen."\n) <>
                  ~s(EM;More;datetime;datetime;at;\n) <>
                  ~s(EM;More;datetime;numeric;at_U;;"Missing data codes for at."\n) <>
                  ~s(EM;More;numberdate;numeric;nd_number;\n) <>
                  ~s(EM;More;numberdate;numeric;nd_number_U;;"Missing data codes for nd_number."\n) <>
                  ~s(EM;More;numberdate;YYMMDD10;nd_date;\n) <>
                  ~s(EM;More;numberdate;numeric;nd_date_U;;"Missing data codes for nd_date."\n) <>
                  ~s(EM;More;year;numeric;year;\n) <>
                  ~s(EM;More;year;numeric;year_U;;"Missing data codes for year."\n) <>
                  ~s(EM;More;checkbox;numeric;family_renal;Family;"This column, related to the family domain variable, has been added as checkbox fields are split into separate columns.";"Renal disease";0\n) <>
                  ~s(EM;More;checkbox;numeric;family_renal_U;;"Missing data codes for family_renal.";;\n) <>
                  ~s(EM;More;checkbox;numeric;family_deafness;Family;"This column, related to the family domain variable, has been added as checkbox fields are split into separate columns.";Deafness;1\n) <>
                  ~s(EM;More;checkbox;numeric;family_deafness_U;;"Missing data codes for family_deafness.";;\n) <>
                  ~s(EM;More;textarea;string;note;\n) <>
                  ~s(EM;More;textarea;numeric;note_U;;"Missing data codes for note."\n)

  @files [
    {"DM.csv", @dm_csv},
    {"EM.csv", @em_csv},
    {"DM_variablelist.csv", @dm_variables},
    {"EM_variablelist.csv", @em_variables},
    {"domain_mapping.csv", @bom <> "Domain abbreviation;Domain name\nDM;Demographics\nEM;More\n"},
    {"field_options.csv", @bom <> "Option group name;Option name;Option value\nSex;Female;1\n"}
  ]

  # An export with a variable list for every domain, its missing values in
  # their own columns and its dates as text, as Castor EDC can write it too.
  @same_column_csv @bom <>
                     @metadata_header <>
                     ~s(;seen;at;time;partly;nd_number;nd_date;family_renal\n) <>
                     ~s(P1;"Not Set";AMS;;;;"2026-10-30 15:48:00";;;Baseline;;Visit;Baseline;2026-05-08;"2026-05-08 12:30";12:30;2026-05-01;7;2026-05-01;1\n) <>
                     ~s(P2;"Not Set";UTR;;;;"2026-10-31 09:00:00";;;Baseline;;Visit;Baseline;01-01-2997;"01-01-2999 00:00:36";00:00:35;01-01-2998;-99;01-01-2999;-95\n)

  @combined_variables @bom <>
                        @variables_header <>
                        @metadata_variables <>
                        ~s(SC;Same;date;string;seen;\n) <>
                        ~s(SC;Same;datetime;string;at;\n) <>
                        ~s(SC;Same;time;string;time;\n) <>
                        ~s(SC;Same;date_partial;string;partly;\n) <>
                        ~s(SC;Same;numberdate;numeric;nd_number;\n) <>
                        ~s(SC;Same;numberdate;string;nd_date;\n) <>
                        ~s(SC;Same;checkbox;numeric;family_renal;Family;"This column, related to the family domain variable, has been added as checkbox fields are split into separate columns.";"Renal disease";0\n) <>
                        ~s(OT;Other;numeric;numeric;weight;\n)

  @same_column_files [
    {"SC.csv", @same_column_csv},
    {"OT.csv", @bom <> @metadata_header <> ";weight\n"},
    {"variablelist.csv", @combined_variables},
    {"domain_mapping.csv", @bom <> "Domain abbreviation;Domain name\nSC;Same\nOT;Other\n"}
  ]

  defp export(files \\ @files), do: %CastorEDC.Export{id: "export-1", type: :participant_data, format: :csv, files: files}

  describe "domains/3" do
    test "gives a frame per domain, typed by its variable list", %{tmp_dir: dir} do
      assert {:ok, %{"DM" => dm, "EM" => em}} =
               CastorEDC.Dux.domains(no_export_client(), Study.id(), from: export(), dir: dir)

      assert names(dm) ==
               ~w(participant_id participant_status site_abbreviation randomization_id randomization_group randomized_on created_on parent_type parent_name visit_name visit_number type name sex weight)

      types = Map.new(types(dm))

      assert %{
               "randomization_id" => "VARCHAR",
               "randomized_on" => "TIMESTAMP",
               "created_on" => "TIMESTAMP",
               "visit_number" => "BIGINT",
               "sex" => "VARCHAR",
               "weight" => "DOUBLE"
             } = types

      # Sorted by type, a participant's repeating data come before their visits.
      assert [p1_repeating, p1_visit, p2] = rows(dm, ["participant_id", "type"])

      assert %{
               "participant_id" => "P1",
               "created_on" => ~N[2026-10-30 15:48:00.000000],
               "type" => "Visit",
               "name" => "Baseline",
               "sex" => "1",
               "weight" => 72.5
             } = p1_visit

      assert %{"type" => "Repeating data", "name" => "Unscheduled visit - 1", "sex" => nil, "weight" => 80.0} =
               p1_repeating

      assert %{"participant_id" => "P2", "sex" => nil, "weight" => nil} = p2

      assert %{
               "seen" => "DATE",
               "at" => "TIMESTAMP",
               "nd_number" => "DOUBLE",
               "nd_date" => "DATE",
               "year" => "BIGINT",
               "family_0" => "BOOLEAN",
               "family_1" => "BOOLEAN",
               "note" => "VARCHAR"
             } = Map.new(types(em))

      assert [
               %{
                 "seen" => ~D[2026-05-08],
                 "at" => ~N[2026-05-08 12:30:00.000000],
                 "nd_number" => 7.0,
                 "nd_date" => ~D[2026-05-01],
                 "year" => 1980,
                 "family_0" => true,
                 "family_1" => false,
                 "note" => "fine; thanks"
               },
               %{"seen" => nil, "nd_number" => nil, "nd_date" => nil, "year" => nil, "family_0" => nil, "note" => nil}
             ] = rows(em)
    end

    test "adds the codes of missing values and the options' names when asked", %{tmp_dir: dir} do
      assert {:ok, %{"DM" => dm, "EM" => em}} =
               CastorEDC.Dux.domains(no_export_client(), Study.id(),
                 from: export(),
                 missing_columns: true,
                 labels: true,
                 dir: dir
               )

      assert Enum.take(names(dm), -5) == ~w(sex sex_missing sex_label weight weight_missing)
      assert {"sex_missing", "SMALLINT"} in types(dm)

      visits = dm |> rows() |> Enum.filter(&(&1["type"] == "Visit"))

      assert Enum.map(visits, &{&1["sex_label"], &1["sex_missing"], &1["weight_missing"]}) == [
               {"Female", nil, nil},
               {nil, 98, 95}
             ]

      assert %{
               "seen_missing" => 97,
               "nd_number_missing" => 99,
               "nd_date_missing" => 99,
               "year_missing" => 96,
               "family_missing" => 95,
               "note_missing" => 98
             } = em |> rows() |> List.last()

      refute "family_1_missing" in names(em)
    end

    test "reads missing values written in their own columns, and a variable list for every domain", %{tmp_dir: dir} do
      assert {:ok, %{"SC" => sc, "OT" => ot}} =
               CastorEDC.Dux.domains(no_export_client(), Study.id(),
                 from: export(@same_column_files),
                 missing_columns: true,
                 dir: dir
               )

      assert %{
               "seen" => "DATE",
               "at" => "TIMESTAMP",
               "time" => "TIME",
               "partly" => "VARCHAR",
               "nd_number" => "DOUBLE",
               "nd_date" => "DATE",
               "family_0" => "BOOLEAN"
             } = Map.new(types(sc))

      assert [
               %{
                 "seen" => ~D[2026-05-08],
                 "at" => ~N[2026-05-08 12:30:00.000000],
                 "time" => ~T[12:30:00.000000],
                 "partly" => "2026-05-01",
                 "nd_number" => 7.0,
                 "nd_date" => ~D[2026-05-01],
                 "family_0" => true,
                 "seen_missing" => nil
               },
               %{
                 "seen" => nil,
                 "seen_missing" => 97,
                 "at" => nil,
                 "at_missing" => 96,
                 "time" => nil,
                 "time_missing" => 95,
                 "partly" => nil,
                 "partly_missing" => 98,
                 "nd_number" => nil,
                 "nd_number_missing" => 99,
                 "nd_date" => nil,
                 "nd_date_missing" => 99,
                 "family_0" => nil,
                 "family_missing" => 95
               }
             ] = rows(sc)

      assert {"weight", "DOUBLE"} in types(ot)
      assert Dux.to_rows(ot) == []
    end

    test "leaves the options' names out unless asked", %{tmp_dir: dir} do
      assert {:ok, %{"DM" => dm}} = CastorEDC.Dux.domains(no_export_client(), Study.id(), from: export(), dir: dir)
      refute "sex_label" in names(dm)
    end

    test "queues a grouped CSV export, with the options' names when asked", %{tmp_dir: dir} do
      assert {:ok, %{"DM" => _dm}} =
               CastorEDC.Dux.domains(client(), Study.id(),
                 labels: true,
                 filters: [site_ids: ["site-1"]],
                 poll_interval: 0,
                 dir: dir
               )

      queue = Test.requested()
      assert %{"exports" => %{"participant_data" => [request]}} = queue.body |> IO.iodata_to_binary() |> JSON.decode!()

      assert request == %{
               "format" => "csv",
               "filters" => %{"site_ids" => ["site-1"]},
               "options" => %{"grouped" => true, "export_coded_options_as" => "values_and_names"}
             }

      assert dir |> Path.join("domains") |> File.ls!() |> length() == 6
    end

    test "refuses an export that isn't grouped, and participant_data/3 one that is", %{tmp_dir: dir} do
      plain = export([{"Study_export_1.csv", "\"Participant Id\"\nP1\n"}])

      assert_raise ArgumentError, ~r/isn't grouped by domain/, fn ->
        CastorEDC.Dux.domains(no_export_client(), Study.id(), from: plain, dir: dir)
      end

      assert_raise ArgumentError, ~r/grouped by domain; read it with CastorEDC.Dux.domains\/3/, fn ->
        CastorEDC.Dux.participant_data(no_export_client(), Study.id(), from: export(), dir: dir)
      end
    end

    test "returns the error of a failed export", %{tmp_dir: dir} do
      client = client(%{"/export" => Test.json(%{"description" => "No visible participants found"}, status: 403)})

      assert {:error, %CastorEDC.Error{status: 403}} =
               CastorEDC.Dux.domains(client, Study.id(), poll_interval: 0, dir: dir)
    end
  end

  # A client whose exports fail, to show an export given as :from is read
  # without running another.
  defp no_export_client do
    client(%{"/export" => Test.json(%{"detail" => "No exports here"}, status: 500)})
  end

  defp client(overrides \\ %{}) do
    routes =
      Map.merge(
        %{
          "/export" => Test.json(%{"queued_exports" => ["export-1"]}, status: 201),
          "/export/export-1/download" =>
            Req.Response.new(status: 200, body: zip(@files), headers: %{"content-type" => ["application/zip"]})
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
