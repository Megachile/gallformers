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

  # Alpha-only unique genus (no digits) so the Direction-B regex extractor,
  # which matches genus as [A-Z][a-z]+, can pick it out of prose.
  defp uniq_alpha do
    letters = for _ <- 1..9, into: "", do: <<Enum.random(?a..?z)>>
    String.capitalize(letters)
  end

  # A gall under its own family/genus with a source note; returns family + gall.
  defp gall_with_note(description, opts \\ []) do
    u = System.unique_integer([:positive])
    fam = taxon("Fam#{u}", "family")
    gen = taxon("Gen#{u}", "genus", parent_id: fam.id)
    gall = species("Testgall#{u} (agamic)", "gall")
    link_taxon(gall.id, gen.id)
    src = source(id: opts[:source_id])
    note(gall.id, src.id, description)
    %{fam: fam, gall: gall}
  end

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

  # --- Direction B -----------------------------------------------------------

  test "Direction B flags a plant named in prose with no gallhost row" do
    g = uniq_alpha()
    species("#{g} rubra", "plant")
    %{fam: fam} = gall_with_note("galls found on #{g} rubra leaves")

    assert %{total: 1, items: [item]} =
             Galls.host_discrepancies(%{gall_taxon_id: fam.id, direction: :b})

    assert item.host_name == "#{g} rubra"
    assert item.direction == :unassociated_mention
    assert item.snippet =~ "rubra"
  end

  test "Direction B ignores a mentioned plant that IS already a host" do
    g = uniq_alpha()
    host = species("#{g} rubra", "plant")
    %{fam: fam, gall: gall} = gall_with_note("galls found on #{g} rubra leaves")
    gall_host(gall.id, host.id)

    assert %{total: 0} = Galls.host_discrepancies(%{gall_taxon_id: fam.id, direction: :b})
  end

  test "Direction B ignores a mention that does not resolve to a real plant" do
    %{fam: fam} = gall_with_note("some morphological description with Capitalized Words")
    assert %{total: 0} = Galls.host_discrepancies(%{gall_taxon_id: fam.id, direction: :b})
  end

  test "Direction B respects a [not a host] text flag" do
    g = uniq_alpha()
    species("#{g} rubra", "plant")
    %{fam: fam} = gall_with_note("#{g} rubra [not a host]; a reporting error")

    assert %{total: 0} = Galls.host_discrepancies(%{gall_taxon_id: fam.id, direction: :b})
  end

  test "Direction B resolves each plant in an elided-genus list" do
    g = uniq_alpha()
    species("#{g} alba", "plant")
    species("#{g} bicolor", "plant")
    %{fam: fam} = gall_with_note("recorded from #{g} alba, bicolor")

    assert %{total: 2, items: items} =
             Galls.host_discrepancies(%{gall_taxon_id: fam.id, direction: :b})

    names = Enum.map(items, & &1.host_name) |> Enum.sort()
    assert names == ["#{g} alba", "#{g} bicolor"]
  end

  test "direction :both returns undocumented associations and unassociated mentions" do
    g = uniq_alpha()
    # a mentioned-but-unassociated plant (Direction B)
    species("#{g} rubra", "plant")
    %{fam: fam, gall: gall} = gall_with_note("on #{g} rubra; also hosts #{g} alba")
    # an associated host that is NOT named in the note (Direction A) — alba is named,
    # so use a separate undocumented host
    undoc = species("#{g} stellata", "plant")
    gall_host(gall.id, undoc.id)

    assert %{total: total, items: items} =
             Galls.host_discrepancies(%{gall_taxon_id: fam.id, direction: :both})

    dirs = items |> Enum.map(& &1.direction) |> Enum.uniq() |> Enum.sort()
    assert :undocumented_association in dirs
    assert :unassociated_mention in dirs
    assert total >= 2
  end
end
