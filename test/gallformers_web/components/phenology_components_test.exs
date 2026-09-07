defmodule GallformersWeb.PhenologyComponentsTest do
  use ExUnit.Case, async: true
  import Phoenix.LiveViewTest
  alias Gallformers.Phenology
  alias GallformersWeb.PhenologyComponents

  test "collapsed panel has an accessible toggle and no form" do
    html = render_component(&PhenologyComponents.phenology_summary/1, species_id: 1)
    assert html =~ ~s(aria-expanded="false")
    refute html =~ ~s(id="gall-phenology-latitude")
  end

  test "empty expanded panel reports absent evidence" do
    html = render_component(&PhenologyComponents.phenology_summary/1, species_id: 1, open: true)
    assert html =~ "No phenology observations"
    refute html =~ "View full chart"
  end

  test "both presentations render the exact same prediction dates and sparse warnings" do
    obs = %{
      species_id: 1,
      species_name: "Example (agamic)",
      date: ~D[2023-12-28],
      latitude: 30.0,
      longitude: -98.0,
      phenophase: "maturing",
      source_type: "inat"
    }

    assert {:ok, [p]} = Phenology.predict([obs], 40, [:emergence])
    assert {:ok, [compact]} = Phenology.predict([obs], 40, [:emergence], contours: false)
    assert Map.delete(p, :contours) == Map.delete(compact, :contours)
    assert compact.contours == []
    expected = render_component(&PhenologyComponents.prediction_results/1, predictions: [p])

    html =
      render_component(&PhenologyComponents.phenology_summary/1,
        species_id: 1,
        open: true,
        count: 1,
        predictions: [compact],
        target_lat: 40
      )

    assert html =~ expected
    assert html =~ "Sparse evidence"
    assert html =~ "One-cell"
    assert html =~ "Extrapolated"
    assert html =~ "species_id=1"
    assert html =~ "lat=40"
  end
end
