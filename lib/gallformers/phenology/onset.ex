defmodule Gallformers.Phenology.Onset do
  @moduledoc """
  Evidence-weighted local correction to the earliest-record seasonal fallback.

  Five-degree latitude bands supply earliest normalized records. Correction
  knots are spaced five degrees apart, centered on the fallback anchor, so
  interpolation cannot create one-degree local bends.
  Only records within fourteen days of that edge support the correction, with
  one contribution per quarter-degree locality/year and at most two per year.
  Isolated edges keep the fallback; repeated edges increasingly influence it.
  Smooth interpolation preserves the earliest anchor and cannot overshoot the
  neighboring corrections. Beyond support, the clock's shape continues from the
  nearest adjusted edge; resetting to the distant global anchor would introduce
  artificial reversals. Local evidence weight falls to zero away from support.

  These fixed pilot heuristics are not calibrated confidence probabilities.
  Inputs are already filtered, deduplicated and unwrapped onto a common clock.
  """
  alias Gallformers.Phenology.SeasonalClock, as: Clock

  @spacing_degrees 5
  @early_days 14
  @fade_degrees 4
  @prior_support 2

  @doc "Prepare a small correction curve from observation/seasonal-phase pairs."
  def fit(records) do
    {anchor, fallback} =
      Enum.min_by(records, fn {o, phase} -> {phase, o.date, o.latitude, o.longitude} end)

    latitudes =
      -6..6
      |> Enum.map(&(anchor.latitude + &1 * @spacing_degrees))
      |> Enum.filter(&Clock.supported_latitude?/1)

    nodes =
      records
      |> Enum.group_by(fn {o, _} -> Enum.min_by(latitudes, &abs(o.latitude - &1)) end)
      |> Enum.map(fn {lat, local} -> edge(local, fallback, lat) end)
      |> Enum.filter(&(&1.weight > 0 or &1.edge == fallback))
      |> Enum.sort_by(& &1.lat)

    %{fallback: fallback, nodes: nodes}
  end

  defp edge(records, fallback, lat) do
    {_, phase} = Enum.min_by(records, fn {o, p} -> {p, o.latitude, o.longitude, o.date} end)
    first_day = Clock.inverse(phase, lat)

    early =
      Enum.filter(records, fn {_, p} ->
        Clock.inverse(p, lat) - first_day <= @early_days
      end)

    local_years =
      early
      |> Enum.map(fn {o, _} -> {round(o.latitude * 4), round(o.longitude * 4), o.date.year} end)
      |> Enum.uniq()

    years = local_years |> Enum.map(&elem(&1, 2)) |> Enum.uniq() |> length()
    support = max(0, min(length(local_years), 2 * years) - 1)
    weight = support / (support + @prior_support)

    %{lat: lat, correction: weight * (phase - fallback), weight: weight, edge: phase}
  end

  @doc "Evaluate the corrected phase and its local influence at a latitude."
  def at(%{fallback: fallback, nodes: nodes}, lat) do
    case Enum.find(Enum.chunk_every(nodes, 2, 1, :discard), fn [a, b] ->
           lat >= a.lat and lat <= b.lat
         end) do
      nil ->
        nearest = Enum.min_by(nodes, &abs(&1.lat - lat))
        proximity = max(0, 1 - abs(nearest.lat - lat) / @fade_degrees)
        %{phase: fallback + nearest.correction, weight: nearest.weight * proximity}

      [a, b] ->
        t = (lat - a.lat) / (b.lat - a.lat)
        smooth = t * t * (3 - 2 * t)
        correction = a.correction + smooth * (b.correction - a.correction)
        proximity = max(0, 1 - min(lat - a.lat, b.lat - lat) / @fade_degrees)
        weight = (a.weight + smooth * (b.weight - a.weight)) * proximity
        %{phase: fallback + correction, weight: weight}
    end
  end
end
