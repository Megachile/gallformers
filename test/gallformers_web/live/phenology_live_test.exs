defmodule GallformersWeb.PhenologyLiveTest do
  @moduledoc """
  LiveView tests for the public phenology explorer at /phenology.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gallformers.Phenology
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  defp insert_gall(name) do
    {:ok, sp} =
      Repo.insert(%Species{name: name, taxoncode: "gall", datacomplete: false})

    sp
  end

  defp insert_obs(species_id, attrs) do
    Map.merge(
      %{
        species_id: species_id,
        source_type: "literature",
        date: ~D[2024-06-15],
        doy: 167,
        latitude: 42.0,
        longitude: -83.0,
        phenophase: "maturing"
      },
      attrs
    )
    |> Phenology.create_observation()
  end

  describe "/phenology" do
    test "renders the page even with no observations", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/phenology")
      assert html =~ "Phenology"
      assert html =~ "0 species with phenology data"
    end

    test "lists species that have observations", %{conn: conn} do
      sp1 = insert_gall("Acraspis testica (agamic)")
      sp2 = insert_gall("Acraspis testica (sexgen)")
      insert_obs(sp1.id, %{})
      insert_obs(sp2.id, %{})

      {:ok, _view, html} = live(conn, ~p"/phenology")

      assert html =~ "Acraspis testica (agamic)"
      assert html =~ "Acraspis testica (sexgen)"
      assert html =~ "2 species with phenology data"
    end

    test "selecting a different species updates the chart data", %{conn: conn} do
      sp1 = insert_gall("Aulacidea alpha (agamic)")
      sp2 = insert_gall("Aulacidea beta (sexgen)")
      insert_obs(sp1.id, %{phenophase: "developing"})
      insert_obs(sp2.id, %{phenophase: "Free-living", date: ~D[2024-07-01], doy: 183})

      {:ok, view, _html} = live(conn, ~p"/phenology")

      # Switch to the second species via the dropdown change event.
      html =
        view
        |> form("form", %{"species_id" => to_string(sp2.id)})
        |> render_change()

      assert html =~ "Aulacidea beta (sexgen)"
      assert html =~ "generation: <strong>sexgen</strong>"
      assert html =~ "Free-living"
    end

    test "page title is set", %{conn: conn} do
      sp = insert_gall("Acraspis tester (agamic)")
      insert_obs(sp.id, %{})

      {:ok, view, _html} = live(conn, ~p"/phenology")
      assert page_title(view) =~ "Phenology"
    end
  end
end
