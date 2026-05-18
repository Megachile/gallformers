defmodule GallformersWeb.PhenologyLiveTest do
  @moduledoc """
  LiveView tests for the public phenology explorer at /phenology — the
  multi-species version with text search, generation radio, and phenophase
  multi-select.
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

  describe "/phenology base rendering" do
    test "renders the page even with no observations", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/phenology")
      assert html =~ "Phenology"
      assert html =~ "0 observations"
      assert html =~ "No observations match these filters."
    end

    test "loads all gall obs into the scatter by default", %{conn: conn} do
      sp1 = insert_gall("Acraspis testica (agamic)")
      sp2 = insert_gall("Acraspis testica (sexgen)")
      insert_obs(sp1.id, %{})
      insert_obs(sp2.id, %{})

      {:ok, _view, html} = live(conn, ~p"/phenology")

      # Stat line reflects total obs + species count.
      assert html =~ "2 observations"
      assert html =~ "across 2 species"
      # Species names are in the chart points (data-points JSON), so escaped.
      assert html =~ "Acraspis testica (agamic)"
      assert html =~ "Acraspis testica (sexgen)"
    end

    test "page title is set", %{conn: conn} do
      sp = insert_gall("Acraspis tester (agamic)")
      insert_obs(sp.id, %{})

      {:ok, view, _html} = live(conn, ~p"/phenology")
      assert page_title(view) =~ "Phenology"
    end
  end

  describe "/phenology filters" do
    setup do
      sp1 = insert_gall("Acraspis erinacei (agamic)")
      sp2 = insert_gall("Aulacidea solidaginis (sexgen)")
      sp3 = insert_gall("Andricus quercuscalifornicus (agamic)")
      insert_obs(sp1.id, %{phenophase: "developing"})
      insert_obs(sp2.id, %{phenophase: "Free-living", date: ~D[2024-07-01], doy: 183})
      insert_obs(sp3.id, %{phenophase: "maturing"})
      :ok
    end

    test "search term filters obs to matching species names", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/phenology")

      html =
        view
        |> form("form", %{"search" => "Acraspis", "generation" => "all"})
        |> render_change()

      assert html =~ "1 observation"
      assert html =~ "Acraspis erinacei"
      refute html =~ "Aulacidea solidaginis"
      refute html =~ "Andricus quercuscalifornicus"
    end

    test "comma-separated search terms match either", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/phenology")

      html =
        view
        |> form("form", %{"search" => "Acraspis, Aulacidea", "generation" => "all"})
        |> render_change()

      assert html =~ "2 observations"
      assert html =~ "Acraspis erinacei"
      assert html =~ "Aulacidea solidaginis"
      refute html =~ "Andricus quercuscalifornicus"
    end

    test "generation filter restricts to sexgen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/phenology")

      html =
        view
        |> form("form", %{"search" => "", "generation" => "sexgen"})
        |> render_change()

      assert html =~ "1 observation"
      assert html =~ "Aulacidea solidaginis (sexgen)"
      refute html =~ "Acraspis erinacei"
    end

    test "phenophase filter restricts to selected phenophases", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/phenology")

      html =
        view
        |> form("form", %{
          "search" => "",
          "generation" => "all",
          "phenophases" => ["developing"]
        })
        |> render_change()

      assert html =~ "1 observation"
      assert html =~ "Acraspis erinacei"
      refute html =~ "Aulacidea solidaginis"
    end
  end

  describe "/phenology URL params" do
    test "?search= seeds the search filter on mount", %{conn: conn} do
      sp = insert_gall("Acraspis erinacei (agamic)")
      other = insert_gall("Aulacidea solidaginis (sexgen)")
      insert_obs(sp.id, %{})
      insert_obs(other.id, %{})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=Acraspis")

      assert html =~ "1 observation"
      assert html =~ "Acraspis erinacei"
      refute html =~ "Aulacidea solidaginis"
    end

    test "?gen= seeds the generation filter on mount", %{conn: conn} do
      sex = insert_gall("Aulacidea sexier (sexgen)")
      agam = insert_gall("Acraspis agamier (agamic)")
      insert_obs(sex.id, %{})
      insert_obs(agam.id, %{})

      {:ok, _view, html} = live(conn, ~p"/phenology?gen=sexgen")

      assert html =~ "1 observation"
      assert html =~ "Aulacidea sexier"
      refute html =~ "Acraspis agamier"
    end

    test "?species_id= back-compat seeds search from the species name", %{conn: conn} do
      sp = insert_gall("Specific testica (agamic)")
      other = insert_gall("Other species (agamic)")
      insert_obs(sp.id, %{})
      insert_obs(other.id, %{})

      {:ok, _view, html} = live(conn, ~p"/phenology?species_id=#{sp.id}")

      assert html =~ "1 observation"
      assert html =~ "Specific testica"
      refute html =~ "Other species"
    end
  end
end
