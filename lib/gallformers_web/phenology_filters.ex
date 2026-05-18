defmodule GallformersWeb.PhenologyFilters do
  @moduledoc """
  Shared filter parsing for `/phenology`.

  Both the LiveView (`GallformersWeb.PhenologyLive`) and the CSV export
  controller (`GallformersWeb.PhenologyController.export/2`) take the
  same filter URL params and need to apply the same defaults / validation
  rules. Putting that logic here ensures the on-screen view and downloaded
  CSV can't drift apart — if we change the default search from
  "Dryocosmus quercuspalustris" to something else, there's one place
  to change.

  Two parsing entry points with different "absent key" semantics:

  - `from_url_params/1` — for URL params on initial mount or controller
    requests. Absent key means "use the default for this filter";
    present-but-empty key means "user has explicitly cleared this filter"
    (e.g. `?search=` → no search; `?phen=` → strict empty).

  - `from_form_params/1` — for LV form change events. Absent key means
    "user has cleared this filter" (e.g. all phenophase checkboxes off →
    browsers omit the `phenophases` key entirely).
  """

  alias Gallformers.Species

  @default_search ["Dryocosmus quercuspalustris"]
  @default_phenophases ~w(maturing perimature Free-living)
  @default_target_lat 42.0

  # Phenophases offered in the explorer UI, in display order. Validates
  # incoming param values. `senescent` is intentionally omitted.
  @explorer_phenophases ~w(oviscar developing dormant maturing Free-living perimature)

  @doc "The explorer's phenophase vocabulary, in display order."
  def explorer_phenophases, do: @explorer_phenophases

  @doc "Default search filter (a list of name fragments)."
  def default_search, do: @default_search

  @doc "Default phenophase filter."
  def default_phenophases, do: @default_phenophases

  @doc "Default target latitude for predictions."
  def default_target_lat, do: @default_target_lat

  @doc """
  Parse filters from URL query params. Used by both LV mount and the
  CSV export controller.
  """
  def from_url_params(params) when is_map(params) do
    %{
      search: parse_search_url(params),
      generation: parse_generation(params["gen"]),
      phenophases: parse_phenophases_url(params),
      display_mode: parse_display_mode(params["display"]),
      target_lat: parse_target_lat(params["lat"])
    }
  end

  @doc """
  Parse filters from a Phoenix LV form-change params map. Differs from
  `from_url_params/1` in how it treats absent keys (form sends nothing
  for unchecked checkbox groups, which we interpret as "user cleared
  the filter" rather than "use default").
  """
  def from_form_params(params) when is_map(params) do
    %{
      search: parse_search_value(params["search"]),
      generation: parse_generation(params["generation"]),
      phenophases: parse_phenophases_form(params["phenophases"]),
      display_mode: parse_display_mode(params["display"]),
      target_lat: parse_target_lat(params["target_lat"])
    }
  end

  @doc """
  Reverse of `from_url_params/1`. Returns a keyword list suitable for
  Phoenix verified-route interpolation. Emits explicit empty values
  when the user has cleared a filter that has a non-empty default, so
  reload preserves the cleared state instead of restoring the default.
  """
  def to_query(filters) when is_map(filters) do
    []
    |> maybe_put_search(filters[:search])
    |> maybe_put_gen(filters[:generation])
    |> maybe_put_phen(filters[:phenophases])
    |> maybe_put_display(filters[:display_mode])
    |> maybe_put_lat(filters[:target_lat])
  end

  @doc """
  Parse brush-selection bounds from URL params (`doy_min`, `doy_max`,
  `lat_min`, `lat_max`). Returns a map or `nil`. All four params must
  be parseable for the brush to apply.
  """
  def parse_brush(params) when is_map(params) do
    with {:ok, dmin} <- to_number(params["doy_min"]),
         {:ok, dmax} <- to_number(params["doy_max"]),
         {:ok, lmin} <- to_number(params["lat_min"]),
         {:ok, lmax} <- to_number(params["lat_max"]) do
      %{doy_min: trunc(dmin), doy_max: trunc(dmax), lat_min: lmin, lat_max: lmax}
    else
      _ -> nil
    end
  end

  @doc """
  Encode a brush map as a keyword list of URL params. Returns `[]` for
  `nil`. Pairs with `parse_brush/1`.
  """
  def brush_query(nil), do: []

  def brush_query(%{doy_min: dmin, doy_max: dmax, lat_min: lmin, lat_max: lmax}) do
    [
      doy_min: to_string(dmin),
      doy_max: to_string(dmax),
      lat_min: to_string(lmin),
      lat_max: to_string(lmax)
    ]
  end

  # ----------------------------------------------------------------------
  # Search
  # ----------------------------------------------------------------------

  defp parse_search_url(params) do
    case Map.fetch(params, "search") do
      {:ok, value} ->
        parse_search_value(value)

      :error ->
        species_id_to_search(params["species_id"]) || @default_search
    end
  end

  defp parse_search_value(nil), do: nil
  defp parse_search_value(""), do: nil

  defp parse_search_value(value) when is_binary(value) do
    terms =
      value
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case terms do
      [] -> nil
      list -> list
    end
  end

  defp parse_search_value(_), do: nil

  defp species_id_to_search(nil), do: nil
  defp species_id_to_search(""), do: nil

  defp species_id_to_search(value) when is_binary(value) do
    case Integer.parse(value) do
      {id, ""} ->
        case Species.get_species(id) do
          %{name: name} when is_binary(name) -> [name]
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp species_id_to_search(_), do: nil

  # ----------------------------------------------------------------------
  # Generation
  # ----------------------------------------------------------------------

  defp parse_generation(value) when value in ["sexgen", "agamic", "all"],
    do: String.to_existing_atom(value)

  defp parse_generation(_), do: :all

  # ----------------------------------------------------------------------
  # Phenophases
  # ----------------------------------------------------------------------

  defp parse_phenophases_url(params) do
    case Map.fetch(params, "phen") do
      :error -> @default_phenophases
      {:ok, nil} -> @default_phenophases
      {:ok, value} -> parse_phenophases_value(value)
    end
  end

  defp parse_phenophases_form(nil), do: []
  defp parse_phenophases_form(value), do: parse_phenophases_value(value)

  defp parse_phenophases_value(""), do: []

  defp parse_phenophases_value(value) when is_list(value) do
    Enum.filter(value, &(&1 in @explorer_phenophases))
  end

  defp parse_phenophases_value(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @explorer_phenophases))
  end

  defp parse_phenophases_value(_), do: []

  # ----------------------------------------------------------------------
  # Display mode
  # ----------------------------------------------------------------------

  # `chart` is accepted for back-compat with older URLs but treated as
  # `predictions` since the chart is no longer toggleable.
  defp parse_display_mode("table"), do: :data_table
  defp parse_display_mode("species"), do: :species_list
  defp parse_display_mode(_), do: :predictions

  # ----------------------------------------------------------------------
  # Target latitude
  # ----------------------------------------------------------------------

  defp parse_target_lat(nil), do: @default_target_lat
  defp parse_target_lat(""), do: @default_target_lat

  defp parse_target_lat(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, _} when f >= -90.0 and f <= 90.0 -> f
      _ -> @default_target_lat
    end
  end

  defp parse_target_lat(value) when is_number(value) and value >= -90 and value <= 90,
    do: value * 1.0

  defp parse_target_lat(_), do: @default_target_lat

  # ----------------------------------------------------------------------
  # URL emit (to_query helpers)
  # ----------------------------------------------------------------------

  defp maybe_put_search(query, terms) when is_list(terms) and terms != [] do
    if terms == @default_search,
      do: query,
      else: query ++ [search: Enum.join(terms, ",")]
  end

  defp maybe_put_search(query, _empty_or_nil),
    do: query ++ [search: ""]

  defp maybe_put_gen(query, :all), do: query

  defp maybe_put_gen(query, gen) when gen in [:sexgen, :agamic],
    do: query ++ [gen: Atom.to_string(gen)]

  defp maybe_put_gen(query, _), do: query

  defp maybe_put_phen(query, phens) when is_list(phens) and phens != [] do
    if phens == @default_phenophases,
      do: query,
      else: query ++ [phen: Enum.join(phens, ",")]
  end

  defp maybe_put_phen(query, _empty_or_nil),
    do: query ++ [phen: ""]

  defp maybe_put_display(query, :predictions), do: query
  defp maybe_put_display(query, :data_table), do: query ++ [display: "table"]
  defp maybe_put_display(query, :species_list), do: query ++ [display: "species"]
  defp maybe_put_display(query, _), do: query

  defp maybe_put_lat(query, lat) when is_number(lat) do
    if lat == @default_target_lat, do: query, else: query ++ [lat: to_string(lat)]
  end

  defp maybe_put_lat(query, _), do: query

  # ----------------------------------------------------------------------
  # Misc
  # ----------------------------------------------------------------------

  defp to_number(nil), do: :error
  defp to_number(""), do: :error
  defp to_number(n) when is_number(n), do: {:ok, n}

  defp to_number(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> {:ok, f}
      :error -> :error
    end
  end

  defp to_number(_), do: :error
end
