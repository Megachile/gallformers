defmodule GallformersWeb.PhenologyComponents do
  @moduledoc """
  Phenology presentation shared by the compact gall panel and full explorer.
  Receives prediction results; contains no fitting or database access.
  """
  use Phoenix.Component

  import GallformersWeb.CoreComponents, only: [button: 1, input: 1]
  import GallformersWeb.Helpers, only: [valid_url?: 1]

  attr :species_id, :integer, required: true
  attr :open, :boolean, default: false
  attr :count, :integer, default: 0
  attr :predictions, :list, default: []
  attr :target_lat, :any, default: nil
  attr :notice, :string, default: nil
  attr :points_json, :string, default: "[]"
  attr :sources, :map, default: %{}

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
          <p :if={@sources != %{}} class="text-xs text-gray-500 mt-1">
            {Enum.map_join(Enum.sort(@sources), " · ", fn {source, n} ->
              "#{n} #{source_label(source)}"
            end)}
          </p>
          <div class="grid md:grid-cols-2 gap-4 mt-3">
            <div class="min-w-0">
              <.chart
                id="gall-phenology-chart"
                points_json={@points_json}
                predictions={@predictions}
                selection={false}
                class="h-[420px]"
              />
              <p :if={@predictions != []} class="mt-1 text-xs text-gray-500">
                Solid: fresh gall onset. Dashed: emergence. Dotted: viable collections.
              </p>
            </div>
            <div class="min-w-0">
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
        </div>
      </div>
    </section>
    """
  end

  attr :id, :string, required: true
  attr :points_json, :string, required: true
  attr :predictions, :list, default: []
  attr :lat_range, :any, default: nil
  attr :selection, :boolean, default: true
  attr :class, :string, default: "h-[540px]"

  @doc "One chart hook for the explorer and read-only gall panel."
  def chart(assigns) do
    ~H"""
    <div
      id={@id}
      phx-hook="PhenologyChart"
      phx-update="ignore"
      data-points={@points_json}
      data-lat-range={if @lat_range, do: Jason.encode!(@lat_range)}
      data-predictions={Jason.encode!(@predictions)}
      data-selection-enabled={to_string(@selection)}
      class={["relative rounded-lg border border-gray-200 bg-white", @class]}
      role="figure"
      aria-label="Phenology observations by date and latitude"
    >
    </div>
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
        <span class="font-medium">{event_label(p.event)} · {generation_label(p.generation)}</span>:
        <span :if={p.event == :onset}>around {doy_label(p.low_doy)}</span>
        <span :if={p.event != :onset}>{doy_label(p.low_doy)}–{doy_label(p.high_doy)}</span>
        <span :if={p.event != :onset} class="text-gray-600">(middle 50%)</span>
        <.onset_anchor
          :if={p.event == :onset}
          anchor={p.anchor}
          adjusted={p.low_doy != p.fallback_doy}
        />
        <span :if={Map.has_key?(p, :median_doy)} class="block text-gray-600">
          Middle 80% {doy_label(p.outer_low_doy)}–{doy_label(p.outer_high_doy)};
          median {doy_label(p.median_doy)}.
        </span>
        <span class="block text-xs text-gray-500">
          {p.n} distinct date/location {if p.n == 1, do: "record", else: "records"}.
          <span :if={p.sparse?}>Few records; season timing may be incomplete.</span>
          <span :if={p.event == :onset && p.local_onset_weight < 0.2} class="block text-amber-800">
            Little local onset evidence; this date relies on the seasonal-clock fallback.
          </span>
          <span :if={p.extrapolated?} class="block text-amber-800">
            Extrapolation: {latitude_label(p.target_lat)} is outside the recorded range
            ({latitude_range(p)}). Timing at this latitude is unverified.
          </span>
          <span
            :if={!p.extrapolated? && p.observed_max_lat - p.observed_min_lat < 2}
            class="block text-amber-800"
          >
            Limited latitude coverage ({latitude_range(p)}); timing elsewhere is uncertain.
          </span>
          <span :if={p.excluded_n > 0}>
            {p.excluded_n} records lack supported dates or coordinates.
          </span>
        </span>
      </li>
    </ul>
    """
  end

  attr :anchor, :map, required: true
  attr :adjusted, :boolean, required: true

  defp onset_anchor(assigns) do
    assigns =
      assign(
        assigns,
        :url,
        Enum.find([assigns.anchor[:page_url], assigns.anchor[:source_url]], &valid_url?/1)
      )

    ~H"""
    <span class="block text-xs text-gray-600">
      <span :if={!@adjusted}>Earliest recorded development, latitude-adjusted.</span>
      <span :if={@adjusted}>Seasonal clock adjusted using early records (pilot).</span>
      <.link
        :if={@url}
        href={@url}
        target="_blank"
        rel="noopener"
        class="text-gf-maroon hover:underline"
      >
        {if @adjusted, do: "Fallback anchor", else: "Anchor record"} ↗
      </.link>
      {Calendar.strftime(@anchor.date, "%b %-d, %Y")} at {latitude_label(@anchor.latitude)}.
    </span>
    """
  end

  defp source_label("inat"), do: "iNaturalist"
  defp source_label("literature"), do: "literature"
  defp source_label(source), do: source || "unspecified source"

  defp latitude_label(lat), do: "#{Float.round(lat / 1, 1)}°N"

  defp latitude_range(p) do
    if Float.round(p.observed_min_lat / 1, 1) == Float.round(p.observed_max_lat / 1, 1),
      do: latitude_label(p.observed_min_lat),
      else: "#{latitude_label(p.observed_min_lat)}–#{latitude_label(p.observed_max_lat)}"
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
