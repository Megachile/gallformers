defmodule GallformersWeb.PhenologyControllerTest do
  @moduledoc """
  Tests for the CSV export endpoint at GET /phenology/export.csv.
  Mirrors the LiveView's filter-param semantics so the same URL maps to
  a corresponding download.
  """
  use GallformersWeb.ConnCase, async: true

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
