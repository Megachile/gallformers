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
  alias Gallformers.Phenology.Observation
  alias Gallformers.Species

  @phenophases Observation.phenophases()
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
        all_phenophases: @phenophases,
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

  # Parse filters from URL params on mount. Supports back-compat with the
  # legacy `?species_id=N` pattern (used by the per-gall widget's "View
  # chart →" link) by translating it into a single search term.
  defp filters_from_params(params) do
    %{
      search: parse_search(params["search"]) || species_id_to_search(params["species_id"]),
      generation: parse_generation(params["gen"]),
      phenophases: parse_phenophases(params["phen"])
    }
  end

  defp filters_from_form(form_params, prior) do
    %{
      search: parse_search(form_params["search"]) || prior.search,
      generation: parse_generation(form_params["generation"]),
      phenophases: parse_phenophases(form_params["phenophases"])
    }
  end

  defp parse_search(nil), do: nil
  defp parse_search(""), do: nil

  defp parse_search(value) when is_binary(value) do
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

  defp parse_search(_), do: nil

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

  defp parse_phenophases(nil), do: []
  defp parse_phenophases(""), do: []

  defp parse_phenophases(value) when is_list(value) do
    Enum.filter(value, &(&1 in @phenophases))
  end

  defp parse_phenophases(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 in @phenophases))
  end

  # Build a query-param keyword list reflecting the current filters. Skips
  # default / empty values so a clean default state produces a clean URL.
  defp filters_to_query(filters) do
    []
    |> maybe_put_search(filters[:search])
    |> maybe_put_gen(filters[:generation])
    |> maybe_put_phen(filters[:phenophases])
  end

  defp maybe_put_search(query, nil), do: query
  defp maybe_put_search(query, []), do: query

  defp maybe_put_search(query, terms) when is_list(terms),
    do: query ++ [search: Enum.join(terms, ",")]

  defp maybe_put_gen(query, :all), do: query

  defp maybe_put_gen(query, gen) when gen in [:sexgen, :agamic],
    do: query ++ [gen: Atom.to_string(gen)]

  defp maybe_put_gen(query, _), do: query

  defp maybe_put_phen(query, nil), do: query
  defp maybe_put_phen(query, []), do: query

  defp maybe_put_phen(query, phens) when is_list(phens),
    do: query ++ [phen: Enum.join(phens, ",")]

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
              <%= for p <- @all_phenophases do %>
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
              No selection = no phenophase filter (all phenophases included).
            </span>
          </fieldset>
        </div>
      </form>

      <div style="font-size: 13px; color: #444; margin: 8px 0;">
        {length(@observations)} observation{if length(@observations) != 1, do: "s"} across {species_count(
          @observations
        )} species
      </div>

      <%= if @observations == [] do %>
        <div style="padding: 40px; text-align: center; color: #888;
                    border: 1px solid #ddd; background: #fff; border-radius: 4px;">
          No observations match these filters.
        </div>
      <% else %>
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
end
