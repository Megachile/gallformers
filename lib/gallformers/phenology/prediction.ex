defmodule Gallformers.Phenology.Prediction do
  @moduledoc """
  Per-generation phenology window predictions from observation seasind IQRs.

  For each generation (`:sexgen` / `:agamic` / `:unknown`) and event type
  (`:rearing` / `:emergence`), computes a low/high day-of-year pair at the
  viewer's chosen latitude based on the seasind IQR of the matching
  observations. Used to drive the chart's prediction-line text outputs
  ("At 42°N, adults of the sexual generation are expected to emerge
  between Apr 12 and Jun 8") in the `/phenology` explorer.

  Mirrors the scientific intent of the legacy R/Shiny `doyCalc` viewer
  (`lineCalc` + `doyLatCalc`) but replaces the precomputed seasind/acchours
  grid lookup with on-the-fly calls into `Gallformers.Phenology.Math`.
  """

  alias Gallformers.Phenology.Math, as: PhenologyMath

  # Minimum observations per (generation, event) bucket to compute a window.
  # Below this the IQR is too noisy to surface a prediction.
  @min_obs 4

  # Phenophase values considered "emergence" of the inducer from the gall.
  # Matches the Shiny app's grouping (Adult was renamed Free-living in our
  # data; the other two map directly).
  @emergence_phenophases ~w(maturing perimature Free-living)

  @generations [:sexgen, :agamic, :unknown]
  @events [:rearing, :emergence]

  @typedoc """
  One prediction row per (generation, event) bucket with enough obs.
  """
  @type prediction :: %{
          generation: :sexgen | :agamic | :unknown,
          event: :rearing | :emergence,
          n: pos_integer(),
          target_lat: number(),
          low_doy: integer(),
          high_doy: integer()
        }

  @doc """
  Returns predictions for all (generation, event) combinations present in
  the observation set, at the given target latitude. Skips combinations
  that don't have at least `@min_obs` obs with non-nil seasind.

  Each observation is expected to be a map with `:species_name` (for
  generation parsing), `:phenophase`, `:viability`, and `:seasind`.
  """
  @spec predictions_for(list(map()), number()) :: [prediction()]
  def predictions_for(observations, target_lat) when is_number(target_lat) do
    for gen <- @generations,
        event <- @events,
        prediction = predict_one(observations, gen, event, target_lat),
        not is_nil(prediction),
        do: prediction
  end

  def predictions_for(_, _), do: []

  defp predict_one(observations, gen, event, target_lat) do
    obs =
      observations
      |> Enum.filter(&(generation_of(&1) == gen))
      |> filter_by_event(event)
      |> Enum.reject(&seasind_missing?/1)

    if length(obs) >= @min_obs do
      seasinds = obs |> Enum.map(&Map.get(&1, :seasind)) |> Enum.sort()
      {q1, q3} = iqr(seasinds)

      %{
        generation: gen,
        event: event,
        n: length(obs),
        target_lat: target_lat,
        low_doy: PhenologyMath.doy_for_seasind(q1, target_lat),
        high_doy: PhenologyMath.doy_for_seasind(q3, target_lat)
      }
    end
  end

  defp filter_by_event(obs, :rearing),
    do: Enum.filter(obs, &(Map.get(&1, :viability) == "viable"))

  defp filter_by_event(obs, :emergence),
    do: Enum.filter(obs, &(Map.get(&1, :phenophase) in @emergence_phenophases))

  defp seasind_missing?(o) do
    case Map.get(o, :seasind) do
      nil -> true
      "" -> true
      _ -> false
    end
  end

  # Same as the LV's generation_of/1 — derived from the species name suffix.
  defp generation_of(%{species_name: name}) when is_binary(name) do
    cond do
      String.contains?(name, "(sexgen)") -> :sexgen
      String.contains?(name, "(agamic)") -> :agamic
      true -> :unknown
    end
  end

  defp generation_of(_), do: :unknown

  # Nearest-rank quartile (matches the widget's iqr/1).
  defp iqr(sorted) do
    n = length(sorted)
    q1_idx = max(0, round((n - 1) * 0.25))
    q3_idx = min(n - 1, round((n - 1) * 0.75))
    {Enum.at(sorted, q1_idx), Enum.at(sorted, q3_idx)}
  end
end
