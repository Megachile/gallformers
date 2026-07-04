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

  alias Gallformers.Galls
  alias Gallformers.Phenology
  alias Gallformers.Phenology.Prediction
  alias Gallformers.Places
  alias GallformersWeb.PhenologyFilters

  @generations [:all, :sexgen, :agamic]

  @impl true
  def mount(params, _session, socket) do
    filters = PhenologyFilters.from_url_params(params)

    socket =
      socket
      |> assign(
        page_title: "Phenology",
        page_description:
          "Phenology of gall-forming species: when galls appear, mature, and emerge across latitudes.",
        page_url: "/phenology",
        page_image: nil,
        page_json_ld: nil,
        explorer_phenophases: PhenologyFilters.explorer_phenophases(),
        # Grouped list of family/tribe/genus nodes that actually have
        # phenology data, for the taxon selector. Loaded in the live mount
        # alongside observations so the dead render doesn't pay for it.
        taxon_options: [],
        # Region typeahead state (country / state / province). `selected_place`
        # is the chosen Place (or nil); place_id lives in `filters`.
        place_query: "",
        place_results: [],
        selected_place: nil,
        # Gall-trait checkbox options (location on host / color / shape).
        # Loaded in the live mount too.
        trait_options: %{plant_parts: [], colors: [], shapes: []},
        # Advanced filters (everything past the name search) start collapsed —
        # most visitors just search by name. The panel is CSS-hidden, not
        # unrendered, so its inputs still submit (phenophase defaults etc.).
        show_filters: false,
        filters: filters,
        observations: [],
        chart_points_json: "[]",
        # Bumped every time `load_observations` runs. The JS table hook
        # reads it off the host's `data-version` attr and re-renders rows
        # from `data-points` when it changes (filter applied → new obs
        # set). The hook owns the inner DOM via `phx-update="ignore"`,
        # so this is how it learns "the underlying obs set just changed."
        obs_version: 0,
        predictions: [],
        initialized?: false
      )

    # Phoenix LV calls mount/3 twice: once during the dead render that ships
    # the initial HTML, then again after the live socket connects. Without
    # a guard the DB query would run both times — and the dead-render HTML
    # would already include the obs, so we'd block the first-paint TTFB on
    # a Postgres roundtrip we're about to throw away. Defer to the live
    # mount; the user sees the page structure instantly and the chart
    # populates a moment later.
    socket =
      if connected?(socket) do
        socket
        |> assign(taxon_options: Phenology.list_taxon_filter_options())
        |> assign(selected_place: load_selected_place(filters[:place_id]))
        |> assign(trait_options: load_trait_options())
        |> load_observations()
        |> compute_predictions()
        |> assign(initialized?: true)
      else
        socket
      end

    {:ok, socket}
  end

  @impl true
  def handle_event("update_filters", params, socket) do
    # The region filter is a typeahead, not a form field, so form changes don't
    # carry it — preserve the current place_id across other-filter edits.
    new_filters =
      params
      |> PhenologyFilters.from_form_params()
      |> Map.put(:place_id, socket.assigns.filters[:place_id])

    prior_filters = socket.assigns.filters
    obs_changed? = query_affecting_filters_changed?(new_filters, prior_filters)

    socket =
      socket
      |> assign(filters: new_filters)
      |> maybe_reload_obs(obs_changed?)
      |> compute_predictions()
      |> push_patch(
        to: ~p"/phenology?#{PhenologyFilters.to_query(new_filters)}",
        replace: true
      )

    {:noreply, socket}
  end

  # Map widget's Clear-box button. Nulls the four coord filters, re-runs
  # the obs query, and pushes the cleared filter state into the URL. The
  # chart's JS hook drops any active brush when it re-renders on the new
  # obs set, so no server-side brush bookkeeping is needed.
  def handle_event("clear_coord_bounds", _params, socket) do
    new_filters =
      socket.assigns.filters
      |> Map.put(:min_lat, nil)
      |> Map.put(:max_lat, nil)
      |> Map.put(:min_lng, nil)
      |> Map.put(:max_lng, nil)

    socket =
      socket
      |> assign(filters: new_filters)
      |> load_observations()
      |> compute_predictions()
      |> push_patch(
        to: ~p"/phenology?#{PhenologyFilters.to_query(new_filters)}",
        replace: true
      )

    {:noreply, socket}
  end

  # Expand / collapse the advanced filter panel. On expand we tell the
  # bounds map to resize: it was mounted inside a `display:none` container
  # (so MapLibre sized its canvas to 0) and won't otherwise notice it's now
  # visible.
  def handle_event("toggle_filters", _params, socket) do
    show = not socket.assigns.show_filters
    socket = assign(socket, show_filters: show)
    socket = if show, do: push_event(socket, "phenology:filters-shown", %{}), else: socket
    {:noreply, socket}
  end

  # Region typeahead (reuses the site-wide place search). Suggestions come from
  # Places.search_places_grouped; selecting one sets the place_id filter and
  # reloads. The obs query rolls a country up to its states, so any level works.
  def handle_event("search_place", %{"value" => query}, socket) do
    results =
      if String.length(query) >= 2, do: Places.search_places_grouped(query, 10), else: []

    {:noreply, assign(socket, place_query: query, place_results: results)}
  end

  def handle_event("select_place", %{"id" => id_str}, socket) do
    place = Places.get_place(String.to_integer(id_str))
    {:noreply, apply_place_selection(socket, place)}
  end

  def handle_event("clear_place", _params, socket) do
    {:noreply, apply_place_selection(socket, nil)}
  end

  # Filters that change the DB query and therefore the on-screen obs set.
  # Changing anything NOT in this list (display_mode, target_lat) leaves the
  # obs set untouched — we skip the DB roundtrip AND keep the brush selection
  # alive (a selection over a still-current obs set is still meaningful).
  @query_affecting_keys [
    :search,
    :generation,
    :phenophases,
    :taxon_id,
    :place_id,
    :plant_part_ids,
    :color_ids,
    :shape_ids,
    :min_lat,
    :max_lat,
    :min_lng,
    :max_lng
  ]

  defp query_affecting_filters_changed?(a, b) do
    Enum.any?(@query_affecting_keys, fn key -> a[key] != b[key] end)
  end

  defp maybe_reload_obs(socket, false), do: socket

  defp maybe_reload_obs(socket, true) do
    # New obs set → any prior brush selection is no longer meaningful, but
    # the brush state lives entirely in the chart's JS hook now; it drops
    # itself when the chart re-renders from a new points set.
    load_observations(socket)
  end

  # Shared by select_place / clear_place: set the region filter, reload obs,
  # and patch the URL so the filter is deep-linkable.
  defp apply_place_selection(socket, place) do
    new_filters = Map.put(socket.assigns.filters, :place_id, place && place.id)

    socket
    |> assign(filters: new_filters, selected_place: place, place_query: "", place_results: [])
    |> load_observations()
    |> compute_predictions()
    |> push_patch(to: ~p"/phenology?#{PhenologyFilters.to_query(new_filters)}", replace: true)
  end

  defp load_selected_place(nil), do: nil
  defp load_selected_place(id) when is_integer(id), do: Places.get_place(id)

  # Label for a place in the region typeahead: "California — United States"
  # for states/provinces (parent_name is present on search results), just the
  # name otherwise (e.g. a country, or a re-loaded selection with no parent).
  defp place_display(place) do
    parent = Map.get(place, :parent_name)

    if Map.get(place, :type) in ["state", "province"] and parent not in [nil, ""] do
      "#{place.name} — #{parent}"
    else
      place.name
    end
  end

  @impl true
  def handle_params(_params, _url, socket), do: {:noreply, socket}

  # ----------------------------------------------------------------------
  # Data loading
  # ----------------------------------------------------------------------

  defp load_observations(socket) do
    observations = Phenology.search_observations(socket.assigns.filters)

    # Pre-encode chart points so the template doesn't re-Jason.encode
    # potentially thousands of obs on every unrelated re-render (display
    # mode toggle, target_lat tweak, brush event, etc).
    chart_points_json = observations |> chart_points() |> Jason.encode!()

    assign(socket,
      observations: observations,
      chart_points_json: chart_points_json,
      obs_version: socket.assigns.obs_version + 1
    )
  end

  # The three gall-trait facets the explorer exposes, pulled from the ID
  # tool's shared option lists so the vocabularies can't drift. Normalized to
  # `%{id, label}` here so the template is agnostic to each facet's differing
  # label column (part / color / shape).
  defp load_trait_options do
    opts = Galls.get_filter_options()

    %{
      plant_parts: normalize_trait_options(opts[:plant_parts], & &1.part),
      colors: normalize_trait_options(opts[:colors], & &1.color),
      shapes: normalize_trait_options(opts[:shapes], & &1.shape)
    }
  end

  defp normalize_trait_options(list, label_fun) do
    Enum.map(list, fn o -> %{id: o.id, label: label_fun.(o)} end)
  end

  defp compute_predictions(socket) do
    target_lat = socket.assigns.filters[:target_lat] || PhenologyFilters.default_target_lat()

    predictions =
      socket.assigns.observations
      |> Prediction.predictions_for(target_lat)
      |> Enum.sort_by(&{&1.generation, &1.event})

    assign(socket, predictions: predictions)
  end

  # ----------------------------------------------------------------------
  # Helpers (chart data + display formatting)
  # ----------------------------------------------------------------------

  @doc false
  # Per-observation payload shipped to the chart hook in `data-points`.
  # The JS-rendered data table and species list both read from this same
  # array, so it carries every field they need to render (host name,
  # longitude, source/page URLs, species_id for the gall-page link).
  def chart_points(observations) do
    Enum.map(observations, fn o ->
      %{
        id: o.id,
        species_id: o.species_id,
        species_name: o.species_name,
        host_species_name: o.host_species_name,
        doy: o.doy,
        seasind: o.seasind,
        date: format_obs_date(o.date),
        lat: o.latitude,
        lng: o.longitude,
        generation: generation_of(o.species_name),
        phenophase: o.phenophase || "(none)",
        lifestage: o.lifestage || "",
        viability: o.viability || "",
        source_type: o.source_type,
        source_url: o.source_url,
        page_url: o.page_url,
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

  # Groups the (already rank-then-name sorted) taxon options into
  # {group_label, options} pairs for rendering as <optgroup>s. Entries of
  # the same group are contiguous after the sort, so chunk_by preserves the
  # family → tribe → genus ordering.
  # Chunk pre-sorted `%{group: ...}` options into `{group, opts}` pairs for
  # <optgroup>s. Shared by the taxon and geographic selectors.
  defp grouped_options(options) do
    options
    |> Enum.chunk_by(& &1.group)
    |> Enum.map(fn [%{group: g} | _] = chunk -> {g, chunk} end)
  end

  defp display_value(%{display_mode: :data_table}), do: "table"
  defp display_value(%{display_mode: :species_list}), do: "species"
  defp display_value(_), do: "predictions"

  # Collapses the obs list to one row per species with obs count, day-of-year
  # span, and latest-observation date attached, ordered by `sort`. Used by the
  # species_list display mode (the JS table mirrors this ordering client-side).
  defp species_rows(observations, sort) do
    observations
    |> Enum.group_by(&{&1.species_id, &1.species_name})
    |> Enum.map(fn {{id, name}, obs} ->
      doys = Enum.map(obs, & &1.doy)

      %{
        species_id: id,
        name: name,
        n_obs: length(obs),
        spread: Enum.max(doys) - Enum.min(doys),
        last_date: obs |> Enum.map(& &1.date) |> Enum.reject(&is_nil/1) |> Enum.max(fn -> nil end)
      }
    end)
    |> sort_species_rows(sort)
  end

  # Name is the tiebreaker (and default) so the order is stable.
  defp sort_species_rows(rows, :obs_count), do: Enum.sort_by(rows, &{-&1.n_obs, &1.name})
  defp sort_species_rows(rows, :spread), do: Enum.sort_by(rows, &{-&1.spread, &1.name})

  defp sort_species_rows(rows, :recency) do
    # Stable two-pass: name asc first, then latest-date desc keeps name as the
    # ascending tiebreaker within a date.
    rows
    |> Enum.sort_by(& &1.name)
    |> Enum.sort_by(&(&1.last_date || ~D[0001-01-01]), {:desc, Date})
  end

  defp sort_species_rows(rows, _name), do: Enum.sort_by(rows, & &1.name)

  # Path for the CSV export endpoint, preserving the current filter state.
  # The brush selection (if any) is appended client-side by the
  # PhenologyCsvLink hook — see assets/js/hooks/phenology_csv_link.js.
  # The controller still honors the brush params when present.
  defp export_path(filters, _selection) do
    query = PhenologyFilters.to_query(filters)
    ~p"/phenology/export.csv?#{query}"
  end

  # Resolves the PMTiles boundaries URL for the bounds-picker map.
  # Mirrors `range_map`: configured per-env in dev/test/runtime, falling
  # back to the production CloudFront-ish path. In dev this is
  # `/data/boundaries.pmtiles`, not `/tiles/...`.
  defp tiles_url do
    Application.get_env(:gallformers, :tiles_url, "/tiles/boundaries.pmtiles")
  end

  # ----------------------------------------------------------------------
  # Render
  # ----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_user={@current_user}>
      <div id="phenology-container" class="max-w-6xl mx-auto">
        <h1 class="text-3xl font-semibold text-gf-maroon mb-1">Phenology</h1>
        <p class="text-gray-600 mb-4">
          Day-of-year × latitude scatter for gall species' observations.
          Colored by generation (blue&nbsp;= sexual, red&nbsp;= agamic, gray&nbsp;= unknown).
        </p>

        <form
          id="phenology-filters"
          phx-change="update_filters"
          phx-submit="update_filters"
          class="mb-4 grid gap-4 rounded-lg border border-gray-200 bg-gray-50 p-4"
        >
          <div>
            <label for="search" class="block text-sm font-semibold text-gray-700 mb-1">
              Search by genus, species, or gallformers code
            </label>
            <input
              type="text"
              name="search"
              id="search"
              class="gf-input"
              value={search_value(@filters)}
              placeholder="e.g. Acraspis, Aulacidea"
              phx-debounce="300"
            />
            <span class="mt-1 block text-xs text-gray-500">
              Comma-separated for multiple terms; matches any fragment in the species name.
            </span>
          </div>

          <div class="flex flex-wrap items-start gap-x-8 gap-y-3">
            <fieldset class="border-0 p-0 m-0">
              <legend class="text-sm font-semibold text-gray-700 mb-1">Generation</legend>
              <%= for {value, label} <- [{"all", "All"}, {"sexgen", "Sexual"}, {"agamic", "Agamic"}] do %>
                <label class="mr-3 text-sm text-gray-700">
                  <input
                    type="radio"
                    class="mr-1 align-middle accent-gf-maroon"
                    name="generation"
                    value={value}
                    checked={gen_value(@filters) == value}
                  /> {label}
                </label>
              <% end %>
            </fieldset>

            <fieldset class="border-0 p-0 m-0 flex-1 min-w-[280px]">
              <legend class="text-sm font-semibold text-gray-700 mb-1">Phenophase</legend>
              <div class="flex flex-wrap gap-x-3 gap-y-1">
                <%= for p <- @explorer_phenophases do %>
                  <label class="text-sm text-gray-700">
                    <input
                      type="checkbox"
                      class="gf-checkbox"
                      name="phenophases[]"
                      value={p}
                      checked={p in @filters.phenophases}
                    /> {p}
                  </label>
                <% end %>
              </div>
              <span class="mt-1 block text-xs text-gray-500">
                Uncheck all to clear filter (no observations will be displayed).
              </span>
            </fieldset>
          </div>

          <div class="flex flex-wrap items-start gap-x-8 gap-y-3">
            <fieldset class="border-0 p-0 m-0">
              <legend class="text-sm font-semibold text-gray-700 mb-1">
                Show below chart
              </legend>
              <%= for {value, label} <- [{"predictions", "Predictions"}, {"table", "Data table"}, {"species", "Species list"}] do %>
                <label class="mr-3 text-sm text-gray-700">
                  <input
                    type="radio"
                    class="mr-1 align-middle accent-gf-maroon"
                    name="display"
                    value={value}
                    checked={display_value(@filters) == value}
                  /> {label}
                </label>
              <% end %>
            </fieldset>

            <div :if={@filters.display_mode == :species_list}>
              <label for="sort" class="block text-sm font-semibold text-gray-700 mb-1">
                Sort species by
              </label>
              <select name="sort" id="sort" class="gf-select">
                <%= for {value, label} <- [
                    {"name", "Name (A–Z)"},
                    {"obs_count", "Observation count"},
                    {"spread", "Phenology spread"},
                    {"recency", "Most recent"}
                  ] do %>
                  <option value={value} selected={to_string(@filters.sort) == value}>
                    {label}
                  </option>
                <% end %>
              </select>
            </div>

            <div>
              <label for="target_lat" class="block text-sm font-semibold text-gray-700 mb-1">
                Predict at latitude
              </label>
              <input
                type="number"
                name="target_lat"
                id="target_lat"
                value={format_target_lat(@filters[:target_lat])}
                step="0.5"
                min="-90"
                max="90"
                phx-debounce="400"
                class="w-20 rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-gf-maroon focus:outline-none"
              />
              <span class="ml-1.5 text-xs text-gray-500">
                °N (negative = °S)
              </span>
            </div>
          </div>

          <button
            type="button"
            id="toggle-filters"
            phx-click="toggle_filters"
            class="justify-self-start inline-flex items-center gap-1 text-sm font-medium text-gf-maroon hover:underline"
            aria-expanded={to_string(@show_filters)}
            aria-controls="phenology-advanced-filters"
          >
            {if @show_filters, do: "Fewer filters", else: "More filters"}
            <.icon
              name="ph-caret-down"
              class={["h-4 w-4 transition-transform", @show_filters && "rotate-180"]}
            />
          </button>

          <div
            id="phenology-advanced-filters"
            class={["grid gap-4", not @show_filters && "hidden"]}
          >
            <div>
              <label for="taxon" class="block text-sm font-semibold text-gray-700 mb-1">
                Taxon (family / tribe)
              </label>
              <select name="taxon" id="taxon" class="gf-select">
                <option value="" selected={is_nil(@filters[:taxon_id])}>All taxa</option>
                <optgroup :for={{group, opts} <- grouped_options(@taxon_options)} label={group}>
                  <option
                    :for={t <- opts}
                    value={t.id}
                    selected={@filters[:taxon_id] == t.id}
                  >
                    {t.name} ({t.n_species})
                  </option>
                </optgroup>
              </select>
              <span class="mt-1 block text-xs text-gray-500">
                Restricts to species under the chosen family or tribe. For a single
                genus, use the search box above. Count is species with phenology data.
              </span>
            </div>

            <div>
              <.typeahead
                id="place-filter"
                label="Region (country / state / province)"
                placeholder="Search regions…"
                search_event="search_place"
                select_event="select_place"
                clear_event="clear_place"
                query={@place_query}
                results={@place_results}
                selected={@selected_place}
                group_key={:group}
                display_fn={&place_display/1}
              />
              <span class="mt-1 block text-xs text-gray-500">
                Restricts to species whose documented range covers the chosen region
                (a country includes its states/provinces). This is the species' known
                range, not where each observation was recorded.
              </span>
            </div>

            <fieldset class="border-0 p-0 m-0">
              <legend class="text-sm font-semibold text-gray-700 mb-1">
                Gall traits (optional)
              </legend>
              <div class="flex flex-wrap gap-6">
                <%= for {facet_label, facet_key, form_name, selected} <- [
                    {"Location on host", :plant_parts, "plant_part_ids", @filters[:plant_part_ids]},
                    {"Color", :colors, "color_ids", @filters[:color_ids]},
                    {"Shape", :shapes, "shape_ids", @filters[:shape_ids]}
                  ] do %>
                  <div class="min-w-[200px]">
                    <div class="text-xs font-semibold text-gray-600 mb-0.5">
                      {facet_label}
                    </div>
                    <div class="flex flex-wrap gap-x-2.5 gap-y-0.5">
                      <label :for={opt <- @trait_options[facet_key]} class="text-sm text-gray-700">
                        <input
                          type="checkbox"
                          class="gf-checkbox"
                          name={form_name <> "[]"}
                          value={opt.id}
                          checked={opt.id in (selected || [])}
                        /> {opt.label}
                      </label>
                    </div>
                  </div>
                <% end %>
              </div>
              <span class="mt-1 block text-xs text-gray-500">
                Filters to galls with the selected traits (within a trait, any match;
                across traits, all must match).
              </span>
            </fieldset>

            <fieldset class="border-0 p-0 m-0">
              <legend class="text-sm font-semibold text-gray-700 mb-1">
                Observation coordinates (optional)
              </legend>
              <div class="flex flex-wrap items-center gap-4 text-sm text-gray-700">
                <span class="inline-flex items-center gap-1.5">
                  <span>Lat</span>
                  <input
                    type="number"
                    name="min_lat"
                    value={format_coord_bound(@filters[:min_lat])}
                    step="0.1"
                    min="-90"
                    max="90"
                    phx-debounce="400"
                    aria-label="Minimum latitude"
                    class="w-20 rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-gf-maroon focus:outline-none"
                  />
                  <span>to</span>
                  <input
                    type="number"
                    name="max_lat"
                    value={format_coord_bound(@filters[:max_lat])}
                    step="0.1"
                    min="-90"
                    max="90"
                    phx-debounce="400"
                    aria-label="Maximum latitude"
                    class="w-20 rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-gf-maroon focus:outline-none"
                  />
                </span>
                <span class="inline-flex items-center gap-1.5">
                  <span>Lng</span>
                  <input
                    type="number"
                    name="min_lng"
                    value={format_coord_bound(@filters[:min_lng])}
                    step="0.1"
                    min="-180"
                    max="180"
                    phx-debounce="400"
                    aria-label="Minimum longitude"
                    class="w-24 rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-gf-maroon focus:outline-none"
                  />
                  <span>to</span>
                  <input
                    type="number"
                    name="max_lng"
                    value={format_coord_bound(@filters[:max_lng])}
                    step="0.1"
                    min="-180"
                    max="180"
                    phx-debounce="400"
                    aria-label="Maximum longitude"
                    class="w-24 rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-gf-maroon focus:outline-none"
                  />
                </span>
                <span class="text-xs text-gray-500">
                  Drops species with no observations in the box. Leave blank for no filter.
                </span>
                <button
                  :if={
                    @filters[:min_lat] || @filters[:max_lat] ||
                      @filters[:min_lng] || @filters[:max_lng]
                  }
                  type="button"
                  phx-click="clear_coord_bounds"
                  class="rounded-md border border-gray-300 bg-white px-2 py-1 text-xs font-medium text-gray-700 hover:bg-gray-50"
                >
                  Clear box
                </button>
              </div>

              <%!-- MapLibre widget under the inputs. Shift+drag draws the box;
                  normal drag still pans. The hook is the canonical writer of
                  the form input values, and reads the host's data-* attrs to
                  hydrate the rectangle on URL deep-link or typed-input
                  changes. phx-update="ignore" so the LV doesn't recreate the
                  canvas on every diff. --%>
              <div
                id="phenology-bounds-map"
                phx-hook="PhenologyBoundsMap"
                phx-update="ignore"
                data-min-lat={format_coord_bound(@filters[:min_lat])}
                data-max-lat={format_coord_bound(@filters[:max_lat])}
                data-min-lng={format_coord_bound(@filters[:min_lng])}
                data-max-lng={format_coord_bound(@filters[:max_lng])}
                data-obs-version={@obs_version}
                data-target-lat={
                  to_string(@filters[:target_lat] || PhenologyFilters.default_target_lat())
                }
                data-target-lat-shown={to_string(@filters.display_mode == :predictions)}
                data-tiles-url={tiles_url()}
                class="mt-2 h-[280px] rounded-md border border-gray-200 bg-gf-sky-blue"
              >
              </div>
              <span class="mt-1 block text-xs text-gray-500">
                Shift + drag on the map to draw a bounding box. Drag without shift
                to pan; scroll to zoom.
              </span>
            </fieldset>
          </div>
          <%!-- /phenology-advanced-filters --%>
        </form>

        <%!-- Chrome bar. Three things hang off the brush state:
                - "· N in brush selection" count
                - Clear-selection button
                - Download CSV link's href (brush bounds get appended)
              None of these can cost a per-brush LV roundtrip, so they're
              all JS-driven via the phenologyState pub/sub.

              Two separate hooks because the CSV link's existence depends
              on server state (display_mode + obs presence) and so must be
              server-rendered with normal LV diffing. The brush count +
              Clear button are pure client state (nothing to render until
              JS publishes a brush) and live in a `phx-update="ignore"`
              host the hook owns. --%>
        <div class="my-2 flex flex-wrap items-center gap-3 text-sm text-gray-600">
          <span :if={not @initialized?} class="italic text-gray-400">
            Loading observations…
          </span>
          <span :if={@initialized?}>
            {length(@observations)} observation{if length(@observations) != 1, do: "s"} across {species_count(
              @observations
            )} species
          </span>
          <div
            id="phenology-brush-chrome"
            phx-hook="PhenologyChrome"
            phx-update="ignore"
            class="contents"
          >
          </div>
        </div>

        <%= cond do %>
          <% not @initialized? -> %>
            <div class="rounded-lg border border-gray-200 bg-white p-10 text-center text-gray-400">
              Loading observations…
            </div>
          <% @observations == [] -> %>
            <div class="rounded-lg border border-gray-200 bg-white p-10 text-center text-gray-400">
              No observations match these filters.
            </div>
          <% true -> %>
            <div
              id="phenology-chart"
              phx-hook="PhenologyChart"
              phx-update="ignore"
              data-points={@chart_points_json}
              class="relative h-[540px] rounded-lg border border-gray-200 bg-white"
            >
            </div>
            <div class="mt-3">
              <%!-- Display-only selection lens (port of the doyCalc "Selection
                    mode"). Always shown under the chart (like the Shiny
                    sidebar control) so it's discoverable regardless of display
                    mode; it narrows the data table / species list / CSV and
                    never touches the prediction windows. Client-side via the
                    PhenologySelect hook, which shows/hides the per-mode input
                    groups; phx-update="ignore" keeps typed values across LV
                    re-renders. --%>
              <div
                id="phenology-select"
                phx-hook="PhenologySelect"
                phx-update="ignore"
                class="rounded-lg border border-gray-200 bg-gray-50 p-3"
              >
                <div class="flex flex-wrap items-start gap-x-6 gap-y-3">
                  <div>
                    <span class="block text-xs font-semibold text-gray-600 mb-1">
                      Selection mode
                    </span>
                    <div class="flex flex-col gap-1 text-sm text-gray-700">
                      <label class="inline-flex items-center gap-1.5">
                        <input
                          type="radio"
                          name="phenology-sel-mode"
                          value="click_drag"
                          checked
                          class="gf-radio"
                        /> Click &amp; drag on chart
                      </label>
                      <label class="inline-flex items-center gap-1.5">
                        <input
                          type="radio"
                          name="phenology-sel-mode"
                          value="date_range"
                          class="gf-radio"
                        /> Date range
                      </label>
                      <label class="inline-flex items-center gap-1.5">
                        <input
                          type="radio"
                          name="phenology-sel-mode"
                          value="season_index"
                          class="gf-radio"
                        /> Season index
                      </label>
                    </div>
                  </div>

                  <div data-sel-group="date_range season_index" class="hidden">
                    <label class="block text-xs font-semibold text-gray-600 mb-1">
                      Reference date <span class="font-normal text-gray-400">(year ignored)</span>
                    </label>
                    <input
                      type="date"
                      data-sel="date"
                      value={Date.to_iso8601(Date.utc_today())}
                      class="rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-gf-maroon focus:outline-none"
                    />
                  </div>

                  <div data-sel-group="date_range" class="hidden">
                    <label class="block text-xs font-semibold text-gray-600 mb-1">
                      Days before / after
                    </label>
                    <input
                      type="number"
                      data-sel="days"
                      min="1"
                      max="183"
                      value="10"
                      class="w-24 rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-gf-maroon focus:outline-none"
                    />
                  </div>

                  <div data-sel-group="season_index" class="hidden">
                    <div class="flex items-end gap-3">
                      <div>
                        <label class="block text-xs font-semibold text-gray-600 mb-1">
                          Latitude (°N)
                        </label>
                        <input
                          type="number"
                          data-sel="lat"
                          min="-90"
                          max="90"
                          step="0.5"
                          value="40"
                          class="w-20 rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-gf-maroon focus:outline-none"
                        />
                      </div>
                      <div>
                        <label class="block text-xs font-semibold text-gray-600 mb-1">
                          Tolerance
                        </label>
                        <input
                          type="number"
                          data-sel="thr"
                          min="0.005"
                          max="0.5"
                          step="0.005"
                          value="0.05"
                          class="w-24 rounded-md border border-gray-300 px-2 py-1 text-sm focus:border-gf-maroon focus:outline-none"
                        />
                      </div>
                    </div>
                  </div>
                </div>

                <p data-sel-group="click_drag" class="mt-2 text-xs text-gray-500">
                  Drag a box on the chart to select observations for the data
                  table and species list. Click outside the box to clear.
                </p>
                <p data-sel-group="date_range" class="hidden mt-2 text-xs text-gray-500">
                  Selects observations within the chosen number of days of your
                  reference date (year ignored; wraps across the new year).
                </p>
                <p data-sel-group="season_index" class="hidden mt-2 text-xs text-gray-500">
                  Selects observations at a similar point in the annual daylight
                  cycle to your reference date at this latitude — comparable
                  across latitudes even though the calendar dates differ.
                  Tolerance widens the band.
                </p>
              </div>

              <div
                :if={@filters.display_mode in [:data_table, :species_list]}
                class="mt-2 flex justify-end"
              >
                <.link
                  id="phenology-csv-link"
                  phx-hook="PhenologyCsvLink"
                  href={export_path(@filters, nil)}
                  data-href-base={export_path(@filters, nil)}
                  class="text-xs text-gf-maroon underline"
                >
                  Download CSV
                </.link>
              </div>
            </div>

            <%= cond do %>
              <% @filters.display_mode == :data_table -> %>
                <div
                  id="phenology-table-host"
                  phx-hook="PhenologyTable"
                  phx-update="ignore"
                  data-mode="table"
                  data-version={@obs_version}
                  class="mt-3 max-h-[60vh] overflow-auto rounded-lg border border-gray-200 bg-white"
                >
                  <%!-- SSR / no-JS fallback only. The hook owns this DOM
                        after mount and filters by brush in JS — see
                        assets/js/hooks/phenology_table.js. --%>
                  <.table
                    id="phenology-obs-table"
                    rows={@observations}
                    variant="compact"
                  >
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
                <div
                  id="phenology-table-host"
                  phx-hook="PhenologyTable"
                  phx-update="ignore"
                  data-mode="species"
                  data-version={@obs_version}
                  data-sort={to_string(@filters.sort)}
                  class="mt-3 max-h-[60vh] overflow-auto rounded-lg border border-gray-200 bg-white"
                >
                  <%!-- SSR / no-JS fallback only — see comment on the
                        obs-table host above. --%>
                  <.table
                    id="phenology-species-table"
                    rows={species_rows(@observations, @filters.sort)}
                    variant="compact"
                  >
                    <:col :let={row} label="Species">
                      <.link href={~p"/gall/#{row.species_id}"}>{row.name}</.link>
                    </:col>
                    <:col :let={row} label="Observations">{row.n_obs}</:col>
                    <:col :let={row} label="DOY span">{row.spread}</:col>
                    <:col :let={row} label="Latest">{format_obs_date(row.last_date)}</:col>
                  </.table>
                </div>
              <% true -> %>
                <%= if @predictions != [] do %>
                  <div
                    id="phenology-predictions"
                    class="mt-3 rounded-lg border border-gray-200 bg-gray-50 p-3 text-sm"
                  >
                    <div class="font-semibold text-gray-800 mb-1.5">
                      Predicted windows at {format_target_lat(@filters[:target_lat])}°{lat_hemisphere(
                        @filters[:target_lat]
                      )}
                    </div>
                    <ul class="list-disc pl-5 space-y-0.5">
                      <li :for={p <- @predictions}>
                        {prediction_sentence(p)}
                      </li>
                    </ul>
                    <span class="mt-1 block text-xs text-gray-500">
                      Based on the seasind IQR of matched observations, back-projected
                      to your latitude. Predictions are NH-temperate-calibrated — see
                      <a
                        href="https://github.com/Megachile/gallformers/issues/1"
                        class="text-gf-maroon underline"
                      >
                        issue #1
                      </a>
                      for the SH validation roadmap.
                    </span>
                  </div>
                <% end %>
            <% end %>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp format_coord(c) when is_float(c), do: :erlang.float_to_binary(c, [:compact, decimals: 3])
  defp format_coord(c) when is_number(c), do: to_string(c)
  defp format_coord(_), do: ""

  defp format_target_lat(lat) when is_float(lat),
    do: :erlang.float_to_binary(abs(lat), [:compact, decimals: 1])

  defp format_target_lat(lat) when is_number(lat), do: to_string(abs(lat))
  defp format_target_lat(_), do: to_string(PhenologyFilters.default_target_lat())

  defp format_coord_bound(v) when is_float(v),
    do: :erlang.float_to_binary(v, [:compact, decimals: 4])

  defp format_coord_bound(v) when is_number(v), do: to_string(v)
  defp format_coord_bound(_), do: ""

  defp lat_hemisphere(lat) when is_number(lat) and lat < 0, do: "S"
  defp lat_hemisphere(_), do: "N"

  # Build the human-readable sentence for a single prediction row.
  # Matches the Shiny app's phrasing: "At X°N, [adults of the sexual
  # generation are expected to emerge] between MM/DD and MM/DD."
  defp prediction_sentence(p) do
    "#{event_phrase(p.event, p.generation)} between #{doy_label(p.low_doy)} and " <>
      "#{doy_label(p.high_doy)} (n=#{p.n})."
  end

  defp event_phrase(:emergence, :sexgen),
    do: "Adults of the sexual generation are expected to emerge"

  defp event_phrase(:emergence, :agamic),
    do: "Adults of the agamic generation are expected to emerge"

  defp event_phrase(:emergence, :unknown),
    do: "Adults (unknown generation) are expected to emerge"

  defp event_phrase(:rearing, :sexgen),
    do: "Galls of the sexual generation can likely be collected for rearing"

  defp event_phrase(:rearing, :agamic),
    do: "Galls of the agamic generation can likely be collected for rearing"

  defp event_phrase(:rearing, :unknown),
    do: "Galls (unknown generation) can likely be collected for rearing"

  defp doy_label(doy) when is_integer(doy) and doy >= 1 and doy <= 366 do
    ~D[2024-01-01]
    |> Date.add(doy - 1)
    |> Calendar.strftime("%b %-d")
  end

  defp doy_label(_), do: "?"
end
