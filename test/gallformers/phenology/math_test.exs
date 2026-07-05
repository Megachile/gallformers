defmodule Gallformers.Phenology.MathTest do
  @moduledoc "Unit tests for pure phenology math helpers."
  use ExUnit.Case, async: true

  alias Gallformers.Phenology.Math

  describe "doy_span/1" do
    test "returns 0 for zero or one observation" do
      assert Math.doy_span([]) == 0
      assert Math.doy_span([167]) == 0
    end

    test "is max - min for a contiguous mid-year window" do
      assert Math.doy_span([150, 200, 250]) == 100
    end

    test "is wrap-aware for a fall to spring species straddling the new year" do
      # Obs at DOY 350 and 10 span ~25 days across the boundary, NOT ~340.
      assert Math.doy_span([350, 10]) == 25
      # A tight fall/winter/early-spring cluster stays small.
      assert Math.doy_span([340, 350, 360, 5, 15, 25]) == 50
    end

    test "duplicate days collapse to a zero span" do
      assert Math.doy_span([167, 167, 167]) == 0
    end

    test "full-year coverage approaches the whole year" do
      # One obs per ~month (DOY 1,31,…,331): inter-obs gaps are 30, the wrap
      # gap 331→1 is 35 → span = 365 - 35 = 330.
      doys = Enum.map(0..11, fn m -> m * 30 + 1 end)
      assert Math.doy_span(doys) == 330
    end
  end
end
