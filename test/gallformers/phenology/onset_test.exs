defmodule Gallformers.Phenology.OnsetTest do
  use ExUnit.Case, async: true
  alias Gallformers.Phenology.{Onset, SeasonalClock}

  defp record(lat, phase, year \\ 2023, lon \\ -90.0) do
    {%{latitude: lat, longitude: lon, date: Date.new!(year, 6, 1)}, phase}
  end

  test "one-site and isolated distant records retain the earliest clock fallback" do
    model = Onset.fit([record(35, 20), record(45, 40)])

    for lat <- [25, 35, 40, 45, 55] do
      assert Onset.at(model, lat).phase == 20
      assert Onset.at(model, lat).weight == 0
    end
  end

  test "repeated northern early records bend the line without moving the southern anchor" do
    south = record(35, 20)
    north = for year <- 2020..2024, do: record(45, 40, year)
    model = Onset.fit([south | north])
    assert Onset.at(model, 35).phase == 20
    assert_in_delta Onset.at(model, 45).phase, 20 + 20 * 4 / 6, 1.0e-8
    assert Onset.at(model, 40).phase > 20
    assert Onset.at(model, 40).phase < Onset.at(model, 45).phase
    stronger = Onset.fit([south | north ++ [record(45, 40, 2025)]])
    assert Onset.at(stronger, 45).phase > Onset.at(model, 45).phase
  end

  test "late photos and same-locality same-year repeats cannot increase early-edge support" do
    records = [record(35, 20), record(45, 40, 2020), record(45, 40, 2021)]
    late = for year <- 2010..2025, do: record(45, 100, year)
    repeats = List.duplicate(record(45, 40, 2020), 100)
    assert Onset.fit(records) == Onset.fit(records ++ late ++ repeats)
  end

  test "one year's many localities do not outweigh repeated years" do
    one_year = for lon <- -100..-80, do: record(45, 40, 2023, lon)
    model = Onset.fit([record(35, 20) | one_year])
    assert_in_delta Onset.at(model, 45).weight, 1 / 3, 1.0e-8
  end

  test "the fourteen-day support window uses calendar days, including its boundary" do
    phase = SeasonalClock.coordinate(150, 45)
    base = [record(35, phase - 20), record(45, phase, 2020)]
    at_boundary = record(45, SeasonalClock.coordinate(164, 45), 2021)
    outside = record(45, SeasonalClock.coordinate(165, 45), 2021)
    assert Onset.at(Onset.fit(base ++ [at_boundary]), 45).weight > 0
    assert Onset.at(Onset.fit(base ++ [outside]), 45).weight == 0
  end

  test "outside support, continue the adjusted clock instead of reversing toward the old date" do
    model = Onset.fit([record(35, 20), record(45, 40, 2020), record(45, 40, 2021)])
    assert Onset.at(model, 55).phase == Onset.at(model, 45).phase
    assert Onset.at(model, 55).weight == 0
    assert Onset.at(model, 25).phase == 20
  end

  test "interpolation is continuous, bounded and independent of input order" do
    records = [record(35.4, 20), record(45, 40, 2020), record(45, 40, 2021)]
    model = Onset.fit(records)
    assert Onset.fit(Enum.reverse(records)) == model

    for lat <- 26..54 do
      assert_in_delta Onset.at(model, lat - 0.00001).phase,
                      Onset.at(model, lat + 0.00001).phase,
                      0.001

      assert Onset.at(model, lat).phase >= 20
      assert Onset.at(model, lat).phase <= 40
    end

    assert Onset.at(model, 35.4).phase == 20
  end

  test "the correction is invariant to which annual clock cycle contains the season" do
    records = [record(35, 240), record(45, 255, 2020), record(45, 255, 2021)]
    shifted = Enum.map(records, fn {o, p} -> {o, p + 365} end)
    model = Onset.fit(records)
    next_year = Onset.fit(shifted)

    for lat <- [30, 35, 40, 45, 50] do
      assert_in_delta Onset.at(next_year, lat).phase - Onset.at(model, lat).phase, 365, 1.0e-8
      assert Onset.at(next_year, lat).weight == Onset.at(model, lat).weight
    end
  end
end
