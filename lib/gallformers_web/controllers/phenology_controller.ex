defmodule GallformersWeb.PhenologyController do
  @moduledoc """
  Controller actions for the public phenology explorer that aren't a
  natural fit for the LiveView — currently just the CSV export.

  Takes the same query-param shape as the LiveView (`search`, `gen`,
  `phen`, `display`) so the same filter URL maps to a corresponding
  download.
  """
  use GallformersWeb, :controller

  alias Gallformers.Phenology

  NimbleCSV.define(PhenologyCSV, separator: ",", escape: "\"")

  @obs_headers ~w(species phenophase lifestage viability host doy date latitude longitude source_type source_url page_url)
  @species_headers ~w(species n_obs)

  def export(conn, params) do
    filters = parse_filters(params)
    observations = Phenology.search_observations(filters)

    {filename, body} = build_csv(filters[:display_mode], observations)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, body)
  end

  # Mirrors the LiveView's URL-param semantics (defaults applied when keys
  # are absent; explicit empties honored). Keeps the LV and CSV in sync so
  # the user gets exactly what they see on screen.
  defp parse_filters(params) do
    %{
      search: parse_search(params),
      generation: parse_generation(params["gen"]),
      phenophases: parse_phenophases(params),
      display_mode: parse_display_mode(params["display"])
    }
  end

  defp parse_search(params) do
    case Map.fetch(params, "search") do
      :error -> ["Dryocosmus quercuspalustris"]
      {:ok, nil} -> ["Dryocosmus quercuspalustris"]
      {:ok, ""} -> nil
      {:ok, value} -> parse_search_value(value)
    end
  end

  defp parse_search_value(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> nil
      list -> list
    end
  end

  defp parse_generation("sexgen"), do: :sexgen
  defp parse_generation("agamic"), do: :agamic
  defp parse_generation(_), do: :all

  defp parse_phenophases(params) do
    case Map.fetch(params, "phen") do
      :error -> ~w(maturing perimature Free-living)
      {:ok, nil} -> ~w(maturing perimature Free-living)
      {:ok, value} -> parse_phenophases_value(value)
    end
  end

  defp parse_phenophases_value(""), do: []

  defp parse_phenophases_value(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_phenophases_value(_), do: []

  defp parse_display_mode("table"), do: :data_table
  defp parse_display_mode("species"), do: :species_list
  defp parse_display_mode(_), do: :chart

  # The two CSV shapes match what's on screen for the respective display
  # modes; the chart view (and any other display mode) gets the full obs
  # table by default so the download is never empty.
  defp build_csv(:species_list, observations) do
    rows =
      observations
      |> Enum.group_by(&{&1.species_id, &1.species_name})
      |> Enum.map(fn {{_, name}, obs} -> [name, length(obs)] end)
      |> Enum.sort_by(&Enum.at(&1, 0))

    body = encode([@species_headers | rows])
    {"phenology_species.csv", body}
  end

  defp build_csv(_data_table_or_other, observations) do
    rows = Enum.map(observations, &obs_to_row/1)
    body = encode([@obs_headers | rows])
    {"phenology_observations.csv", body}
  end

  defp obs_to_row(o) do
    [
      o.species_name,
      o.phenophase || "",
      o.lifestage || "",
      o.viability || "",
      o.host_species_name || "",
      to_string(o.doy),
      format_date(o.date),
      format_number(o.latitude),
      format_number(o.longitude),
      o.source_type || "",
      o.source_url || "",
      o.page_url || ""
    ]
  end

  defp encode(rows), do: rows |> PhenologyCSV.dump_to_iodata() |> IO.iodata_to_binary()

  defp format_date(%Date{} = d), do: Date.to_iso8601(d)
  defp format_date(_), do: ""

  defp format_number(n) when is_float(n), do: :erlang.float_to_binary(n, [:compact, decimals: 4])
  defp format_number(n) when is_number(n), do: to_string(n)
  defp format_number(_), do: ""
end
