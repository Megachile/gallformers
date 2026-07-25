defmodule Gallformers.AuthorshipTest do
  use Gallformers.DataCase, async: true

  alias Gallformers.Authorship
  alias Gallformers.Repo
  alias Gallformers.Sources.Source
  alias Gallformers.Species.Species
  alias Gallformers.Species.SpeciesSource

  defp species!(name) do
    Repo.insert!(%Species{name: name, taxoncode: "gall"})
  end

  defp source!(attrs) do
    Repo.insert!(struct(%Source{link: "", citation: "", license: "", datacomplete: false}, attrs))
  end

  defp entry!(species, source, description \\ "") do
    Repo.insert!(%SpeciesSource{
      species_id: species.id,
      source_id: source.id,
      description: description
    })
  end

  defp mention!(entry, attrs) do
    {:ok, mention} =
      Authorship.upsert_mention(Map.merge(%{species_source_id: entry.id}, attrs))

    mention
  end

  describe "authorship/2 — establishing entries" do
    setup do
      species = species!("Druon ignotum")

      bassett =
        source!(%{title: "New Cynipidae", author: "HF Bassett", pubyear: "1881"})

      entry = entry!(species, bassett, "Cynips ignota, n. sp.\n\nSmall oval cells")
      mention!(entry, %{name: "Cynips ignota", role: "establishes"})

      %{species: species}
    end

    test "takes author and year from the establishing entry's source", %{species: species} do
      result = Authorship.authorship("Druon ignotum", Authorship.mentions_for_species(species.id))

      assert result.authorship == "(Bassett, 1881)"
      assert result.basionym == "Cynips ignota"
      assert result.role == "establishes"
    end

    test "the basionym itself is unparenthesised", %{species: species} do
      result = Authorship.authorship("Cynips ignota", Authorship.mentions_for_species(species.id))

      assert result.authorship == "Bassett, 1881"
    end

    test "the basionym stays bare even when a later combination is on record", %{
      species: species
    } do
      # The 2022 revision restates the authorship as "Druon ignotum (Bassett,
      # 1881)". Preferring that record would parenthesise Cynips ignota, which
      # is the name Bassett actually published.
      revision = source!(%{title: "Re-establishment", author: "Cuesta-Porta", pubyear: "2022"})
      entry = entry!(species, revision, "Druon ignotum (Bassett, 1881), comb. nov.")

      mention!(entry, %{
        name: "Druon ignotum",
        role: "cites_original",
        author: "Bassett",
        year: 1881,
        parenthesised: true
      })

      mentions = Authorship.mentions_for_species(species.id)

      assert Authorship.authorship("Cynips ignota", mentions).authorship == "Bassett, 1881"
      assert Authorship.authorship("Druon ignotum", mentions).authorship == "(Bassett, 1881)"
    end

    test "a homotypic synonym inherits it, parenthesised by genus", %{species: species} do
      result =
        Authorship.authorship("Andricus ignotus", Authorship.mentions_for_species(species.id))

      assert result.authorship == "(Bassett, 1881)"
    end

    test "an unrelated name gets nothing", %{species: species} do
      assert Authorship.authorship("Quercus alba", Authorship.mentions_for_species(species.id)) ==
               nil
    end
  end

  describe "authorship/2 — cited originals" do
    test "reads a citation whose publication is not a source record" do
      species = species!("Acalitus blastofagi")

      xue =
        source!(%{
          title: "Eriophyoid mites on Fagaceae",
          author: "Xiao-Feng Xue",
          pubyear: "2009"
        })

      entry = entry!(species, xue, "Aceria blastofagi Keifer, 1966b: 15.")

      mention!(entry, %{
        name: "Aceria blastofagi",
        role: "cites_original",
        author: "Keifer",
        year: 1966
      })

      result =
        Authorship.authorship("Acalitus blastofagi", Authorship.mentions_for_species(species.id))

      assert result.authorship == "(Keifer, 1966)"
      refute result.authorship =~ "Xue"
      refute result.authorship =~ "2009"
    end

    test "keeps parentheses the citation already carried" do
      # The original genus never appears in the line, so a genus comparison
      # would compare the name to itself and drop them.
      species = species!("Phylloteras poculum")
      revision = source!(%{title: "Re-establishment", author: "Nicholls", pubyear: "2022"})
      entry = entry!(species, revision, "Phylloteras poculum (Osten Sacken, 1862)")

      mention!(entry, %{
        name: "Phylloteras poculum",
        role: "cites_original",
        author: "Osten Sacken",
        year: 1862,
        parenthesised: true
      })

      result =
        Authorship.authorship("Phylloteras poculum", Authorship.mentions_for_species(species.id))

      assert result.authorship == "(Osten Sacken, 1862)"
    end
  end

  describe "authorship/2 — precedence" do
    test "the earliest year wins, whatever restates it later" do
      species = species!("Philonix fulvicollis")
      fitch = source!(%{title: "Fitch", author: "Asa Fitch", pubyear: "1859"})
      houard = source!(%{title: "Houard", author: "C Houard", pubyear: "1934"})

      early = entry!(species, fitch, "Philonix fulvicollis, n. sp.")
      mention!(early, %{name: "Philonix fulvicollis", role: "establishes"})

      late = entry!(species, houard, "Dryophanta fulvicollis Houard, 1934: 8.")

      mention!(late, %{
        name: "Dryophanta fulvicollis",
        role: "cites_original",
        author: "Houard",
        year: 1934
      })

      result =
        Authorship.authorship("Philonix fulvicollis", Authorship.mentions_for_species(species.id))

      assert result.authorship == "Fitch, 1859"
    end

    test "an establishing entry beats a citation carrying a transcribed year" do
      # The real Neuroterus umbilicatus conflict: 1990 typed for 1900.
      species = species!("Neuroterus umbilicatus")
      bassett = source!(%{title: "Bassett", author: "HF Bassett", pubyear: "1900"})
      later = source!(%{title: "Later", author: "Someone", pubyear: "2020"})

      described = entry!(species, bassett, "Neuroterus umbilicatus, n. sp.")
      mention!(described, %{name: "Neuroterus umbilicatus", role: "establishes"})

      cited = entry!(species, later, "Neuroterus umbilicatus Bassett, 1990: 4.")

      mention!(cited, %{
        name: "Neuroterus umbilicatus",
        role: "cites_original",
        author: "Bassett",
        year: 1990
      })

      result =
        Authorship.authorship(
          "Neuroterus umbilicatus",
          Authorship.mentions_for_species(species.id)
        )

      assert result.authorship == "Bassett, 1900"
    end

    test "a heterotypic synonym keeps its own attribution" do
      species = species!("Neuroterus niger")
      gillette = source!(%{title: "Gillette", author: "CP Gillette", pubyear: "1888"})
      revision = source!(%{title: "Revision", author: "Someone", pubyear: "2020"})

      described = entry!(species, gillette, "Neuroterus niger, n. sp.")
      mention!(described, %{name: "Neuroterus niger", role: "establishes"})

      cited = entry!(species, revision, "Neuroterus papillosus Beutenmueller, 1910: 4.")

      mention!(cited, %{
        name: "Neuroterus papillosus",
        role: "cites_original",
        author: "Beutenmueller",
        year: 1910
      })

      mentions = Authorship.mentions_for_species(species.id)

      assert Authorship.authorship("Neuroterus niger", mentions).authorship == "Gillette, 1888"

      assert Authorship.authorship("Neuroterus papillosus", mentions).authorship ==
               "Beutenmueller, 1910"
    end
  end

  describe "authorship/2 — usage lines" do
    test "a name merely used supplies no authorship" do
      species = species!("Aceria blastofagi")
      catalog = source!(%{title: "Amrine Catalog", author: "James Amrine", pubyear: "2019"})
      entry = entry!(species, catalog, "Aceria blastofagi; Amrine & Stasny, 1994: 27.")

      mention!(entry, %{name: "Aceria blastofagi", role: "uses"})

      assert Authorship.authorship(
               "Aceria blastofagi",
               Authorship.mentions_for_species(species.id)
             ) ==
               nil
    end
  end

  describe "upsert_mention/1" do
    test "re-recording the same name updates rather than duplicating" do
      species = species!("Druon ignotum")
      source = source!(%{title: "S", author: "A", pubyear: "1881"})
      entry = entry!(species, source, "Cynips ignota, n. sp.")

      mention!(entry, %{name: "Cynips ignota", role: "establishes"})
      mention!(entry, %{name: "Cynips ignota", role: "cites_original", author: "X", year: 1900})

      assert [only] = Authorship.mentions_for_entry(entry.id)
      assert only.role == "cites_original"
      assert only.year == 1900
    end

    test "rejects a role outside the allowed set" do
      species = species!("Druon ignotum")
      source = source!(%{title: "S", author: "A", pubyear: "1881"})
      entry = entry!(species, source, "x")

      assert {:error, changeset} =
               Authorship.upsert_mention(%{
                 species_source_id: entry.id,
                 name: "Cynips ignota",
                 role: "invents"
               })

      assert "is invalid" in errors_on(changeset).role
    end
  end

  describe "authorships/2" do
    test "resolves many names from one query" do
      species = species!("Druon ignotum")
      bassett = source!(%{title: "New Cynipidae", author: "HF Bassett", pubyear: "1881"})
      entry = entry!(species, bassett, "Cynips ignota, n. sp.")
      mention!(entry, %{name: "Cynips ignota", role: "establishes"})

      result =
        Authorship.authorships(species.id, [
          "Druon ignotum",
          "Cynips ignota",
          "Quercus alba"
        ])

      assert result["Druon ignotum"].authorship == "(Bassett, 1881)"
      assert result["Cynips ignota"].authorship == "Bassett, 1881"
      refute Map.has_key?(result, "Quercus alba")
    end
  end
end
