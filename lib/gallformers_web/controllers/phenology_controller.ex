defmodule GallformersWeb.PhenologyController do
  @moduledoc """
  Controller actions for the public phenology explorer that aren't a
  natural fit for the LiveView — currently just the CSV export.

  Takes the same query-param shape as the LiveView (`search`, `gen`,
  `phen`, `display`) so the same filter URL maps to a corresponding
  download. Filter / brush parsing is shared with the LiveView via
  `GallformersWeb.PhenologyFilters` so they can't drift.
  """
  use GallformersWeb, :controller

  alias Gallformers.Phenology
  alias GallformersWeb.PhenologyFilters

  NimbleCSV.define(PhenologyCSV, separator: ",", escape: "\"")

  @obs_headers ~w(species phenophase lifestage viability host doy date latitude longitude source_type source_url page_url)
  @species_headers ~w(species n_obs)

  def export(conn, params) do
    filters = PhenologyFilters.from_url_params(params)

    observations =
      filters
      |> Phenology.search_observations()
      |> apply_brush(PhenologyFilters.parse_brush(params))
      |> apply_selection(PhenologyFilters.parse_selection(params))

    {filename, body} = build_csv(filters[:display_mode], observations)

    conn
    |> put_resp_content_type("text/csv")
    |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename}"))
    |> send_resp(200, body)
  end

  defp apply_brush(obs, nil), do: obs

  defp apply_brush(obs, %{doy_min: dmin, doy_max: dmax, lat_min: lmin, lat_max: lmax}) do
    Enum.filter(obs, fn o ->
      o.doy >= dmin and o.doy <= dmax and
        is_number(o.latitude) and o.latitude >= lmin and o.latitude <= lmax
    end)
  end

  # Display-only selection lens, mirroring the client-side applySelection so
  # the CSV matches the on-screen table. Modes are mutually exclusive.
  defp apply_selection(obs, nil), do: obs

  defp apply_selection(obs, {:date_range, doy, days}) do
    min = Integer.mod(doy - days, 365)
    max = Integer.mod(doy + days, 365)

    Enum.filter(obs, fn o ->
      if min <= max, do: o.doy >= min and o.doy <= max, else: o.doy >= min or o.doy <= max
    end)
  end

  defp apply_selection(obs, {:season_index, si, thr}) do
    Enum.filter(obs, fn o ->
      is_number(o.seasind) and mod_dist(o.seasind, si) <= thr
    end)
  end

  # Circular distance on the 0..1 season-index ring.
  defp mod_dist(a, b) do
    d = abs(a - b)
    min(d, 1 - d)
  end

  # The two CSV shapes match what's on screen for the respective display
  # modes; predictions / any other mode gets the full obs table by default
  # so the download is never empty.
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
