defmodule Gallformers.Phenology.Math do
  @moduledoc """
  Season index (`seasind`) math, ported from
  `phenology_pipeline/phenology_math.py` (in turn ported from the original
  R `seasonIndex()` in iNatImportFunctions.R).

  Season index is the fraction of total annual daylight hours accumulated
  by a given day-of-year at a given latitude. It's monotonically increasing
  from 0 (DOY 1) to 1 (DOY 365), and lets phenological "calendars" be
  compared across latitudes — a species at seasind 0.45 in Florida and the
  same species at seasind 0.45 in Maine are at roughly the same point in
  their physiological year, even though the calendar dates differ.

  Used by the phenology widget on each gall page to translate a per-species
  seasind IQR (computed from the species' actual observations across many
  latitudes) into a calendar-date IQR at the viewer's chosen latitude.
  """

  @doc """
  Solar declination angle in degrees for a given day of year.
  Standard astronomical formula.
  """
  @spec declination(integer()) :: float()
  def declination(doy) do
    23.45 * :math.sin(2 * :math.pi() * (284 + doy) / 365)
  end

  @doc """
  Daylight hours function (standard version, ported from R `eq()`).

  Returns the (latitude-adjusted) daylight hours for a given DOY at a given
  latitude. Result clamped at zero to handle polar winters where the geometric
  formula would be negative.
  """
  @spec eq(integer(), number()) :: float()
  def eq(doy, lat) do
    lat_rad = lat * :math.pi() / 180
    decl_rad = :math.pi() * declination(doy) / 180

    arg =
      (-:math.tan(lat_rad) * :math.tan(decl_rad))
      |> clamp(-1.0, 1.0)

    2 * (24 / (2 * :math.pi())) * :math.acos(arg) - (0.1 * lat + 5)
  end

  @doc """
  Compute season index for a single (DOY, latitude) pair.

  Defined as the cumulative integral of positive daylight hours up to DOY,
  divided by the same integral over the full year. Trapezoidal rule with
  unit spacing (1 day per step).
  """
  @spec season_index(integer(), number()) :: float()
  def season_index(doy, lat) when doy >= 1 and doy <= 365 do
    numerator = trapz_eq_pos(1, doy, lat)
    denominator = trapz_eq_pos(1, 365, lat)

    if denominator == 0.0, do: 0.0, else: numerator / denominator
  end

  @doc """
  Inverse of `season_index/2`: given a target seasind value at a latitude,
  return the DOY where the cumulative seasind first reaches or exceeds it.

  Caps at 365 if the target is unreachable at this latitude. Returns 1 for
  any non-positive target. Used by the widget to back-project a seasind IQR
  (computed across many observations at varied latitudes) into calendar
  dates at the viewer's chosen latitude.
  """
  @spec doy_for_seasind(number(), number()) :: integer()
  def doy_for_seasind(target_seasind, _lat) when target_seasind <= 0, do: 1

  def doy_for_seasind(target_seasind, _lat) when target_seasind >= 1, do: 365

  def doy_for_seasind(target_seasind, lat) do
    # Precompute cumulative seasind for each DOY at this latitude, then
    # search for the first DOY at-or-above the target. The cumulative
    # construction is O(365); the search is O(365) too — both negligible
    # for a per-request widget computation.
    denominator = trapz_eq_pos(1, 365, lat)

    if denominator == 0.0 do
      1
    else
      search_doy(target_seasind, lat, denominator)
    end
  end

  defp search_doy(target_seasind, lat, denominator) do
    1..365
    |> Enum.reduce_while({0.0, 0.0, 1}, fn doy, {prev_seasind, prev_h, _} ->
      h = pos(eq(doy, lat))
      # Trapezoidal step from doy-1 to doy uses (prev_h + h) / 2 = the
      # daily contribution.
      step = (prev_h + h) / 2
      cum = prev_seasind + step / denominator
      step_decision(cum, h, doy, target_seasind)
    end)
    |> case do
      doy when is_integer(doy) -> doy
      _ -> 365
    end
  end

  defp step_decision(cum, _h, doy, target) when cum >= target, do: {:halt, doy}
  defp step_decision(cum, h, doy, _target), do: {:cont, {cum, h, doy}}

  # ----------------------------------------------------------------------
  # Internals
  # ----------------------------------------------------------------------

  defp trapz_eq_pos(start_doy, end_doy, lat) when end_doy >= start_doy do
    # Trapezoidal rule with unit spacing over positive-clamped daylight hours.
    h_start = pos(eq(start_doy, lat))
    h_end = pos(eq(end_doy, lat))

    interior =
      Enum.reduce((start_doy + 1)..(end_doy - 1)//1, 0.0, fn d, acc ->
        acc + pos(eq(d, lat))
      end)

    (h_start + h_end) / 2 + interior
  end

  defp trapz_eq_pos(_, _, _), do: 0.0

  defp pos(x) when x > 0, do: x
  defp pos(_), do: 0.0

  defp clamp(x, lo, _hi) when x < lo, do: lo
  defp clamp(x, _lo, hi) when x > hi, do: hi
  defp clamp(x, _, _), do: x
end
