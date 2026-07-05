defmodule Gallformers.Galls.HostConsistencyTest do
  @moduledoc "Tests for the host↔source consistency checker (Direction A)."
  use Gallformers.DataCase, async: true

  alias Gallformers.Galls
  alias Gallformers.Galls.HostConsistency

  # --- fixtures (own data, unique names so seed data can't collide) -----------

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

  defp gall_host(gall_id, host_id) do
    Repo.insert!(%Gallformers.Galls.GallHost{gall_species_id: gall_id, host_species_id: host_id})
  end

  defp note(species_id, source_id, description) do
    Repo.insert!(%Gallformers.Species.SpeciesSource{
      species_id: species_id,
      source_id: source_id,
      description: description
    })
  end

  defp source(opts) do
    attrs = %Gallformers.Sources.Source{
      title: "Src #{System.unique_integer([:positive])}",
      author: "Author",
      pubyear: "2000",
      link: "https://example.org",
      citation: "cite",
      license: "public domain"
    }

    case Keyword.get(opts, :id) do
      nil -> Repo.insert!(attrs)
      id -> Repo.get(Gallformers.Sources.Source, id) || Repo.insert!(%{attrs | id: id})
    end
  end

  # Builds a gall (under a gall family/genus) with one host (under a plant
  # family/genus) plus an optional source note. Every taxon/gall name is
  # uniquified; the caller supplies the host `name` and `description` (which the
  # matcher compares) using `uniq_genus/0` so seed data can't collide.
  defp scenario(host_name, description, opts \\ []) do
    u = System.unique_integer([:positive])
    gfam = taxon("GFam#{u}", "family")
    ggen = taxon("Ggen#{u}", "genus", parent_id: gfam.id)
    gall = species("Testgall#{u} (agamic)", "gall")
    link_taxon(gall.id, ggen.id)

    hfam = taxon("HFam#{u}", "family")
    hgen = taxon("Hgen#{u}", "genus", parent_id: hfam.id)
    host = species(host_name, "plant", placeholder: Keyword.get(opts, :placeholder, false))
    link_taxon(host.id, hgen.id)

    gall_host(gall.id, host.id)

    src = source(id: opts[:source_id])
    if description, do: note(gall.id, src.id, description)

    %{gall: gall, host: host, gfam: gfam, hfam: hfam, src: src}
  end

  defp uniq_genus, do: "Testoak#{System.unique_integer([:positive])}"

  # --- Direction A -----------------------------------------------------------

  test "flags a host whose name is absent from the gall's source text" do
    g = uniq_genus()

    %{gall: gall, host: host, gfam: gfam} =
      scenario("#{g} alba", "found on #{g} rubra only")

    assert %{total: 1, items: [item]} = Galls.host_discrepancies(%{gall_taxon_id: gfam.id})
    assert item.gall_id == gall.id
    assert item.host_id == host.id
    assert item.direction == :undocumented_association
  end

  test "does not flag a host named verbatim in the source text" do
    g = uniq_genus()
    %{gfam: gfam} = scenario("#{g} alba", "galls on #{g} alba leaves")
    assert %{total: 0, items: []} = Galls.host_discrepancies(%{gall_taxon_id: gfam.id})
  end

  test "does not flag a host documented via an elided-genus list" do
    g = uniq_genus()
    %{gfam: gfam} = scenario("#{g} bicolor", "on #{g} alba, bicolor, macrocarpa")
    assert %{total: 0} = Galls.host_discrepancies(%{gall_taxon_id: gfam.id})
  end

  test "documents a genus-level placeholder host from the genus alone" do
    g = uniq_genus()
    %{gfam: gfam} = scenario("#{g} spp", "various #{g} in the region", placeholder: true)
    assert %{total: 0} = Galls.host_discrepancies(%{gall_taxon_id: gfam.id})
  end

  # --- Filters ---------------------------------------------------------------

  test "requires a taxon filter — returns empty with none" do
    g = uniq_genus()
    scenario("#{g} alba", "on #{g} rubra")
    assert %{total: 0, items: []} = Galls.host_discrepancies(%{})
  end

  test "host_taxon_id narrows to hosts under the chosen taxon" do
    g = uniq_genus()
    %{hfam: hfam} = scenario("#{g} alba", "on #{g} rubra")

    assert %{total: 1} = Galls.host_discrepancies(%{host_taxon_id: hfam.id})

    other = taxon("OtherFam#{System.unique_integer([:positive])}", "family")
    assert %{total: 0} = Galls.host_discrepancies(%{host_taxon_id: other.id})
  end

  test "has_gf_notes filter separates galls with/without GF Notes (source 58)" do
    g = uniq_genus()
    %{gfam: gfam} = scenario("#{g} alba", "on #{g} rubra", source_id: 58)

    assert %{total: 1} = Galls.host_discrepancies(%{gall_taxon_id: gfam.id, has_gf_notes: :with})

    assert %{total: 0} =
             Galls.host_discrepancies(%{gall_taxon_id: gfam.id, has_gf_notes: :without})
  end

  test "gf_notes_source_id/0 is 58" do
    assert HostConsistency.gf_notes_source_id() == 58
  end
end
