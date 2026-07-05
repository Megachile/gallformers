defmodule GallformersWeb.Admin.HostConsistencyLiveTest do
  use GallformersWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Repo

  defp setup_admin_session(conn) do
    user = %Auth0User{
      id: "test-user-id",
      email: "admin@test.com",
      name: "Test Admin",
      roles: ["admin"]
    }

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
    |> put_session(:db_display_name, "Test User")
  end

  defp species(name, taxoncode, opts \\ []) do
    Repo.insert!(%Gallformers.Species.Species{
      name: name,
      taxoncode: taxoncode,
      genus_placeholder: Keyword.get(opts, :placeholder, false)
    })
  end

  defp taxon(name, type, opts \\ []) do
    Repo.insert!(%Gallformers.Taxonomy.Taxonomy{
      name: name,
      type: type,
      parent_id: Keyword.get(opts, :parent_id)
    })
  end

  defp link_taxon(species_id, taxonomy_id) do
    Repo.insert_all("species_taxonomy", [%{species_id: species_id, taxonomy_id: taxonomy_id}])
  end

  defp source do
    Repo.insert!(%Gallformers.Sources.Source{
      title: "Src #{System.unique_integer([:positive])}",
      author: "A",
      pubyear: "2000",
      link: "https://example.org",
      citation: "c",
      license: "public domain"
    })
  end

  # A gall with one undocumented host under a gall family; returns names + family id.
  defp undocumented_world do
    u = System.unique_integer([:positive])
    fam = taxon("Fam#{u}", "family")
    gen = taxon("Gen#{u}", "genus", parent_id: fam.id)
    gall = species("Testgall#{u} (agamic)", "gall")
    link_taxon(gall.id, gen.id)

    host = species("Testoak#{u} alba", "plant")
    Repo.insert!(%Gallformers.Galls.GallHost{gall_species_id: gall.id, host_species_id: host.id})

    src = source()

    Repo.insert!(%Gallformers.Species.SpeciesSource{
      species_id: gall.id,
      source_id: src.id,
      description: "reported only from Testoak#{u} rubra"
    })

    %{family_id: fam.id, gall: gall, host: host}
  end

  describe "Host Association Review page" do
    setup %{conn: conn} do
      {:ok, %{conn: setup_admin_session(conn)}}
    end

    test "renders and prompts for a filter before loading the queue", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/host-consistency")

      assert html =~ "Host Association Review"
      assert html =~ "Choose an inducer or host family"
    end

    test "lists the undocumented host once a family filter is applied", %{conn: conn} do
      %{family_id: fam_id, gall: gall, host: host} = undocumented_world()

      {:ok, _view, html} = live(conn, ~p"/admin/host-consistency?gfam=#{fam_id}")

      assert html =~ gall.name
      assert html =~ host.name
      assert html =~ "1 discrepancy"
    end

    test "Direction B lists a plant named in the prose with no association", %{conn: conn} do
      u = System.unique_integer([:positive])
      fam = taxon("Fam#{u}", "family")
      gen = taxon("Gen#{u}", "genus", parent_id: fam.id)
      gall = species("Testgall#{u} (agamic)", "gall")
      link_taxon(gall.id, gen.id)
      # alpha-only genus so the Direction-B extractor can pull it from prose
      plant = species("Qwertyuiop rubra", "plant")
      src = source()

      Repo.insert!(%Gallformers.Species.SpeciesSource{
        species_id: gall.id,
        source_id: src.id,
        description: "galls recorded on Qwertyuiop rubra in autumn"
      })

      {:ok, _view, html} = live(conn, ~p"/admin/host-consistency?gfam=#{fam.id}&dir=b")

      assert html =~ plant.name
      assert html =~ "lit. mention"
    end

    test "an unrelated family filter shows the empty (all-clear) state", %{conn: conn} do
      undocumented_world()
      other = taxon("Empty#{System.unique_integer([:positive])}", "family")

      {:ok, _view, html} = live(conn, ~p"/admin/host-consistency?gfam=#{other.id}")

      assert html =~ "No discrepancies in this scope"
    end
  end
end
