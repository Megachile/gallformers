defmodule GallformersWeb.PhenologyLiveTest do
  @moduledoc """
  LiveView tests for the public phenology explorer at /phenology.

  The mounted explorer pre-populates a default search (Dryocosmus
  quercuspalustris) and a default phenophase set (maturing / perimature /
  Free-living). Tests that want to see all obs regardless of those filters
  mount with `?search=` (clears default search to empty) and pass an
  explicit `phenophases` list when sending form changes.
  """
  use GallformersWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias Gallformers.Phenology
  alias Gallformers.Repo
  alias Gallformers.Species.Species

  # All explorer phenophases checked — the equivalent of "show me everything"
  # for tests that want to focus only on search / generation filtering.
  @all_explorer_phenophases ~w(oviscar developing dormant maturing Free-living perimature)

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

    test "default mount pre-fills the Dryocosmus search and shows matching obs",
         %{conn: conn} do
      drycosmus = insert_gall("Dryocosmus quercuspalustris (agamic)")
      acraspis = insert_gall("Acraspis testica (agamic)")
      insert_obs(drycosmus.id, %{phenophase: "maturing"})
      insert_obs(acraspis.id, %{phenophase: "maturing"})

      {:ok, _view, html} = live(conn, ~p"/phenology")

      # Default search pre-fills the input.
      assert html =~ "value=\"Dryocosmus quercuspalustris\""
      # Only the Dryocosmus obs matches; Acraspis is filtered out by default.
      assert html =~ "1 observation"
      assert html =~ "across 1 species"
      assert html =~ "Dryocosmus quercuspalustris"
      refute html =~ "Acraspis testica"
    end

    test "default mount pre-checks maturing / perimature / Free-living", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/phenology")

      # The three default phenophase checkboxes render with `checked`.
      assert html =~ ~s(name="phenophases[]" value="maturing" checked="")
      assert html =~ ~s(name="phenophases[]" value="perimature" checked="")
      assert html =~ ~s(name="phenophases[]" value="Free-living" checked="")
      # The other three are NOT checked.
      refute html =~ ~s(name="phenophases[]" value="oviscar" checked="")
      refute html =~ ~s(name="phenophases[]" value="developing" checked="")
      refute html =~ ~s(name="phenophases[]" value="dormant" checked="")
    end

    test "senescent is not exposed in the explorer UI", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/phenology")
      refute html =~ ~s(name="phenophases[]" value="senescent")
    end

    test "?search= clears the default search to show all obs across species", %{conn: conn} do
      sp1 = insert_gall("Acraspis testica (agamic)")
      sp2 = insert_gall("Acraspis testica (sexgen)")
      insert_obs(sp1.id, %{})
      insert_obs(sp2.id, %{})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=")

      assert html =~ "2 observations"
      assert html =~ "across 2 species"
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
      # Start with ?search= to clear the default, then filter via form change.
      # Include all phenophases so the search filter is the only thing
      # restricting the obs set.
      {:ok, view, _html} = live(conn, ~p"/phenology?search=")

      html =
        view
        |> form("form", %{
          "search" => "Acraspis",
          "generation" => "all",
          "phenophases" => @all_explorer_phenophases
        })
        |> render_change()

      assert html =~ "1 observation"
      assert html =~ "Acraspis erinacei"
      refute html =~ "Aulacidea solidaginis"
      refute html =~ "Andricus quercuscalifornicus"
    end

    test "comma-separated search terms match either", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/phenology?search=")

      html =
        view
        |> form("form", %{
          "search" => "Acraspis, Aulacidea",
          "generation" => "all",
          "phenophases" => @all_explorer_phenophases
        })
        |> render_change()

      assert html =~ "2 observations"
      assert html =~ "Acraspis erinacei"
      assert html =~ "Aulacidea solidaginis"
      refute html =~ "Andricus quercuscalifornicus"
    end

    test "generation filter restricts to sexgen", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/phenology?search=")

      html =
        view
        |> form("form", %{
          "search" => "",
          "generation" => "sexgen",
          "phenophases" => @all_explorer_phenophases
        })
        |> render_change()

      assert html =~ "1 observation"
      assert html =~ "Aulacidea solidaginis (sexgen)"
      refute html =~ "Acraspis erinacei"
    end

    test "phenophase filter restricts to selected phenophases", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/phenology?search=")

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

    test "unchecking all phenophases shows no obs (strict empty)", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/phenology?search=")

      # Use render_change directly so we can omit the phenophases key
      # entirely — the form helper would fill in checked defaults. The
      # browser sends no `phenophases` key when no checkboxes are checked.
      html =
        render_change(view, "update_filters", %{
          "search" => "",
          "generation" => "all"
        })

      assert html =~ "0 observations"
      assert html =~ "No observations match these filters."
    end
  end

  describe "/phenology URL params" do
    test "?search= seeds the search filter on mount", %{conn: conn} do
      sp = insert_gall("Acraspis erinacei (agamic)")
      other = insert_gall("Aulacidea solidaginis (sexgen)")
      insert_obs(sp.id, %{phenophase: "maturing"})
      insert_obs(other.id, %{phenophase: "maturing"})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=Acraspis")

      assert html =~ "1 observation"
      assert html =~ "Acraspis erinacei"
      refute html =~ "Aulacidea solidaginis"
    end

    test "?gen= seeds the generation filter on mount", %{conn: conn} do
      sex = insert_gall("Aulacidea sexier (sexgen)")
      agam = insert_gall("Acraspis agamier (agamic)")
      insert_obs(sex.id, %{phenophase: "maturing"})
      insert_obs(agam.id, %{phenophase: "maturing"})

      # `search=` clears the default search so only the gen filter restricts.
      {:ok, _view, html} = live(conn, ~p"/phenology?search=&gen=sexgen")

      assert html =~ "1 observation"
      assert html =~ "Aulacidea sexier"
      refute html =~ "Acraspis agamier"
    end

    test "?phen= explicitly empty results in zero obs (strict)", %{conn: conn} do
      sp = insert_gall("Acraspis erinacei (agamic)")
      insert_obs(sp.id, %{phenophase: "maturing"})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=&phen=")

      assert html =~ "0 observations"
    end

    test "?phen=val restricts to those phenophases", %{conn: conn} do
      sp1 = insert_gall("Acraspis a (agamic)")
      sp2 = insert_gall("Acraspis b (agamic)")
      insert_obs(sp1.id, %{phenophase: "developing"})
      insert_obs(sp2.id, %{phenophase: "maturing"})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=&phen=developing")

      assert html =~ "1 observation"
      assert html =~ "Acraspis a"
      refute html =~ "Acraspis b"
    end

    test "?species_id= back-compat seeds search from the species name", %{conn: conn} do
      sp = insert_gall("Specific testica (agamic)")
      other = insert_gall("Other species (agamic)")
      insert_obs(sp.id, %{phenophase: "maturing"})
      insert_obs(other.id, %{phenophase: "maturing"})

      {:ok, _view, html} = live(conn, ~p"/phenology?species_id=#{sp.id}")

      assert html =~ "1 observation"
      assert html =~ "Specific testica"
      refute html =~ "Other species"
    end
  end
end
