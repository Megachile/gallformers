defmodule GallformersWeb.PhenologyLive do
  @moduledoc """
  Public phenology explorer. Multi-species scatter of day-of-year × latitude
  with comma-separated name search, generation filter, and phenophase
  multi-select. Points are colored by generation (blue = sexual, red = agamic,
  gray = unknown) and shaped by phenophase. The tooltip surfaces species
  identity per-point.

  Aims at parity with the legacy R/Shiny `doyCalc` viewer in slices — see
  Megachile/gallformers#2 for the full slicing.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Phenology
  alias Gallformers.Species

  # Phenophases offered in the explorer UI, in display order. NOT the same
  # as `Observation.phenophases()` — `senescent` is intentionally omitted
  # (uninteresting for the prediction use case Adam built the tool around).
  # New phenophases land in the DB regardless; this is a UX-only list.
  @explorer_phenophases ~w(oviscar developing dormant maturing Free-living perimature)

  # Pre-populated default filters on first visit (no URL params). Defaults
  # to one well-observed species + a useful phenophase subset so the page
  # loads quickly and is interesting out of the box. Each filter has
  # independent override semantics — see parse_*_param below.
  @default_search ["Dryocosmus quercuspalustris"]
  @default_phenophases ~w(maturing perimature Free-living)

  @generations [:all, :sexgen, :agamic]

  @impl true
  def mount(params, _session, socket) do
    filters = filters_from_params(params)

    socket =
      socket
      |> assign(
        page_title: "Phenology",
        page_description:
          "Phenology of gall-forming species: when galls appear, mature, and emerge across latitudes.",
        page_url: "/phenology",
        page_image: nil,
        page_json_ld: nil,
        explorer_phenophases: @explorer_phenophases,
        filters: filters,
        observations: []
      )
      |> load_observations()

    {:ok, socket}
  end

  @impl true
  def handle_event("update_filters", params, socket) do
    filters = filters_from_form(params, socket.assigns.filters)

    {:noreply,
     socket
     |> assign(filters: filters)
     |> load_observations()
     |> push_patch(to: ~p"/phenology?#{filters_to_query(filters)}", replace: true)}
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ----------------------------------------------------------------------
  # Filter parsing
  # ----------------------------------------------------------------------

  # Parse filters from URL params on mount.
  #
  # URL semantics (key absent → use default; key present-but-empty → that
  # filter cleared explicitly):
  # - `search` absent → default search; `search=` → no search filter (all species)
  # - `phen` absent → default phenophases; `phen=` → empty (no obs match)
  # - `gen` absent → :all; `gen=sexgen|agamic` → restrict; anything else → :all
  # - `species_id=N` (legacy from the per-gall widget link) translates to a
  #   single search term and overrides `search` only when no `search` is given.
  defp filters_from_params(params) do
    %{
      search: parse_search_param(params),
      generation: parse_generation(params["gen"]),
      phenophases: parse_phenophases_param(params),
      display_mode: parse_display_mode(params["display"])
    }
  end

  # Form semantics: every change event sends the full form state. Absent
  # key means "user cleared it" (e.g. all checkboxes off), not "use default."
  defp filters_from_form(form_params, _prior) do
    %{
      search: parse_search_value(form_params["search"]),
      generation: parse_generation(form_params["generation"]),
      phenophases: parse_phenophases_form(form_params["phenophases"]),
      display_mode: parse_display_mode(form_params["display"])
    }
  end

  defp parse_display_mode("table"), do: :data_table
  defp parse_display_mode("species"), do: :species_list
  defp parse_display_mode(_), do: :chart

  defp parse_search_param(params) do
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

  defp parse_generation(value) when value in ["sexgen", "agamic", "all"],
    do: String.to_existing_atom(value)

  defp parse_generation(_), do: :all

  defp parse_phenophases_param(params) do
    case Map.fetch(params, "phen") do
      :error -> @default_phenophases
      {:ok, nil} -> @default_phenophases
      {:ok, value} -> parse_phenophases_value(value)
    end
  end

  # Form-event variant: nil means "no checkboxes checked" — the browser
  # omits unchecked groups entirely. Distinguishing this from URL-absent
  # is what gives the strict-empty semantics.
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

  # Build a query-param keyword list reflecting the current filters.
  # Emits explicit `search=` / `phen=` (empty value) when the user has
  # cleared a filter that has a non-empty default, so reload preserves
  # the cleared state instead of restoring the default.
  defp filters_to_query(filters) do
    []
    |> maybe_put_search(filters[:search])
    |> maybe_put_gen(filters[:generation])
    |> maybe_put_phen(filters[:phenophases])
    |> maybe_put_display(filters[:display_mode])
  end

  defp maybe_put_display(query, :chart), do: query
  defp maybe_put_display(query, :data_table), do: query ++ [display: "table"]
  defp maybe_put_display(query, :species_list), do: query ++ [display: "species"]
  defp maybe_put_display(query, _), do: query

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

  # ----------------------------------------------------------------------
  # Data loading
  # ----------------------------------------------------------------------

  defp load_observations(socket) do
    observations = Phenology.search_observations(socket.assigns.filters)
    assign(socket, observations: observations)
  end

  # ----------------------------------------------------------------------
  # Helpers (chart data + display formatting)
  # ----------------------------------------------------------------------

  @doc false
  def chart_points(observations) do
    Enum.map(observations, fn o ->
      %{
        doy: o.doy,
        lat: o.latitude,
        date: format_obs_date(o.date),
        species_name: o.species_name,
        generation: generation_of(o.species_name),
        phenophase: o.phenophase || "(none)",
        lifestage: o.lifestage || "",
        viability: o.viability || "",
        source_type: o.source_type,
        site: o.site || "",
        state: o.state || "",
        country: o.country || ""
      }
    end)
  end

  @doc false
  def generation_of(name) when is_binary(name) do
    cond do
      String.contains?(name, "(sexgen)") -> "sexgen"
      String.contains?(name, "(agamic)") -> "agamic"
      true -> "unknown"
    end
  end

  def generation_of(_), do: "unknown"

  defp format_obs_date(%Date{} = d), do: Date.to_iso8601(d)
  defp format_obs_date(_), do: ""

  defp species_count(observations) do
    observations |> Enum.map(& &1.species_id) |> Enum.uniq() |> length()
  end

  defp search_value(%{search: nil}), do: ""
  defp search_value(%{search: terms}) when is_list(terms), do: Enum.join(terms, ", ")
  defp search_value(_), do: ""

  defp gen_value(%{generation: gen}) when gen in @generations, do: Atom.to_string(gen)
  defp gen_value(_), do: "all"

  defp display_value(%{display_mode: :data_table}), do: "table"
  defp display_value(%{display_mode: :species_list}), do: "species"
  defp display_value(_), do: "chart"

  # Collapses the obs list to one row per species with the obs count attached,
  # ordered by name. Used by the species_list display mode.
  defp species_rows(observations) do
    observations
    |> Enum.group_by(&{&1.species_id, &1.species_name})
    |> Enum.map(fn {{id, name}, obs} -> %{species_id: id, name: name, n_obs: length(obs)} end)
    |> Enum.sort_by(& &1.name)
  end

  # Path for the CSV export endpoint, preserving the current filter state.
  # The same parser handles ?display= so the export respects whether the
  # user is on the data-table or species-list view (different shape).
  defp export_path(filters) do
    ~p"/phenology/export.csv?#{filters_to_query(filters)}"
  end

  # ----------------------------------------------------------------------
  # Render
  # ----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="phenology-page" style="max-width: 1200px; margin: 0 auto; padding: 16px;">
      <h1 style="margin: 0 0 4px 0;">Phenology</h1>
      <p style="color: #666; margin-top: 0;">
        Day-of-year × latitude scatter for gall species' observations.
        Colored by generation (blue&nbsp;= sexual, red&nbsp;= agamic, gray&nbsp;= unknown).
      </p>

      <form
        phx-change="update_filters"
        phx-submit="update_filters"
        style="margin: 12px 0; display: grid; grid-template-columns: 1fr; gap: 10px;
               padding: 10px 12px; background: #f5f3ec; border: 1px solid #ddd;
               border-radius: 4px;"
      >
        <div>
          <label for="search" style="font-weight: 600; display: block; margin-bottom: 4px;">
            Search by genus, species, or gallformers code
          </label>
          <input
            type="text"
            name="search"
            id="search"
            value={search_value(@filters)}
            placeholder="e.g. Acraspis, Aulacidea"
            phx-debounce="300"
            style="width: 100%; padding: 5px 8px; border: 1px solid #ccc; border-radius: 3px;"
          />
          <span style="display: block; color: #666; font-size: 11px; margin-top: 2px;">
            Comma-separated for multiple terms; matches any fragment in the species name.
          </span>
        </div>

        <div style="display: flex; gap: 18px; align-items: flex-start; flex-wrap: wrap;">
          <fieldset style="border: none; padding: 0; margin: 0;">
            <legend style="font-weight: 600; padding: 0; margin-bottom: 4px;">Generation</legend>
            <%= for {value, label} <- [{"all", "All"}, {"sexgen", "Sexual"}, {"agamic", "Agamic"}] do %>
              <label style="margin-right: 12px; font-size: 13px;">
                <input
                  type="radio"
                  name="generation"
                  value={value}
                  checked={gen_value(@filters) == value}
                /> {label}
              </label>
            <% end %>
          </fieldset>

          <fieldset style="border: none; padding: 0; margin: 0; flex: 1; min-width: 280px;">
            <legend style="font-weight: 600; padding: 0; margin-bottom: 4px;">Phenophase</legend>
            <div style="display: flex; flex-wrap: wrap; gap: 4px 12px;">
              <%= for p <- @explorer_phenophases do %>
                <label style="font-size: 13px;">
                  <input
                    type="checkbox"
                    name="phenophases[]"
                    value={p}
                    checked={p in @filters.phenophases}
                  /> {p}
                </label>
              <% end %>
            </div>
            <span style="display: block; color: #666; font-size: 11px; margin-top: 2px;">
              Uncheck all to clear filter (no observations will be displayed).
            </span>
          </fieldset>
        </div>

        <fieldset style="border: none; padding: 0; margin: 0;">
          <legend style="font-weight: 600; padding: 0; margin-bottom: 4px;">View</legend>
          <%= for {value, label} <- [{"chart", "Chart"}, {"table", "Data table"}, {"species", "Species list"}] do %>
            <label style="margin-right: 12px; font-size: 13px;">
              <input
                type="radio"
                name="display"
                value={value}
                checked={display_value(@filters) == value}
              /> {label}
            </label>
          <% end %>
        </fieldset>
      </form>

      <div style="font-size: 13px; color: #444; margin: 8px 0; display: flex; gap: 12px; align-items: center;">
        <span>
          {length(@observations)} observation{if length(@observations) != 1, do: "s"} across {species_count(
            @observations
          )} species
        </span>
        <.link
          :if={@filters.display_mode in [:data_table, :species_list] and @observations != []}
          href={export_path(@filters)}
          style="font-size: 12px; color: #2b5e3a; text-decoration: underline;"
        >
          Download CSV
        </.link>
      </div>

      <%= cond do %>
        <% @observations == [] -> %>
          <div style="padding: 40px; text-align: center; color: #888;
                      border: 1px solid #ddd; background: #fff; border-radius: 4px;">
            No observations match these filters.
          </div>
        <% @filters.display_mode == :data_table -> %>
          <div style="overflow-x: auto; border: 1px solid #ddd; background: #fff; border-radius: 4px;">
            <.table id="phenology-obs-table" rows={@observations} variant="compact">
              <:col :let={o} label="Species">{o.species_name}</:col>
              <:col :let={o} label="Phenophase">{o.phenophase || "—"}</:col>
              <:col :let={o} label="Lifestage">{o.lifestage || "—"}</:col>
              <:col :let={o} label="Viability">{o.viability || "—"}</:col>
              <:col :let={o} label="Host">{o.host_species_name || "—"}</:col>
              <:col :let={o} label="DOY">{o.doy}</:col>
              <:col :let={o} label="Date">{format_obs_date(o.date)}</:col>
              <:col :let={o} label="Lat">{format_coord(o.latitude)}</:col>
              <:col :let={o} label="Lng">{format_coord(o.longitude)}</:col>
              <:col :let={o} label="Source">
                <%= if o.source_url do %>
                  <a href={o.source_url} target="_blank" rel="noopener">link</a>
                <% else %>
                  —
                <% end %>
              </:col>
              <:col :let={o} label="Page">
                <%= if o.page_url do %>
                  <a href={o.page_url} target="_blank" rel="noopener">link</a>
                <% else %>
                  —
                <% end %>
              </:col>
            </.table>
          </div>
        <% @filters.display_mode == :species_list -> %>
          <div style="overflow-x: auto; border: 1px solid #ddd; background: #fff; border-radius: 4px;">
            <.table id="phenology-species-table" rows={species_rows(@observations)} variant="compact">
              <:col :let={row} label="Species">
                <.link href={~p"/gall/#{row.species_id}"}>{row.name}</.link>
              </:col>
              <:col :let={row} label="Observations">{row.n_obs}</:col>
            </.table>
          </div>
        <% true -> %>
          <div
            id="phenology-chart"
            phx-hook="PhenologyChart"
            phx-update="ignore"
            data-points={Jason.encode!(chart_points(@observations))}
            style="height: 540px; border: 1px solid #ddd; background: #fff; border-radius: 4px;"
          >
          </div>
      <% end %>
    </div>
    """
  end

  defp format_coord(c) when is_float(c), do: :erlang.float_to_binary(c, [:compact, decimals: 3])
  defp format_coord(c) when is_number(c), do: to_string(c)
  defp format_coord(_), do: ""
end
