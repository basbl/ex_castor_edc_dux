defmodule CastorEDC.Dux.Study do
  @moduledoc """
  A small study the API stub serves: a visit form, a repeating data and a
  survey, with a field of most types and a few values.
  """

  import CastorEDC.Test, only: [json: 1]

  @id "study-1"

  def id, do: @id

  @doc """
  A `CastorEDC.Test` client for the study; `overrides` replaces the
  responses of the given paths (relative to the study).
  """
  def client(overrides \\ %{}) do
    routes = Map.merge(routes(), overrides)

    CastorEDC.Test.client(fn request ->
      Map.fetch!(routes, String.replace_prefix(request.url.path, "/api/study/#{@id}", ""))
    end)
  end

  def page(key, items), do: json(%{"_embedded" => %{key => items}, "page" => 1, "page_count" => 1})

  def routes do
    %{
      "/field" => page("fields", fields()),
      "/form" =>
        page("forms", [
          %{
            "id" => "form-1",
            "form_name" => "Baseline",
            "_embedded" => %{"visit" => %{"id" => "visit-1", "visit_name" => "Screening"}}
          }
        ]),
      "/repeating-data" => page("repeatingData", [%{"id" => "rd-1", "name" => "Blood pressure"}]),
      "/repeating-data/rd-1/repeating-data-form" =>
        page("repeating_data_forms", [%{"id" => "rd-form-1", "repeating_data_form_name" => "Measurement"}]),
      "/survey" => page("surveys", [%{"id" => "survey-1", "name" => "GAD-7"}]),
      "/survey/survey-1/survey-form" =>
        page("survey_forms", [%{"id" => "survey-form-1", "survey_form_name" => "Questions"}]),
      "/participant" =>
        page("participants", [
          %{
            "participant_id" => "P1",
            "status" => "open",
            "progress" => 100,
            "locked" => false,
            "archived" => false,
            "randomization_group" => 2,
            "created_on" => %{"date" => "2026-10-07 21:06:33.000000", "timezone" => "Europe/Amsterdam"},
            "participant_status" => %{"id" => "ps-1", "name" => "Included"},
            "_embedded" => %{"site" => %{"id" => "site-1", "name" => "Amsterdam"}}
          },
          %{"participant_id" => "P2", "progress" => 12.5, "_embedded" => %{"site" => %{"id" => "site-2"}}}
        ]),
      "/site" =>
        page("sites", [
          %{"id" => "site-1", "name" => "Amsterdam", "abbreviation" => "AMS", "country_id" => 169, "order" => 0},
          %{"id" => "site-2", "name" => "Utrecht", "deleted" => true}
        ]),
      "/field-optiongroup" =>
        page("fieldOptionGroups", [
          %{
            "id" => "og-sex",
            "name" => "Sex",
            "options" => [
              %{"value" => "0", "name" => "Male", "groupOrder" => 0},
              %{"value" => "1", "name" => "Female", "groupOrder" => 1}
            ]
          },
          %{"id" => "og-empty", "name" => "Empty", "options" => []}
        ]),
      "/data-points/study" =>
        page("items", [
          point("P1", "f-weight", "72.5"),
          point("P1", "f-year", "1980"),
          point("P1", "f-visit", "07-10-2026"),
          point("P1", "f-seen", "07-10-2026;12:30"),
          point("P1", "f-time", "12:30"),
          point("P1", "f-sex", "1"),
          point("P1", "f-family", "0;2"),
          point("P1", "f-note", "fine; thanks"),
          point("P1", "f-bmi", "22.4"),
          point("P2", "f-weight", "##USER_MISSING_98##"),
          point("P2", "f-note", "*encrypted*"),
          point("P2", "f-family", "##USER_MISSING_95##")
        ]),
      "/data-points/repeating-data-instance" =>
        page("items", [
          point("P1", "f-sys", "120", %{"repeating_data_instance_id" => "rdi-2"}),
          point("P1", "f-sys", "118", %{"repeating_data_instance_id" => "rdi-1"})
        ]),
      "/data-points/survey-instance" => page("items", [point("P2", "f-gad", "3", %{"survey_instance_id" => "si-1"})])
    }
  end

  defp fields do
    [
      field("f-weight", "numeric", "form-1", 1, %{
        "field_required" => 1,
        "field_hidden" => 0,
        "field_units" => "kg",
        "field_min" => 30,
        "field_max" => 250.5
      }),
      field("f-year", "year", "form-1", 2),
      field("f-visit", "date", "form-1", 3),
      field("f-seen", "datetime", "form-1", 4),
      field("f-time", "time", "form-1", 5),
      field("f-sex", "radio", "form-1", 6, %{"option_group" => options("og-sex", [{"0", "Male"}, {"1", "Female"}])}),
      field("f-family", "checkbox", "form-1", 7, %{
        "option_group" => options("og-family", [{"0", "Renal"}, {"1", "Deafness"}, {"2", "Diabetes"}])
      }),
      field("f-note", "string", "form-1", 8),
      field("f-bmi", "calculation", "form-1", 9),
      field("f-remark", "remark", "form-1", 10),
      field("f-sys", "numeric", "rd-form-1", 1),
      field("f-gad", "radio", "survey-form-1", 1, %{"option_group" => options("og-gad", [{"3", "Nearly every day"}])})
    ]
  end

  defp field(id, type, parent, number, attrs \\ %{}) do
    Map.merge(
      %{
        "id" => id,
        "field_type" => type,
        "field_variable_name" => String.replace_prefix(id, "f-", ""),
        "field_label" => "Label #{id}",
        "field_number" => number,
        "parent_id" => parent
      },
      attrs
    )
  end

  defp options(id, options) do
    %{"id" => id, "options" => for({value, name} <- options, do: %{"value" => value, "name" => name})}
  end

  defp point(participant, field, value, attrs \\ %{}) do
    Map.merge(
      %{
        "participant_id" => participant,
        "field_id" => field,
        "field_value" => value,
        "updated_on" => "2026-10-07 21:49:55"
      },
      attrs
    )
  end
end
