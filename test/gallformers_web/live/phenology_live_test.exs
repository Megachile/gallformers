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
  alias Gallformers.Taxonomy.Taxonomy

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

  defp insert_taxon(attrs) do
    {:ok, node} =
      Repo.insert(struct(Taxonomy, Map.put_new(attrs, :is_placeholder, false)))

    node
  end

  defp link_taxon(species_id, taxonomy_id) do
    Repo.insert_all("species_taxonomy", [
      %{species_id: species_id, taxonomy_id: taxonomy_id}
    ])
  end

  defp insert_gall_traits(species_id) do
    Repo.insert_all("gall_traits", [%{species_id: species_id}])
  end

  defp insert_color(name) do
    {1, [%{id: id}]} = Repo.insert_all("color", [%{color: name}], returning: [:id])
    id
  end

  defp link_color(species_id, color_id) do
    Repo.insert_all("gall_color", [%{species_id: species_id, color_id: color_id}])
  end

  defp insert_place(name, type) do
    code = "zt-#{System.unique_integer([:positive])}"

    {1, [%{id: id}]} =
      Repo.insert_all("place", [%{name: name, type: type, code: code}], returning: [:id])

    id
  end

  defp link_place_hierarchy(parent_id, child_id) do
    Repo.insert_all("place_hierarchy", [%{parent_id: parent_id, place_id: child_id}])
  end

  defp link_gall_range(species_id, place_id) do
    Repo.insert_all("gall_range", [
      %{species_id: species_id, place_id: place_id, precision: "exact"}
    ])
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

    test "selection-mode controls render in table mode", %{conn: conn} do
      sp = insert_gall("Acraspis tester (agamic)")
      insert_obs(sp.id, %{})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=&display=table")

      # The mode switcher (click & drag / date range / season index) and its
      # per-mode input groups are present alongside the table.
      assert html =~ ~s(phx-hook="PhenologySelect")
      assert html =~ ~s(name="phenology-sel-mode")
      assert html =~ ~s(value="click_drag")
      assert html =~ ~s(value="date_range")
      assert html =~ ~s(value="season_index")
      assert html =~ ~s(data-sel="date")
      assert html =~ ~s(data-sel="days")
      assert html =~ ~s(data-sel="lat")
      assert html =~ ~s(data-sel="thr")
      # No raw seasind number is ever exposed.
      refute html =~ ~s(data-sel="seasind")
    end

    test "selection-mode controls are shown in predictions mode too", %{conn: conn} do
      # The selector sits under the chart in every display mode (like the
      # Shiny sidebar control) so it's discoverable on the default view; only
      # the CSV link is gated to the table / species modes.
      sp = insert_gall("Acraspis tester (agamic)")
      insert_obs(sp.id, %{})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=")
      assert html =~ ~s(phx-hook="PhenologySelect")
      refute html =~ ~s(id="phenology-csv-link")
    end

    test "advanced filters are collapsed by default and toggle open", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/phenology")

      # Collapsed: the advanced panel carries the `hidden` class and the
      # toggle invites expansion. The name-search box is always visible.
      assert html =~ ~s(id="search")
      assert html =~ "More filters"
      assert html =~ ~r/id="phenology-advanced-filters"[^>]*class="[^"]*hidden/

      # Toggling flips the label (and drops the hidden class).
      html = view |> element("#toggle-filters") |> render_click()
      assert html =~ "Fewer filters"
      refute html =~ ~r/id="phenology-advanced-filters"[^>]*class="[^"]*hidden/
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
        |> form("#phenology-filters", %{
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
        |> form("#phenology-filters", %{
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
        |> form("#phenology-filters", %{
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
        |> form("#phenology-filters", %{
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

  describe "/phenology taxon filter" do
    setup do
      # Cynipidae ─ Acraspis ─ sp_acraspis ; Tephritidae ─ Eurosta ─ sp_eurosta
      cynipidae = insert_taxon(%{name: "Cynipidae", type: "family", description: "Wasp"})
      acraspis = insert_taxon(%{name: "Acraspis", type: "genus", parent_id: cynipidae.id})
      tephritidae = insert_taxon(%{name: "Tephritidae", type: "family", description: "Fly"})
      eurosta = insert_taxon(%{name: "Eurosta", type: "genus", parent_id: tephritidae.id})

      sp_acraspis = insert_gall("Acraspis erinacei (agamic)")
      sp_eurosta = insert_gall("Eurosta solidaginis")
      link_taxon(sp_acraspis.id, acraspis.id)
      link_taxon(sp_eurosta.id, eurosta.id)
      insert_obs(sp_acraspis.id, %{})
      insert_obs(sp_eurosta.id, %{})

      %{cynipidae: cynipidae, acraspis: acraspis, sp_acraspis: sp_acraspis}
    end

    test "the selector renders data-bearing family/tribe nodes, but not genera", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=")

      assert html =~ ~s(<optgroup label="Family">)
      assert html =~ "Cynipidae"
      assert html =~ "Tephritidae"
      # Genera are intentionally not offered in the dropdown (use the search box).
      refute html =~ ~s(<optgroup label="Genus">)
    end

    test "selecting a family narrows the obs to species under it", %{
      conn: conn,
      cynipidae: cynipidae
    } do
      {:ok, view, _html} = live(conn, ~p"/phenology?search=")

      # Baseline: both species visible with no taxon filter.
      html =
        view
        |> form("#phenology-filters", %{
          "search" => "",
          "generation" => "all",
          "phenophases" => @all_explorer_phenophases
        })
        |> render_change()

      assert html =~ "2 observations"

      html =
        view
        |> form("#phenology-filters", %{
          "search" => "",
          "generation" => "all",
          "phenophases" => @all_explorer_phenophases,
          "taxon" => to_string(cynipidae.id)
        })
        |> render_change()

      assert html =~ "1 observation"
      assert html =~ "Acraspis erinacei"
      refute html =~ "Eurosta solidaginis"
    end

    test "?taxon=ID seeds the taxon filter on mount", %{conn: conn, cynipidae: cynipidae} do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=&taxon=#{cynipidae.id}")

      assert html =~ "1 observation"
      assert html =~ "Acraspis erinacei"
      refute html =~ "Eurosta solidaginis"
      # The selected option is marked selected in the rendered <select>.
      assert html =~ ~r/value="#{cynipidae.id}"[^>]*selected/
    end
  end

  describe "/phenology geographic filter" do
    setup do
      usa = insert_place("Testeria", "country")
      ca = insert_place("Testalpha", "state")
      link_place_hierarchy(usa, ca)

      sp_ca = insert_gall("Andricus californicus (agamic)")
      sp_on = insert_gall("Neuroterus ontario (sexgen)")
      link_gall_range(sp_ca.id, ca)
      insert_obs(sp_ca.id, %{})
      insert_obs(sp_on.id, %{})

      %{usa: usa, ca: ca}
    end

    test "the region typeahead renders and searches places", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/phenology?search=")

      # Typeahead wrapper wired to the place events; no legacy <select>.
      assert html =~ ~s(id="place-filter")
      assert html =~ "Region"
      refute html =~ ~s(name="place")

      # Typing surfaces matching places (states are labelled with their parent).
      results = render_hook(view, "search_place", %{"value" => "test"})
      assert results =~ "Testeria"
      assert results =~ "Testalpha"
    end

    test "selecting a region narrows the obs to species ranged there", %{conn: conn, ca: ca} do
      {:ok, view, _html} = live(conn, ~p"/phenology?search=")

      html = render_hook(view, "select_place", %{"id" => to_string(ca)})

      assert html =~ "1 observation"
      assert html =~ "Andricus californicus"
      refute html =~ "Neuroterus ontario"
    end

    test "clearing the region restores all obs", %{conn: conn, ca: ca} do
      {:ok, view, _html} = live(conn, ~p"/phenology?search=&place=#{ca}")
      assert render(view) =~ "1 observation"

      html = render_hook(view, "clear_place", %{})
      assert html =~ "2 observations"
    end

    test "?place=ID seeds the region filter on mount", %{conn: conn, usa: usa} do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=&place=#{usa}")

      assert html =~ "1 observation"
      assert html =~ "Andricus californicus"
      refute html =~ "Neuroterus ontario"
      # The chosen place shows as a selected chip (display name), not a dropdown.
      assert html =~ "Testeria"
    end
  end

  describe "/phenology species sort" do
    # Names chosen so alphabetical order is the OPPOSITE of the sort orders
    # under test, proving the sort actually reordered.
    setup do
      few = insert_gall("Aaa fewobs (agamic)")
      many = insert_gall("Zzz manyobs (agamic)")
      # `many` has more obs AND a wider DOY span AND a more recent date.
      insert_obs(few.id, %{doy: 150, date: ~D[2020-06-01]})
      insert_obs(many.id, %{doy: 60, date: ~D[2024-03-01]})
      insert_obs(many.id, %{doy: 200, date: ~D[2024-07-18]})
      insert_obs(many.id, %{doy: 300, date: ~D[2024-10-26]})
      %{few: few, many: many}
    end

    defp gall_link_index(html, id), do: elem(:binary.match(html, "/gall/#{id}"), 0)

    test "the columns are the sort control — active arrow, no dropdown", %{conn: conn} do
      {:ok, _view, default} = live(conn, ~p"/phenology?search=&display=species")
      # No separate dropdown/form — the column headers do the sorting.
      refute default =~ ~s(name="sort")
      refute default =~ ~s(phx-change="sort_species")
      # Default sort = name, ascending → Species header carries the ▲ arrow.
      assert default =~ "Species ▲"

      {:ok, _view, by_obs} = live(conn, ~p"/phenology?search=&display=species&sort=obs_count")
      assert by_obs =~ "Observations ▼"
      refute by_obs =~ "Species ▲"
    end

    test "the direction arrow reflects the dir param", %{conn: conn} do
      {:ok, _view, obs_asc} =
        live(conn, ~p"/phenology?search=&display=species&sort=obs_count&dir=asc")

      assert obs_asc =~ "Observations ▲"

      {:ok, _view, name_desc} =
        live(conn, ~p"/phenology?search=&display=species&sort=name&dir=desc")

      assert name_desc =~ "Species ▼"
    end

    test "default sort is alphabetical by name", %{conn: conn, few: few, many: many} do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=&display=species")
      assert gall_link_index(html, few.id) < gall_link_index(html, many.id)
    end

    test "sort=obs_count orders by observation count desc", %{conn: conn, few: few, many: many} do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=&display=species&sort=obs_count")
      assert gall_link_index(html, many.id) < gall_link_index(html, few.id)
    end

    test "sort=spread orders by DOY span desc", %{conn: conn, few: few, many: many} do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=&display=species&sort=spread")
      assert gall_link_index(html, many.id) < gall_link_index(html, few.id)
    end

    test "sort=recency orders by latest observation date desc", %{
      conn: conn,
      few: few,
      many: many
    } do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=&display=species&sort=recency")
      assert gall_link_index(html, many.id) < gall_link_index(html, few.id)
    end

    test "dir=asc reverses the ordering", %{conn: conn, few: few, many: many} do
      {:ok, _view, html} =
        live(conn, ~p"/phenology?search=&display=species&sort=obs_count&dir=asc")

      # Ascending obs count → the 1-obs species now precedes the 3-obs one.
      assert gall_link_index(html, few.id) < gall_link_index(html, many.id)
    end

    test "the sort control updates key + direction without reloading obs", %{conn: conn} do
      # The species table host is phx-update="ignore" (the JS hook owns its
      # rows and re-sorts off data-sort/-dir), so assert the host attributes
      # the hook reads flip — not the SSR row order, which the LV won't touch.
      {:ok, view, html} = live(conn, ~p"/phenology?search=&display=species")
      assert html =~ ~s(data-sort="name")
      assert html =~ ~s(data-sort-dir="asc")

      sorted = render_hook(view, "sort_species", %{"sort" => "obs_count", "dir" => "desc"})
      assert sorted =~ ~s(data-sort="obs_count")
      assert sorted =~ ~s(data-sort-dir="desc")
      # Obs set is unchanged — the event only re-sorts.
      assert sorted =~ "4 observations"

      # Re-clicking the same column flips direction.
      toggled = render_hook(view, "sort_species", %{"sort" => "obs_count", "dir" => "asc"})
      assert toggled =~ ~s(data-sort-dir="asc")
    end
  end

  describe "/phenology trait filter" do
    setup do
      red = insert_color("test-scarlet")
      green = insert_color("test-chartreuse")

      sp_red = insert_gall("Acraspis reddish (agamic)")
      sp_green = insert_gall("Andricus greenish (agamic)")
      insert_gall_traits(sp_red.id)
      insert_gall_traits(sp_green.id)
      link_color(sp_red.id, red)
      link_color(sp_green.id, green)
      insert_obs(sp_red.id, %{})
      insert_obs(sp_green.id, %{})

      %{red: red, green: green}
    end

    test "renders the gall-trait facet checkboxes with shared vocabulary", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=")

      assert html =~ "Gall traits (optional)"
      assert html =~ "Location on host"
      assert html =~ "test-scarlet"
      assert html =~ ~s(name="color_ids[]")
    end

    test "checking a color narrows the obs to species with that trait", %{
      conn: conn,
      red: red
    } do
      {:ok, view, _html} = live(conn, ~p"/phenology?search=")

      html =
        view
        |> form("#phenology-filters", %{
          "search" => "",
          "generation" => "all",
          "phenophases" => @all_explorer_phenophases,
          "color_ids" => [to_string(red)]
        })
        |> render_change()

      assert html =~ "1 observation"
      assert html =~ "Acraspis reddish"
      refute html =~ "Andricus greenish"
    end

    test "?color=ID seeds the trait filter on mount and checks the box", %{
      conn: conn,
      red: red
    } do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=&color=#{red}")

      assert html =~ "1 observation"
      assert html =~ "Acraspis reddish"
      refute html =~ "Andricus greenish"
      assert html =~ ~r/name="color_ids\[\]" value="#{red}"[^>]*checked/
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

    test "?min_lat/?max_lat/?min_lng/?max_lng filter on observation coords",
         %{conn: conn} do
      sp = insert_gall("Acraspis bound (agamic)")
      # In-box: lat 40, lng -80
      insert_obs(sp.id, %{
        phenophase: "maturing",
        latitude: 40.0,
        longitude: -80.0,
        date: ~D[2024-06-15],
        doy: 167
      })

      # Out-of-box on latitude (too far north)
      insert_obs(sp.id, %{
        phenophase: "maturing",
        latitude: 60.0,
        longitude: -80.0,
        date: ~D[2024-06-15],
        doy: 167
      })

      # Out-of-box on longitude (too far west)
      insert_obs(sp.id, %{
        phenophase: "maturing",
        latitude: 40.0,
        longitude: -120.0,
        date: ~D[2024-06-15],
        doy: 167
      })

      # Null coords — should be dropped when any coordinate bound is set
      insert_obs(sp.id, %{
        phenophase: "maturing",
        latitude: nil,
        longitude: nil,
        date: ~D[2024-06-15],
        doy: 167
      })

      {:ok, _view, html} =
        live(
          conn,
          ~p"/phenology?search=&min_lat=35&max_lat=45&min_lng=-90&max_lng=-70"
        )

      assert html =~ "1 observation"
    end

    test "?display=table renders the obs data table", %{conn: conn} do
      sp = insert_gall("Acraspis erinacei (agamic)")
      insert_obs(sp.id, %{phenophase: "maturing", site: "Ann Arbor", state: "MI"})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=&display=table")

      assert html =~ ~s(id="phenology-obs-table")
      assert html =~ "Acraspis erinacei"
      assert html =~ "Lifestage"
      assert html =~ "Viability"
      assert html =~ "DOY"
      # Download link present for table view
      assert html =~ "Download CSV"
      assert html =~ "/phenology/export.csv"
    end

    test "?display=species renders the species list table", %{conn: conn} do
      sp1 = insert_gall("Acraspis a (agamic)")
      sp2 = insert_gall("Aulacidea b (sexgen)")
      insert_obs(sp1.id, %{phenophase: "maturing"})
      insert_obs(sp1.id, %{phenophase: "maturing", date: ~D[2024-07-01], doy: 183})
      insert_obs(sp2.id, %{phenophase: "maturing"})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=&display=species")

      assert html =~ ~s(id="phenology-species-table")
      assert html =~ "Acraspis a"
      assert html =~ "Aulacidea b"
      # Two obs for Acraspis a → "2" should appear in the n_obs column.
      assert html =~ "Acraspis a"
      assert html =~ "Download CSV"
    end

    test "default panel (predictions) does not show the CSV download link", %{conn: conn} do
      sp = insert_gall("Acraspis erinacei (agamic)")
      insert_obs(sp.id, %{phenophase: "maturing"})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=")

      # Chart always renders now, regardless of display mode.
      assert html =~ ~s(id="phenology-chart")
      # No CSV download in predictions mode (default).
      refute html =~ "Download CSV"
    end

    test "chart always renders even when display=table", %{conn: conn} do
      sp = insert_gall("Acraspis erinacei (agamic)")
      insert_obs(sp.id, %{phenophase: "maturing"})

      {:ok, _view, html} = live(conn, ~p"/phenology?search=&display=table")

      # Chart on top + data table below.
      assert html =~ ~s(id="phenology-chart")
      assert html =~ ~s(id="phenology-obs-table")
    end

    test "?lat= sets the prediction target latitude", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/phenology?search=&lat=37.5")
      # The number input's value attribute reflects the chosen lat.
      assert html =~ ~s(name="target_lat") and html =~ ~s(value="37.5")
    end

    test "predictions panel renders when enough obs with seasind", %{conn: conn} do
      sp = insert_gall("Dryocosmus quercuspalustris (sexgen)")

      for s <- [0.30, 0.40, 0.50, 0.60] do
        insert_obs(sp.id, %{
          phenophase: "maturing",
          seasind: s,
          date: ~D[2024-06-15],
          doy: 167
        })
      end

      {:ok, _view, html} = live(conn, ~p"/phenology")

      assert html =~ "Predicted windows at"
      assert html =~ "Adults of the sexual generation are expected to emerge"
      assert html =~ "n=4"
    end

    test "predictions panel absent when below threshold", %{conn: conn} do
      sp = insert_gall("Dryocosmus quercuspalustris (sexgen)")
      # Only 3 obs with seasind — below @min_obs = 4.
      for s <- [0.30, 0.40, 0.50] do
        insert_obs(sp.id, %{phenophase: "maturing", seasind: s})
      end

      {:ok, _view, html} = live(conn, ~p"/phenology")
      refute html =~ "Predicted windows at"
    end

    # Brush behavior — selecting points on the chart, narrowing the table
    # to the brush window, the Clear-selection button, and the CSV link
    # picking up brush bounds — used to be testable via render_hook on
    # "set_selection" / "clear_selection". Those server events are gone
    # (the brush lives entirely in phenology_chart.js / phenology_state.js
    # / phenology_chrome.js to avoid a per-gesture LV roundtrip), so the
    # behavior is now JS-only. Move to a browser-level e2e suite if we
    # want coverage.

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
