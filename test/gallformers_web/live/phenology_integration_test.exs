defmodule GallformersWeb.PhenologyIntegrationTest do
  use GallformersWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  alias Gallformers.Phenology
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  defp gall(name) do
    Repo.insert!(%Species{name: name, taxoncode: "gall", datacomplete: false})
  end

  defp observation(species, phase, day, viability \\ nil) do
    {:ok, record} =
      Phenology.create_observation(%{
        species_id: species.id,
        date: Date.add(~D[2023-01-01], day - 1),
        doy: day,
        latitude: 30.0,
        longitude: -98.0,
        phenophase: phase,
        viability: viability,
        source_type: "literature"
      })

    record
  end

  defp windows(view) do
    view
    |> render()
    |> LazyHTML.from_document()
    |> LazyHTML.query("[data-event]")
    |> Enum.map(fn node ->
      Enum.map(
        ~w(data-event data-generation data-low-doy data-high-doy),
        &LazyHTML.attribute(node, &1)
      )
    end)
  end

  test "gall panel and explorer agree, use exact identity, and preserve latitude", %{conn: conn} do
    sp = gall("Phenology contract (agamic)")
    other = gall("Phenology contract (agamic) additional")
    observation(sp, "developing", 160)
    observation(sp, "dormant", 250, "viable")
    observation(sp, "maturing", 350)
    observation(sp, "Free-living", 5)
    observation(other, "maturing", 100)

    {:ok, compact, _} = live(conn, ~p"/gall/#{sp.id}")
    refute has_element?(compact, "#gall-phenology-content")
    compact |> element("#toggle-phenology") |> render_click()
    assert has_element?(compact, "#gall-phenology-content")
    compact |> form("#gall-phenology-latitude", target_lat: "40") |> render_change()
    compact_windows = windows(compact)
    assert length(compact_windows) == 3

    {:ok, explorer, _} =
      live(conn, ~p"/phenology?species_id=#{sp.id}&lat=40&events=onset,emergence,rearing")

    assert windows(explorer) == compact_windows
    refute render(explorer) =~ other.name

    render_patch(explorer, ~p"/phenology?species_id=#{sp.id}&display=table")
    assert has_element?(explorer, "#phenology-obs-table a[href='/gall/#{sp.id}']", sp.name)

    compact |> element("#toggle-phenology") |> render_click()
    refute has_element?(compact, "#gall-phenology-content")
    compact |> element("#toggle-phenology") |> render_click()
    assert windows(compact) == compact_windows
    compact |> form("#gall-phenology-latitude", target_lat: "60") |> render_change()
    assert windows(compact) == []
    assert render(compact) =~ "25–55"
  end

  test "dots, event toggles and URL changes are independent", %{conn: conn} do
    sp = gall("Visibility contract (agamic)")
    observation(sp, "developing", 160, "viable")
    observation(sp, "dormant", 250, "viable")
    observation(sp, "maturing", 350)

    {:ok, view, _} =
      live(conn, ~p"/phenology?species_id=#{sp.id}&lat=30&events=onset,emergence,rearing")

    before = windows(view)

    render_patch(
      view,
      ~p"/phenology?species_id=#{sp.id}&lat=30&phen=&events=onset,emergence,rearing"
    )

    assert windows(view) == before
    assert has_element?(view, "#phenology-chart[data-points='[]']")

    view
    |> form("#phenology-model-form",
      events: %{onset: "false", emergence: "false", rearing: "true"}
    )
    |> render_change()

    assert length(windows(view)) == 1
    assert hd(hd(windows(view))) == ["rearing"]

    view
    |> form("#phenology-model-form",
      events: %{onset: "false", emergence: "false", rearing: "false"}
    )
    |> render_change()

    assert windows(view) == []
    assert has_element?(view, "#phenology-chart")
  end
end
