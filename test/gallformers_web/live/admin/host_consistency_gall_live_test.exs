defmodule GallformersWeb.Admin.HostConsistencyGallLiveTest do
  use GallformersWeb.ConnCase

  import Phoenix.LiveViewTest

  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Repo

  defp setup_admin_session(conn) do
    user = %Auth0User{id: "u", email: "a@t.com", name: "Admin", roles: ["admin"]}

    conn
    |> init_test_session(%{})
    |> put_session(:current_user, user)
    |> put_session(:db_display_name, "Test")
  end

  defp species(name, taxoncode) do
    Repo.insert!(%Gallformers.Species.Species{name: name, taxoncode: taxoncode})
  end

  defp source(title) do
    Repo.insert!(%Gallformers.Sources.Source{
      title: title,
      author: "A",
      pubyear: "2000",
      link: "https://example.org",
      citation: "c",
      license: "public domain"
    })
  end

  setup %{conn: conn} do
    {:ok, %{conn: setup_admin_session(conn)}}
  end

  test "renders host status, mentions, and source text", %{conn: conn} do
    u = System.unique_integer([:positive])
    gall = species("Testgall#{u} (agamic)", "gall")
    doc = species("Qwertyuiop alba", "plant")
    undoc = species("Qwertyuiop stellata", "plant")
    species("Qwertyuiop rubra", "plant")
    src = source("Monograph #{u}")

    Repo.insert!(%Gallformers.Species.SpeciesSource{
      species_id: gall.id,
      source_id: src.id,
      description: "on Qwertyuiop alba; also Qwertyuiop rubra nearby"
    })

    Repo.insert!(%Gallformers.Galls.GallHost{gall_species_id: gall.id, host_species_id: doc.id})
    Repo.insert!(%Gallformers.Galls.GallHost{gall_species_id: gall.id, host_species_id: undoc.id})

    {:ok, _view, html} = live(conn, ~p"/admin/host-consistency/gall/#{gall.id}")

    assert html =~ gall.name
    assert html =~ "Qwertyuiop alba"
    assert html =~ "documented"
    assert html =~ "undocumented"
    # rubra is named in the prose but not a host -> appears as a mention
    assert html =~ "Qwertyuiop rubra"
    assert html =~ "Monograph #{u}"
  end

  test "shows a not-found state for a missing id", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/host-consistency/gall/99999999")
    assert html =~ "could not be found"
  end
end
