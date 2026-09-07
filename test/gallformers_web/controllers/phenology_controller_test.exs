defmodule GallformersWeb.PhenologyControllerTest do
  @moduledoc """
  Tests for the CSV export endpoint at GET /phenology/export.csv.
  Mirrors the LiveView's filter-param semantics so the same URL maps to
  a corresponding download.
  """
  use GallformersWeb.ConnCase, async: true

  alias Gallformers.Phenology
  alias Gallformers.Phenology.Math, as: PhenologyMath
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.Taxonomy

  defp insert_gall(name) do
    {:ok, sp} =
      Repo.insert(%Species{name: name, taxoncode: "gall", datacomplete: false})

    sp
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

  describe "GET /phenology/export.csv" do
    test "default (no display) returns the obs table CSV", %{conn: conn} do
      sp = insert_gall("Dryocosmus quercuspalustris (agamic)")

      insert_obs(sp.id, %{
        phenophase: "maturing",
        site: "Site A",
        state: "MI",
        country: "USA",
        source_url: "https://example.org/source",
        page_url: "https://example.org/page"
      })

      conn = get(conn, ~p"/phenology/export.csv")

      assert response_content_type(conn, :csv) =~ "text/csv"

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="phenology_observations.csv")
             ]

      body = response(conn, 200)
      assert body =~ "species,phenophase,lifestage,viability,host,doy,date"
      assert body =~ "Dryocosmus quercuspalustris (agamic)"
      assert body =~ "maturing"
      assert body =~ "https://example.org/source"
      assert body =~ "https://example.org/page"
    end

    test "?display=species returns the species summary CSV", %{conn: conn} do
      sp1 = insert_gall("Acraspis a (agamic)")
      sp2 = insert_gall("Aulacidea b (sexgen)")
      insert_obs(sp1.id, %{})
      insert_obs(sp1.id, %{date: ~D[2024-07-01], doy: 183})
      insert_obs(sp2.id, %{})

      conn = get(conn, ~p"/phenology/export.csv?search=&display=species")

      assert get_resp_header(conn, "content-disposition") == [
               ~s(attachment; filename="phenology_species.csv")
             ]

      body = response(conn, 200)
      assert body =~ "species,n_obs"
      assert body =~ "Acraspis a (agamic),2"
      assert body =~ "Aulacidea b (sexgen),1"
    end

    test "?search= clears default and exports across species", %{conn: conn} do
      sp1 = insert_gall("Acraspis erinacei (agamic)")
      sp2 = insert_gall("Aulacidea b (sexgen)")
      insert_obs(sp1.id, %{})
      insert_obs(sp2.id, %{})

      body =
        conn
        |> get(~p"/phenology/export.csv?search=&display=table")
        |> response(200)

      assert body =~ "Acraspis erinacei"
      assert body =~ "Aulacidea b"
    end

    test "?gen= filters the exported obs", %{conn: conn} do
      sex = insert_gall("Aulacidea s (sexgen)")
      agam = insert_gall("Acraspis a (agamic)")
      insert_obs(sex.id, %{})
      insert_obs(agam.id, %{})

      body =
        conn
        |> get(~p"/phenology/export.csv?search=&gen=sexgen&display=table")
        |> response(200)

      assert body =~ "Aulacidea s"
      refute body =~ "Acraspis a"
    end

    test "?taxon= filters the exported obs to the taxon subtree", %{conn: conn} do
      family = insert_taxon(%{name: "Cynipidae", type: "family", description: "Wasp"})
      genus = insert_taxon(%{name: "Acraspis", type: "genus", parent_id: family.id})
      other_family = insert_taxon(%{name: "Tephritidae", type: "family", description: "Fly"})
      other_genus = insert_taxon(%{name: "Eurosta", type: "genus", parent_id: other_family.id})

      inside = insert_gall("Acraspis erinacei (agamic)")
      outside = insert_gall("Eurosta solidaginis")
      link_taxon(inside.id, genus.id)
      link_taxon(outside.id, other_genus.id)
      insert_obs(inside.id, %{})
      insert_obs(outside.id, %{})

      body =
        conn
        |> get(~p"/phenology/export.csv?search=&display=table&taxon=#{family.id}")
        |> response(200)

      assert body =~ "Acraspis erinacei"
      refute body =~ "Eurosta solidaginis"
    end

    test "?color= filters the exported obs to galls with that trait", %{conn: conn} do
      red = insert_color("test-crimson")
      green = insert_color("test-lime")

      sp_red = insert_gall("Acraspis reddish (agamic)")
      sp_green = insert_gall("Andricus greenish (agamic)")
      insert_gall_traits(sp_red.id)
      insert_gall_traits(sp_green.id)
      link_color(sp_red.id, red)
      link_color(sp_green.id, green)
      insert_obs(sp_red.id, %{})
      insert_obs(sp_green.id, %{})

      body =
        conn
        |> get(~p"/phenology/export.csv?search=&display=table&color=#{red}")
        |> response(200)

      assert body =~ "Acraspis reddish"
      refute body =~ "Andricus greenish"
    end

    test "?display=species&sort=obs_count orders the species CSV by count", %{conn: conn} do
      few = insert_gall("Aaa fewobs (agamic)")
      many = insert_gall("Zzz manyobs (agamic)")
      insert_obs(few.id, %{})
      insert_obs(many.id, %{})
      insert_obs(many.id, %{date: ~D[2024-07-01], doy: 183})

      body =
        conn
        |> get(~p"/phenology/export.csv?search=&display=species&sort=obs_count")
        |> response(200)

      lines = String.split(body, "\n", trim: true)
      # Header, then the higher-count species (Zzz, 2) before the lower (Aaa, 1).
      assert Enum.at(lines, 0) =~ "species,n_obs,latest"
      assert Enum.at(lines, 1) =~ "Zzz manyobs"
      assert Enum.at(lines, 2) =~ "Aaa fewobs"
    end

    test "?dir=asc reverses the species CSV order", %{conn: conn} do
      few = insert_gall("Aaa fewobs (agamic)")
      many = insert_gall("Zzz manyobs (agamic)")
      insert_obs(few.id, %{})
      insert_obs(many.id, %{})
      insert_obs(many.id, %{date: ~D[2024-07-01], doy: 183})

      body =
        conn
        |> get(~p"/phenology/export.csv?search=&display=species&sort=obs_count&dir=asc")
        |> response(200)

      lines = String.split(body, "\n", trim: true)
      # Ascending count → the 1-obs species (Aaa) precedes the 2-obs one (Zzz).
      assert Enum.at(lines, 1) =~ "Aaa fewobs"
      assert Enum.at(lines, 2) =~ "Zzz manyobs"
    end

    test "?place= filters the exported obs to species ranged in the region", %{conn: conn} do
      usa = insert_place("Testeria", "country")
      ca = insert_place("Testalpha", "state")
      link_place_hierarchy(usa, ca)

      inside = insert_gall("Andricus californicus (agamic)")
      outside = insert_gall("Neuroterus ontario (sexgen)")
      link_gall_range(inside.id, ca)
      insert_obs(inside.id, %{})
      insert_obs(outside.id, %{})

      # Selecting the country rolls up to its states.
      body =
        conn
        |> get(~p"/phenology/export.csv?search=&display=table&place=#{usa}")
        |> response(200)

      assert body =~ "Andricus californicus"
      refute body =~ "Neuroterus ontario"
    end

    test "sel_mode=date_range narrows the exported CSV to the DOY window", %{conn: conn} do
      sp = insert_gall("Acraspis erinacei (agamic)")
      insert_obs(sp.id, %{doy: 120, date: ~D[2024-04-29]})
      insert_obs(sp.id, %{doy: 250, date: ~D[2024-09-06]})

      body =
        conn
        |> get(
          ~p"/phenology/export.csv?search=&display=table&sel_mode=date_range&sel_doy=120&sel_days=10"
        )
        |> response(200)

      # Header + the single in-window (DOY 120, within 120±10) row.
      lines = String.split(body, "\n", trim: true)
      assert length(lines) == 2
      assert Enum.at(lines, 1) =~ ",120,"
      refute body =~ ",250,"
    end

    test "sel_mode=season_index narrows the exported CSV to the seasind band", %{conn: conn} do
      # Server recomputes the season index from sel_doy + sel_lat exactly as
      # the client does, so derive the reference value the same way here.
      si = PhenologyMath.season_index(120, 40.0)

      sp = insert_gall("Acraspis erinacei (agamic)")
      insert_obs(sp.id, %{doy: 100, date: ~D[2024-04-09], seasind: si})
      insert_obs(sp.id, %{doy: 260, date: ~D[2024-09-16], seasind: min(si + 0.3, 0.99)})

      body =
        conn
        |> get(
          ~p"/phenology/export.csv?search=&display=table&sel_mode=season_index&sel_doy=120&sel_lat=40&sel_thr=0.02"
        )
        |> response(200)

      # Only the obs whose seasind sits inside the ±0.02 band survives.
      lines = String.split(body, "\n", trim: true)
      assert length(lines) == 2
      assert Enum.at(lines, 1) =~ ",100,"
      refute body =~ ",260,"
    end

    test "brush bounds in URL narrow the exported CSV", %{conn: conn} do
      sp = insert_gall("Acraspis erinacei (agamic)")
      insert_obs(sp.id, %{phenophase: "maturing", doy: 120, date: ~D[2024-04-29]})
      insert_obs(sp.id, %{phenophase: "maturing", doy: 200, date: ~D[2024-07-18]})

      body =
        conn
        |> get(
          ~p"/phenology/export.csv?search=&display=table&doy_min=100&doy_max=150&lat_min=0&lat_max=90"
        )
        |> response(200)

      # Two header lines + one data row (DOY 120 in window, DOY 200 out).
      lines = body |> String.split("\n", trim: true)
      assert length(lines) == 2
      assert Enum.at(lines, 1) =~ "120"
      refute body =~ "200"
    end

    test "default search filter (Dryocosmus) is applied when ?search= is absent",
         %{conn: conn} do
      dryo = insert_gall("Dryocosmus quercuspalustris (agamic)")
      other = insert_gall("Acraspis other (agamic)")
      insert_obs(dryo.id, %{})
      insert_obs(other.id, %{})

      body =
        conn
        |> get(~p"/phenology/export.csv?display=table")
        |> response(200)

      assert body =~ "Dryocosmus quercuspalustris"
      refute body =~ "Acraspis other"
    end
  end
end
