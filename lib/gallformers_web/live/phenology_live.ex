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
  alias Gallformers.Phenology.Prediction
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
    new_filters = PhenologyFilters.from_form_params(params)
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

  # Only `search` / `generation` / `phenophases` affect the DB query and
  # therefore the on-screen obs set. Changing `display_mode` or `target_lat`
  # leaves the obs set untouched — we skip the DB roundtrip AND keep the
  # brush selection alive (selection from a still-current obs set is still
  # meaningful).
  defp query_affecting_filters_changed?(a, b) do
    a[:search] != b[:search] or
      a[:generation] != b[:generation] or
      a[:phenophases] != b[:phenophases] or
      a[:min_lat] != b[:min_lat] or
      a[:max_lat] != b[:max_lat] or
      a[:min_lng] != b[:min_lng] or
      a[:max_lng] != b[:max_lng]
  end

  defp maybe_reload_obs(socket, false), do: socket

  defp maybe_reload_obs(socket, true) do
    # New obs set → any prior brush selection is no longer meaningful, but
    # the brush state lives entirely in the chart's JS hook now; it drops
    # itself when the chart re-renders from a new points set.
    load_observations(socket)
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

  defp display_value(%{display_mode: :data_table}), do: "table"
  defp display_value(%{display_mode: :species_list}), do: "species"
  defp display_value(_), do: "predictions"

  # Collapses the obs list to one row per species with the obs count attached,
  # ordered by name. Used by the species_list display mode.
  defp species_rows(observations) do
    observations
    |> Enum.group_by(&{&1.species_id, &1.species_name})
    |> Enum.map(fn {{id, name}, obs} -> %{species_id: id, name: name, n_obs: length(obs)} end)
    |> Enum.sort_by(& &1.name)
  end

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
          <legend style="font-weight: 600; padding: 0; margin-bottom: 4px;">
            Observation coordinates (optional)
          </legend>
          <div style="display: flex; gap: 16px; align-items: center; flex-wrap: wrap; font-size: 13px;">
            <span style="display: inline-flex; gap: 6px; align-items: center;">
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
                style="width: 72px; padding: 3px 6px; border: 1px solid #ccc; border-radius: 3px;"
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
                style="width: 72px; padding: 3px 6px; border: 1px solid #ccc; border-radius: 3px;"
              />
            </span>
            <span style="display: inline-flex; gap: 6px; align-items: center;">
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
                style="width: 78px; padding: 3px 6px; border: 1px solid #ccc; border-radius: 3px;"
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
                style="width: 78px; padding: 3px 6px; border: 1px solid #ccc; border-radius: 3px;"
              />
            </span>
            <span style="color: #666; font-size: 11px;">
              Drops species with no observations in the box. Leave blank for no filter.
            </span>
            <button
              :if={
                @filters[:min_lat] || @filters[:max_lat] ||
                  @filters[:min_lng] || @filters[:max_lng]
              }
              type="button"
              phx-click="clear_coord_bounds"
              style="font-size: 11px; padding: 1px 8px; border: 1px solid #ccc;
                     background: #fff; border-radius: 3px; cursor: pointer;"
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
            data-tiles-url={tiles_url()}
            style="margin-top: 8px; height: 280px; border: 1px solid #ddd;
                   border-radius: 4px; background: #ADD8E6;"
          >
          </div>
          <span style="display: block; color: #666; font-size: 11px; margin-top: 2px;">
            Shift + drag on the map to draw a bounding box. Drag without shift
            to pan; scroll to zoom.
          </span>
        </fieldset>

        <div style="display: flex; gap: 18px; align-items: flex-start; flex-wrap: wrap;">
          <fieldset style="border: none; padding: 0; margin: 0;">
            <legend style="font-weight: 600; padding: 0; margin-bottom: 4px;">
              Show below chart
            </legend>
            <%= for {value, label} <- [{"predictions", "Predictions"}, {"table", "Data table"}, {"species", "Species list"}] do %>
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

          <div>
            <label
              for="target_lat"
              style="font-weight: 600; display: block; margin-bottom: 4px;"
            >
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
              style="width: 80px; padding: 4px 6px; border: 1px solid #ccc; border-radius: 3px;"
            />
            <span style="margin-left: 6px; color: #666; font-size: 12px;">
              °N (negative = °S)
            </span>
          </div>
        </div>
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
      <div style="font-size: 13px; color: #444; margin: 8px 0; display: flex; gap: 12px; align-items: center; flex-wrap: wrap;">
        <span :if={not @initialized?} style="color: #888; font-style: italic;">
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
          style="display: contents;"
        >
        </div>
        <.link
          :if={
            @filters.display_mode in [:data_table, :species_list] and
              @observations != []
          }
          id="phenology-csv-link"
          phx-hook="PhenologyCsvLink"
          href={export_path(@filters, nil)}
          data-href-base={export_path(@filters, nil)}
          style="font-size: 12px; color: #2b5e3a; text-decoration: underline;"
        >
          Download CSV
        </.link>
      </div>

      <%= cond do %>
        <% not @initialized? -> %>
          <div style="padding: 40px; text-align: center; color: #888;
                      border: 1px solid #ddd; background: #fff; border-radius: 4px;">
            Loading observations…
          </div>
        <% @observations == [] -> %>
          <div style="padding: 40px; text-align: center; color: #888;
                      border: 1px solid #ddd; background: #fff; border-radius: 4px;">
            No observations match these filters.
          </div>
        <% true -> %>
          <div
            id="phenology-chart"
            phx-hook="PhenologyChart"
            phx-update="ignore"
            data-points={@chart_points_json}
            style="height: 540px; border: 1px solid #ddd; background: #fff;
                 border-radius: 4px; position: relative;"
          >
          </div>
          <p style="margin: 4px 0 0; color: #666; font-size: 11px;">
            Drag on the chart to brush-select observations into the table /
            species list below. Click outside the brush to clear.
          </p>

          <%= cond do %>
            <% @filters.display_mode == :data_table -> %>
              <div
                id="phenology-table-host"
                phx-hook="PhenologyTable"
                phx-update="ignore"
                data-mode="table"
                data-version={@obs_version}
                style="margin-top: 12px; max-height: 60vh; overflow: auto; border: 1px solid #ddd; background: #fff; border-radius: 4px;"
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
                style="margin-top: 12px; max-height: 60vh; overflow: auto; border: 1px solid #ddd; background: #fff; border-radius: 4px;"
              >
                <%!-- SSR / no-JS fallback only — see comment on the
                      obs-table host above. --%>
                <.table
                  id="phenology-species-table"
                  rows={species_rows(@observations)}
                  variant="compact"
                >
                  <:col :let={row} label="Species">
                    <.link href={~p"/gall/#{row.species_id}"}>{row.name}</.link>
                  </:col>
                  <:col :let={row} label="Observations">{row.n_obs}</:col>
                </.table>
              </div>
            <% true -> %>
              <%= if @predictions != [] do %>
                <div
                  id="phenology-predictions"
                  style="margin-top: 12px; padding: 10px 12px; background: #f5f3ec;
                       border: 1px solid #ddd; border-radius: 4px; font-size: 13px;"
                >
                  <div style="font-weight: 600; margin-bottom: 6px;">
                    Predicted windows at {format_target_lat(@filters[:target_lat])}°{lat_hemisphere(
                      @filters[:target_lat]
                    )}
                  </div>
                  <ul style="margin: 0; padding-left: 18px;">
                    <li :for={p <- @predictions} style="margin-bottom: 2px;">
                      {prediction_sentence(p)}
                    </li>
                  </ul>
                  <span style="display: block; color: #666; font-size: 11px; margin-top: 4px;">
                    Based on the seasind IQR of matched observations, back-projected
                    to your latitude. Predictions are NH-temperate-calibrated — see
                    <a href="https://github.com/Megachile/gallformers/issues/1">
                      issue #1
                    </a>
                    for the SH validation roadmap.
                  </span>
                </div>
              <% end %>
          <% end %>
      <% end %>
    </div>
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
