defmodule GallformersWeb.PhenologyComponents do
  @moduledoc """
  Compact, page-embedded phenology components.

  Right now: `phenology_summary/1`, an inobtrusive card for the species
  detail page that shows observation count + a per-phenophase active-window
  prediction (IQR of day-of-year) when there are enough samples, with a
  link to the full explorer page.
  """
  use Phoenix.Component

  alias Gallformers.Phenology.Math, as: PhenologyMath

  # Threshold: don't compute a window unless we have at least this many
  # observations for a given phenophase. Below this the IQR is too noisy
  # to be meaningfully predictive.
  @min_obs_for_window 8

  # Tolerance around the observed-latitude range when deciding whether to
  # honor a viewer-entered lat. Mild extrapolation (a few degrees) is fine;
  # at larger gaps the seasind back-projection becomes guesswork. Tuned by
  # feel — adjust here if the gate feels too chatty / too permissive.
  @lat_range_buffer_deg 5.0

  attr :species_id, :integer, required: true

  attr :observations, :list,
    required: true,
    doc: "List of plain maps from PhenologyComponents.to_summary_map/1"

  attr :target_lat, :any,
    default: nil,
    doc:
      "Optional latitude (number or numeric string); switches windows to seasind-based predictions back-projected to that lat"

  def phenology_summary(assigns) do
    target_lat = parse_lat(assigns.target_lat)
    {windows, gate_message} = build_windows(assigns.observations, target_lat)

    assigns =
      assigns
      |> assign(:n_total, length(assigns.observations))
      |> assign(:source_breakdown, source_breakdown(assigns.observations))
      |> assign(:target_lat_parsed, target_lat)
      |> assign(:target_lat_input, format_lat_input(assigns.target_lat))
      |> assign(:windows, windows)
      |> assign(:gate_message, gate_message)
      |> assign(:min_obs_for_window, @min_obs_for_window)

    ~H"""
    <div class="border border-gray-200 rounded-lg p-3 bg-white">
      <div class="flex items-center justify-between mb-1">
        <h3 class="font-semibold text-gray-800">Phenology</h3>
        <.link
          :if={@n_total > 0}
          href={"/phenology?species_id=#{@species_id}"}
          class="text-sm text-gf-maroon hover:underline"
        >
          View chart →
        </.link>
      </div>

      <p :if={@n_total == 0} class="text-sm text-gray-500 italic">
        No phenology observations recorded yet for this species.
      </p>

      <p :if={@n_total > 0} class="text-sm text-gray-600">
        {@n_total} observation{if @n_total != 1, do: "s"}
        <span :if={@source_breakdown != ""}>· {@source_breakdown}</span>
      </p>

      <form
        :if={@n_total > 0}
        phx-change="set_phenology_lat"
        phx-submit="set_phenology_lat"
        class="mt-2 flex items-center gap-2 text-sm"
      >
        <label for="phenology_target_lat" class="text-gray-600">
          Predict for latitude:
        </label>
        <input
          type="number"
          step="0.1"
          min="-90"
          max="90"
          name="target_lat"
          id="phenology_target_lat"
          value={@target_lat_input}
          placeholder="e.g. 42"
          phx-debounce="500"
          class="w-20 px-2 py-0.5 border border-gray-300 rounded text-right"
        />
        <span class="text-xs text-gray-500">
          ° (positive&nbsp;= N, negative&nbsp;= S; blank&nbsp;= averaged across all obs)
        </span>
      </form>

      <div :if={@windows != []} class="mt-2 space-y-0.5 text-sm">
        <div :for={w <- @windows} class="text-gray-700">
          <span class="font-medium">{w.phenophase}</span>: {w.start_label} – {w.end_label}
          <span class="text-xs text-gray-500">{w.qualifier}</span>
        </div>
      </div>

      <p
        :if={@gate_message != nil}
        class="mt-1 text-xs text-gray-500 italic"
      >
        {@gate_message}
      </p>

      <p
        :if={@n_total > 0 and @windows == [] and @gate_message == nil}
        class="mt-1 text-xs text-gray-500 italic"
      >
        Not enough samples per phenophase yet to predict active windows
        (need ≥ {@min_obs_for_window} each).
      </p>
    </div>
    """
  end

  @doc """
  Converts an `Observation` schema struct into the plain map the component
  expects. Kept out of the component so the component stays a pure rendering
  function with no schema dependency.
  """
  def to_summary_map(obs) do
    %{
      doy: obs.doy,
      phenophase: obs.phenophase,
      source_type: obs.source_type,
      latitude: obs.latitude,
      seasind: obs.seasind
    }
  end

  # ----------------------------------------------------------------------
  # Helpers
  # ----------------------------------------------------------------------

  defp source_breakdown(observations) do
    observations
    |> Enum.frequencies_by(& &1.source_type)
    |> Enum.sort_by(fn {_t, n} -> -n end)
    |> Enum.map_join(", ", fn {t, n} -> "#{n} #{t}" end)
  end

  # Dispatches: with a parsed target_lat, predicts via seasind back-projection
  # (gated on viewer-lat-in-observed-range and the viewer's hemisphere having
  # data); without one, falls back to plain DOY-IQR across all observations.
  #
  # Returns `{windows, gate_message}` where `gate_message` is nil unless the
  # lat-gated path refused to predict, in which case `windows == []` and the
  # message explains why.
  defp build_windows(observations, nil), do: {phenophase_windows_doy(observations), nil}
  defp build_windows(observations, lat), do: phenophase_windows_at_lat(observations, lat)

  # DOY-IQR fallback: ignores latitude entirely. Returns the same shape as
  # the lat-adjusted version (with a "(IQR, n=X)" qualifier).
  defp phenophase_windows_doy(observations) do
    observations
    |> Enum.reject(&(is_nil(&1.phenophase) or &1.phenophase == ""))
    |> Enum.group_by(& &1.phenophase)
    |> Enum.filter(fn {_p, group} -> length(group) >= @min_obs_for_window end)
    |> Enum.map(fn {pheno, group} ->
      doys = group |> Enum.map(& &1.doy) |> Enum.sort()
      {q1, q3} = iqr(doys)

      %{
        phenophase: pheno,
        start_label: doy_label(q1),
        end_label: doy_label(q3),
        start_doy: q1,
        n: length(group),
        qualifier: "(IQR, n=#{length(group)})"
      }
    end)
    |> Enum.sort_by(& &1.start_doy)
    |> Enum.map(&Map.delete(&1, :start_doy))
  end

  # Lat-adjusted: filter obs to the viewer's hemisphere, refuse if that
  # leaves zero obs or if the viewer's lat is outside the hemisphere's
  # observed-lat range (with a small buffer). Otherwise compute a seasind
  # IQR per phenophase from the hemisphere-filtered obs and back-project
  # to DOY at the target latitude. Hemisphere bucketing is structurally
  # important: pooling NH and SH observations would average across the
  # ~6-month phase flip — see GH issue #1.
  defp phenophase_windows_at_lat(observations, target_lat) do
    same_hem = Enum.filter(observations, &same_hemisphere?(&1, target_lat))

    case observed_lat_range(same_hem) do
      :empty ->
        {[], "No observations in your hemisphere for this species yet."}

      {lo, hi} ->
        if target_lat < lo - @lat_range_buffer_deg or target_lat > hi + @lat_range_buffer_deg do
          {[],
           "No observations near this latitude — observed range for this species is " <>
             "#{format_lat_label(lo)} to #{format_lat_label(hi)}."}
        else
          {windows_from_seasind(same_hem, target_lat), nil}
        end
    end
  end

  # Builds the actual per-phenophase windows from a pre-filtered observation
  # set. Skips obs missing seasind (legacy rows we couldn't compute).
  defp windows_from_seasind(observations, target_lat) do
    observations
    |> Enum.reject(&(is_nil(&1.phenophase) or &1.phenophase == "" or is_nil(&1.seasind)))
    |> Enum.group_by(& &1.phenophase)
    |> Enum.filter(fn {_p, group} -> length(group) >= @min_obs_for_window end)
    |> Enum.map(fn {pheno, group} ->
      seasinds = group |> Enum.map(& &1.seasind) |> Enum.sort()
      {si_q1, si_q3} = iqr(seasinds)

      q1_doy = PhenologyMath.doy_for_seasind(si_q1, target_lat)
      q3_doy = PhenologyMath.doy_for_seasind(si_q3, target_lat)

      %{
        phenophase: pheno,
        start_label: doy_label(q1_doy),
        end_label: doy_label(q3_doy),
        start_doy: q1_doy,
        n: length(group),
        qualifier: "(at #{format_lat_label(target_lat)}, from seasind IQR of n=#{length(group)})"
      }
    end)
    |> Enum.sort_by(& &1.start_doy)
    |> Enum.map(&Map.delete(&1, :start_doy))
  end

  # Hemisphere classification: treat lat == 0 as NH so the classification
  # is total and zero falls on the same side as the bulk of our current
  # data. Obs with nil latitude are excluded (we can't place them on
  # either side).
  defp same_hemisphere?(%{latitude: nil}, _target_lat), do: false

  defp same_hemisphere?(%{latitude: obs_lat}, target_lat),
    do: hemisphere(obs_lat) == hemisphere(target_lat)

  defp hemisphere(lat) when lat < 0, do: :south
  defp hemisphere(_), do: :north

  # Min/max latitude across the given obs, ignoring nil latitudes. Returns
  # `:empty` if there are no usable obs.
  defp observed_lat_range(observations) do
    lats =
      observations
      |> Enum.map(& &1.latitude)
      |> Enum.reject(&is_nil/1)

    case lats do
      [] -> :empty
      _ -> {Enum.min(lats), Enum.max(lats)}
    end
  end

  # Simple "nearest rank" percentile — good enough for an inobtrusive
  # widget; the full explorer can use a fancier estimator later.
  defp iqr(sorted_values) do
    n = length(sorted_values)
    q1_idx = max(0, round((n - 1) * 0.25))
    q3_idx = min(n - 1, round((n - 1) * 0.75))
    {Enum.at(sorted_values, q1_idx), Enum.at(sorted_values, q3_idx)}
  end

  defp doy_label(doy) when is_integer(doy) and doy >= 1 and doy <= 366 do
    # 2024 was a leap year — supports doy 366. Format as "Jan 5".
    ~D[2024-01-01]
    |> Date.add(doy - 1)
    |> Calendar.strftime("%b %-d")
  end

  defp doy_label(_), do: "?"

  # Parse latitude from form input (which arrives as string). Returns nil for
  # blank / unparseable / out-of-range values so the widget falls back to the
  # DOY-IQR view rather than rendering garbage.
  defp parse_lat(nil), do: nil
  defp parse_lat(""), do: nil

  defp parse_lat(value) when is_binary(value) do
    case Float.parse(String.trim(value)) do
      {f, ""} -> validate_lat(f)
      {f, _rest} -> validate_lat(f)
      :error -> nil
    end
  end

  defp parse_lat(value) when is_number(value), do: validate_lat(value * 1.0)
  defp parse_lat(_), do: nil

  defp validate_lat(f) when f >= -90.0 and f <= 90.0, do: f
  defp validate_lat(_), do: nil

  defp format_lat_input(nil), do: ""
  defp format_lat_input(""), do: ""

  defp format_lat_input(value) when is_binary(value) do
    case parse_lat(value) do
      nil -> ""
      f -> format_lat(f)
    end
  end

  defp format_lat_input(value) when is_number(value), do: format_lat(value)
  defp format_lat_input(_), do: ""

  defp format_lat(f) when is_float(f), do: :erlang.float_to_binary(f, [:compact, decimals: 2])
  defp format_lat(f), do: to_string(f)

  # Display latitude as "42.5°N" / "37.8°S" using sign. Zero is rendered as
  # "0°N" to match the hemisphere classification.
  defp format_lat_label(lat) when is_number(lat) and lat < 0,
    do: "#{format_lat(-lat * 1.0)}°S"

  defp format_lat_label(lat) when is_number(lat),
    do: "#{format_lat(lat * 1.0)}°N"
end
