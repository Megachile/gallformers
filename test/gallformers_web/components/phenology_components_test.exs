defmodule GallformersWeb.PhenologyComponentsTest do
  @moduledoc """
  Tests for the embedded phenology summary widget — specifically the
  latitude-gated prediction logic that refuses to predict outside the
  species' observed-latitude range or in a hemisphere with no observations.
  """
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest

  alias GallformersWeb.PhenologyComponents

  # Build a single observation map matching what PhenologyComponents
  # consumes (see `to_summary_map/1`).
  defp obs(opts) do
    %{
      doy: Keyword.get(opts, :doy, 167),
      phenophase: Keyword.get(opts, :phenophase, "maturing"),
      source_type: Keyword.get(opts, :source_type, "literature"),
      latitude: Keyword.get(opts, :latitude, 42.0),
      seasind: Keyword.get(opts, :seasind, 0.45)
    }
  end

  # Generate `n` observations of one phenophase with monotonically
  # increasing seasind and DOY values, all at the same latitude. Enough
  # samples (≥ @min_obs_for_window = 8) for the widget to compute a window.
  defp obs_batch(n, opts) do
    base_seasind = Keyword.get(opts, :base_seasind, 0.30)
    base_doy = Keyword.get(opts, :base_doy, 90)

    for i <- 0..(n - 1) do
      obs(
        Keyword.merge(opts,
          seasind: base_seasind + i * 0.03,
          doy: base_doy + i * 5
        )
      )
    end
  end

  defp render_summary(assigns) do
    render_component(&PhenologyComponents.phenology_summary/1, assigns)
  end

  describe "phenology_summary/1 — base rendering" do
    test "shows empty-state when no observations" do
      html = render_summary(species_id: 1, observations: [], target_lat: nil)
      assert html =~ "Phenology"
      assert html =~ "No phenology observations recorded yet"
    end

    test "shows observation count and DOY-IQR fallback when target_lat is nil" do
      observations = obs_batch(10, latitude: 42.0)
      html = render_summary(species_id: 1, observations: observations, target_lat: nil)

      assert html =~ "10 observations"
      assert html =~ "maturing"
      assert html =~ "(IQR, n=10)"
      refute html =~ "from seasind IQR"
    end
  end

  describe "phenology_summary/1 — latitude gating" do
    test "predicts windows when target_lat is inside the observed-lat range" do
      # Obs at 30-50°N, viewer at 42°N → predict.
      observations =
        obs_batch(10, latitude: 40.0) ++
          [obs(latitude: 30.0), obs(latitude: 50.0)]

      html = render_summary(species_id: 1, observations: observations, target_lat: 42.0)

      assert html =~ "from seasind IQR"
      assert html =~ "42.0°N"
      refute html =~ "observed range for this species is"
      refute html =~ "No observations in your hemisphere"
    end

    test "refuses to predict when target_lat is outside the observed-lat range" do
      observations = obs_batch(10, latitude: 40.0)
      html = render_summary(species_id: 1, observations: observations, target_lat: 75.0)

      assert html =~ "observed range for this species is"
      assert html =~ "40.0°N to 40.0°N"
      refute html =~ "from seasind IQR"
    end

    test "honors the buffer — slightly outside is still in" do
      # Obs at exactly 40°N, viewer at 44°N → 4° outside, within 5° buffer.
      observations = obs_batch(10, latitude: 40.0)
      html = render_summary(species_id: 1, observations: observations, target_lat: 44.0)

      assert html =~ "from seasind IQR"
      refute html =~ "observed range for this species is"
    end

    test "refuses to predict when viewer's hemisphere has no obs" do
      # All obs NH, viewer SH → refuse with hemisphere-specific message.
      observations = obs_batch(10, latitude: 40.0)
      html = render_summary(species_id: 1, observations: observations, target_lat: -30.0)

      assert html =~ "No observations in your hemisphere"
      refute html =~ "from seasind IQR"
    end

    test "displays °S in the qualifier when target_lat is negative" do
      observations = obs_batch(10, latitude: -33.0)
      html = render_summary(species_id: 1, observations: observations, target_lat: -30.0)

      assert html =~ "from seasind IQR"
      assert html =~ "30.0°S"
      refute html =~ "30.0°N"
    end

    test "displays °S in the range message when the obs are SH" do
      observations = obs_batch(10, latitude: -33.0)
      html = render_summary(species_id: 1, observations: observations, target_lat: -75.0)

      assert html =~ "observed range for this species is"
      assert html =~ "33.0°S to 33.0°S"
    end

    test "buckets by hemisphere — pooled obs do not contaminate the IQR" do
      # 10 NH obs + 10 SH obs (with very different seasind ranges). Viewer
      # in NH should see windows computed from NH obs only. The SH obs are
      # in scope of the species but the IQR must not pool across the
      # equator. We assert positively that the NH path renders (the
      # alternative — pooled IQR — wouldn't fail the gate but would
      # produce silently-wrong dates).
      nh = obs_batch(10, latitude: 40.0, base_seasind: 0.30, base_doy: 90)
      sh = obs_batch(10, latitude: -40.0, base_seasind: 0.70, base_doy: 270)

      html = render_summary(species_id: 1, observations: nh ++ sh, target_lat: 42.0)

      assert html =~ "from seasind IQR"
      # n in qualifier should be 10 (NH only), not 20 (pooled).
      assert html =~ "n=10"
      refute html =~ "n=20"
    end
  end

  describe "phenology_summary/1 — input label" do
    test "input help text mentions both hemispheres" do
      observations = obs_batch(10, latitude: 40.0)
      html = render_summary(species_id: 1, observations: observations, target_lat: nil)

      # The hardcoded °N has been replaced with sign-based guidance.
      assert html =~ "positive"
      assert html =~ "negative"
      refute html =~ "°N (blank"
    end
  end
end
