defmodule Gallformers.Phenology.PredictionTest do
  @moduledoc """
  Unit tests for the per-(generation × event) phenology prediction
  windows. The module hits `Gallformers.Phenology.Math.doy_for_seasind/2`
  but no DB; we feed it plain maps with the fields it expects.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Phenology.Prediction

  defp obs(opts) do
    %{
      species_name: Keyword.get(opts, :species_name, "Acraspis testica (sexgen)"),
      phenophase: Keyword.get(opts, :phenophase, "maturing"),
      viability: Keyword.get(opts, :viability, nil),
      seasind: Keyword.get(opts, :seasind, 0.5)
    }
  end

  describe "predictions_for/2" do
    test "returns [] when there aren't enough obs in any (gen, event) bucket" do
      # 3 obs of sexgen emergence — below the @min_obs = 4 threshold.
      obs = for s <- [0.30, 0.40, 0.50], do: obs(seasind: s, phenophase: "maturing")
      assert Prediction.predictions_for(obs, 42.0) == []
    end

    test "returns one prediction per (gen, event) bucket above threshold" do
      # 4 sexgen emergence obs — exactly at threshold.
      obs =
        for s <- [0.30, 0.40, 0.50, 0.60],
            do: obs(seasind: s, phenophase: "maturing", species_name: "X (sexgen)")

      [p] = Prediction.predictions_for(obs, 42.0)
      assert p.generation == :sexgen
      assert p.event == :emergence
      assert p.n == 4
      assert p.target_lat == 42.0
      assert is_integer(p.low_doy)
      assert is_integer(p.high_doy)
      assert p.low_doy <= p.high_doy
    end

    test "separates predictions by generation" do
      sex =
        for s <- [0.30, 0.40, 0.50, 0.60],
            do: obs(seasind: s, phenophase: "maturing", species_name: "X (sexgen)")

      agam =
        for s <- [0.50, 0.60, 0.70, 0.80],
            do: obs(seasind: s, phenophase: "maturing", species_name: "X (agamic)")

      preds = Prediction.predictions_for(sex ++ agam, 42.0)
      generations = preds |> Enum.map(& &1.generation) |> Enum.sort()
      assert generations == [:agamic, :sexgen]
    end

    test "rearing uses viability='viable', emergence uses maturing/perimature/Free-living" do
      rearing_obs =
        for s <- [0.30, 0.40, 0.50, 0.60] do
          obs(
            seasind: s,
            phenophase: "developing",
            viability: "viable",
            species_name: "X (sexgen)"
          )
        end

      emergence_obs =
        for s <- [0.60, 0.70, 0.80, 0.90] do
          obs(seasind: s, phenophase: "maturing", species_name: "X (sexgen)")
        end

      preds = Prediction.predictions_for(rearing_obs ++ emergence_obs, 42.0)
      events = preds |> Enum.map(& &1.event) |> Enum.sort()
      assert events == [:emergence, :rearing]
    end

    test "obs missing seasind are skipped" do
      obs =
        [
          obs(seasind: nil, phenophase: "maturing"),
          obs(seasind: 0.30, phenophase: "maturing"),
          obs(seasind: 0.40, phenophase: "maturing"),
          obs(seasind: 0.50, phenophase: "maturing")
        ]

      # Only 3 valid obs after dropping nil — below threshold.
      assert Prediction.predictions_for(obs, 42.0) == []
    end

    test "non-numeric target_lat returns []" do
      obs =
        for s <- [0.30, 0.40, 0.50, 0.60],
            do: obs(seasind: s, phenophase: "maturing", species_name: "X (sexgen)")

      assert Prediction.predictions_for(obs, nil) == []
      assert Prediction.predictions_for(obs, "not a number") == []
    end

    test "target_lat affects the predicted DOYs" do
      obs =
        for s <- [0.30, 0.40, 0.50, 0.60],
            do: obs(seasind: s, phenophase: "maturing", species_name: "X (sexgen)")

      [south] = Prediction.predictions_for(obs, 30.0)
      [north] = Prediction.predictions_for(obs, 50.0)

      # The back-projection is lat-dependent; we only assert that the result
      # changes with target_lat, not the direction of the shift (which
      # depends on which part of the seasind range the IQR sits in — early
      # spring seasinds shift one way, late summer the other).
      assert south.low_doy != north.low_doy or south.high_doy != north.high_doy
    end
  end
end
