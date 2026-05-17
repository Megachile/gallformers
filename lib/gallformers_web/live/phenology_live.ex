defmodule GallformersWeb.PhenologyLive do
  @moduledoc """
  Public phenology explorer. Picks a single gall species and renders its
  observations as a DOY × latitude scatter. Multi-species + trait filters
  + season-index overlay come in follow-up commits.

  Replaces the standalone Shiny app at gallphen.org with an in-app
  experience that lives next to the rest of gallformers' data.
  """
  use GallformersWeb, :live_view

  alias Gallformers.Phenology
  alias Gallformers.Phenology.Observation

  @impl true
  def mount(params, _session, socket) do
    species_with_counts = Phenology.list_species_with_counts()

    initial_species_id =
      case params["species_id"] do
        nil ->
          case species_with_counts do
            [%{species_id: id} | _] -> id
            _ -> nil
          end

        id_str ->
          case Integer.parse(id_str) do
            {id, ""} -> id
            _ -> nil
          end
      end

    socket =
      socket
      |> assign(
        page_title: "Phenology",
        page_description:
          "Phenology of gall-forming species: when galls appear, mature, and emerge across latitudes.",
        page_url: "/phenology",
        page_image: nil,
        page_json_ld: nil,
        species_with_counts: species_with_counts,
        selected_species_id: initial_species_id,
        selected_species: nil,
        observations: []
      )
      |> load_selected_species()

    {:ok, socket}
  end

  @impl true
  def handle_event("select_species", %{"species_id" => id_str}, socket) do
    case Integer.parse(id_str) do
      {id, ""} ->
        {:noreply,
         socket
         |> assign(selected_species_id: id)
         |> load_selected_species()}

      _ ->
        {:noreply, socket}
    end
  end

  defp load_selected_species(%{assigns: %{selected_species_id: nil}} = socket) do
    assign(socket, observations: [], selected_species: nil)
  end

  defp load_selected_species(socket) do
    id = socket.assigns.selected_species_id
    obs = Phenology.list_observations_for_species(id)

    species = Enum.find(socket.assigns.species_with_counts, &(&1.species_id == id))

    assign(socket, observations: obs, selected_species: species)
  end

  # ----------------------------------------------------------------------
  # Helpers (chart data + display formatting)
  # ----------------------------------------------------------------------

  @doc false
  def chart_points(observations) do
    Enum.map(observations, fn %Observation{} = o ->
      %{
        doy: o.doy,
        lat: o.latitude,
        date: Date.to_iso8601(o.date),
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

  # ----------------------------------------------------------------------
  # Render
  # ----------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="phenology-page" style="max-width: 1200px; margin: 0 auto; padding: 16px;">
      <h1 style="margin: 0 0 4px 0;">Phenology</h1>
      <p style="color: #666; margin-top: 0;">
        Day-of-year × latitude scatter for each gall species' observations.
        Colored by generation (blue&nbsp;= sexual, red&nbsp;= agamic, gray&nbsp;= unknown).
      </p>

      <form phx-change="select_species" style="margin: 12px 0;">
        <label for="species_id" style="font-weight: 600;">Species:</label>
        <select
          name="species_id"
          id="species_id"
          style="min-width: 360px; padding: 4px 6px; margin-left: 6px;"
        >
          <%= for sp <- @species_with_counts do %>
            <option value={sp.species_id} selected={sp.species_id == @selected_species_id}>
              {sp.name} ({sp.n_obs})
            </option>
          <% end %>
        </select>
        <span style="margin-left: 12px; color: #666; font-size: 12px;">
          {length(@species_with_counts)} species with phenology data
        </span>
      </form>

      <%= if @selected_species do %>
        <div style="font-size: 13px; color: #444; margin-bottom: 8px;">
          <em>{@selected_species.name}</em>
          — generation: <strong>{generation_of(@selected_species.name)}</strong>
          — {length(@observations)} observations
        </div>

        <div
          id="phenology-chart"
          phx-hook="PhenologyChart"
          phx-update="ignore"
          data-points={Jason.encode!(chart_points(@observations))}
          data-generation={generation_of(@selected_species.name)}
          data-species-name={@selected_species.name}
          style="height: 540px; border: 1px solid #ddd; background: #fff; border-radius: 4px;"
        >
        </div>
      <% else %>
        <div style="padding: 40px; text-align: center; color: #888;">
          No species selected.
        </div>
      <% end %>
    </div>
    """
  end
end
