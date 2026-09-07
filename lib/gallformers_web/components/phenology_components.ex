defmodule GallformersWeb.PhenologyComponents do
  @moduledoc """
  Phenology presentation shared by the compact gall panel and full explorer.
  Receives prediction results; contains no fitting or database access.
  """
  use Phoenix.Component

  import GallformersWeb.CoreComponents, only: [button: 1, input: 1]

  attr :species_id, :integer, required: true
  attr :open, :boolean, default: false
  attr :count, :integer, default: 0
  attr :predictions, :list, default: []
  attr :target_lat, :any, default: nil
  attr :notice, :string, default: nil

  @doc "Collapsible gall-page panel; the parent loads evidence on first expansion."
  def phenology_summary(assigns) do
    assigns = assign(assigns, :form, to_form(%{"target_lat" => assigns.target_lat}))

    ~H"""
    <section id="gall-phenology" class="border border-gray-200 rounded-lg p-3 bg-white">
      <.button
        id="toggle-phenology"
        variant="ghost"
        size="sm"
        phx-click="toggle_phenology"
        aria-expanded={to_string(@open)}
        aria-controls="gall-phenology-content"
      >
        Phenology {if @open, do: "−", else: "+"}
      </.button>
      <div :if={@open} id="gall-phenology-content" class="mt-2 text-sm">
        <p :if={@count == 0} class="text-gray-500">
          No phenology observations recorded yet for this species.
        </p>
        <div :if={@count > 0}>
          <div class="flex items-center justify-between">
            <span>{@count} observations</span>
            <.link
              href={explorer_path(@species_id, @target_lat)}
              class="text-gf-maroon hover:underline"
            >
              View full chart →
            </.link>
          </div>
          <.form
            for={@form}
            id="gall-phenology-latitude"
            phx-change="set_phenology_lat"
            phx-submit="set_phenology_lat"
          >
            <div class="mt-2 max-w-48">
              <.input
                field={@form[:target_lat]}
                id="phenology_target_lat"
                type="number"
                label="Latitude (°N)"
                min="25"
                max="55"
                step="0.1"
                placeholder="e.g. 42"
                phx-debounce="500"
              />
            </div>
          </.form>
          <.prediction_results predictions={@predictions} />
          <p :if={@notice} class="mt-2 text-xs text-gray-500" role="status">{@notice}</p>
          <p :if={@predictions != []} class="mt-2 text-xs text-gray-500">
            Latitude-only estimate; no elevation, host or year adjustment.
          </p>
        </div>
      </div>
    </section>
    """
  end

  attr :predictions, :list, required: true

  @doc "Shared date outputs and evidence limitations for both displays."
  def prediction_results(assigns) do
    ~H"""
    <ul class="mt-2 space-y-2">
      <li
        :for={p <- @predictions}
        data-event={p.event}
        data-generation={p.generation}
        data-low-doy={p.low_doy}
        data-high-doy={p.high_doy}
      >
        <span class="font-medium">{event_label(p.event)} · {generation_label(p.generation)}</span>: {doy_label(
          p.low_doy
        )}–{doy_label(p.high_doy)}
        <span :if={p.event != :onset} class="text-gray-600">(middle 50%)</span>
        <span :if={p.event == :onset} class="text-gray-600">
          (5th–10th percentile onset estimate)
        </span>
        <span :if={Map.has_key?(p, :median_doy)} class="block text-gray-600">
          Middle 80% {doy_label(p.outer_low_doy)}–{doy_label(p.outer_high_doy)};
          median {doy_label(p.median_doy)}.
        </span>
        <span class="block text-xs text-gray-500">
          {p.n} distinct date/locality records · {p.cells} geographic cells.
          <span :if={p.sparse?}>Sparse evidence: not a reliable season boundary.</span>
          <span :if={p.cells == 1}>One-cell geographic coverage.</span>
          <span :if={p.extrapolated?}>Extrapolated beyond observed latitudes.</span>
          <span :if={p.excluded_n > 0}>
            {p.excluded_n} records lack supported dates or coordinates.
          </span>
        </span>
      </li>
    </ul>
    """
  end

  defp explorer_path(id, lat) do
    query = %{species_id: id, events: "onset,emergence,rearing"}
    query = if lat in [nil, ""], do: query, else: Map.put(query, :lat, lat)
    "/phenology?" <> URI.encode_query(query)
  end

  defp event_label(:onset), do: "Fresh gall onset"
  defp event_label(:emergence), do: "Adult emergence"
  defp event_label(:rearing), do: "Viable collections"

  defp generation_label(:sexgen), do: "sexual"
  defp generation_label(:agamic), do: "agamic"
  defp generation_label(:unknown), do: "generation unspecified"

  defp doy_label(day) do
    ~D[2023-01-01] |> Date.add(day - 1) |> Calendar.strftime("%b %-d")
  end
end
