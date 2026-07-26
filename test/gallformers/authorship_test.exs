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

  describe "authorship/2 — attribution differing from the paper" do
    test "an establishing mention may name its own authority" do
      # A revision by five people describing several species attributes them
      # individually. Melika & Nicholls published this one; the paper's full
      # author list did not.
      species = species!("Andricus foo")

      revision =
        source!(%{
          title: "Revision of the oak gallwasps",
          author: "George Melika, James Nicholls, Graham Stone, Warren Abrahamson",
          pubyear: "2010"
        })

      entry = entry!(species, revision, "Andricus foo Melika & Nicholls, n. sp.")

      mention!(entry, %{
        name: "Andricus foo",
        role: "establishes",
        author: "Melika & Nicholls"
      })

      result = Authorship.authorship_for_species(species.id, "Andricus foo")

      assert result.authorship == "Melika & Nicholls, 2010"
    end

    test "falls back to the paper's authors when the mention names none" do
      species = species!("Andricus bar")

      revision =
        source!(%{
          title: "Revision",
          author: "George Melika, James Nicholls, Graham Stone",
          pubyear: "2010"
        })

      entry = entry!(species, revision, "Andricus bar, n. sp.")
      mention!(entry, %{name: "Andricus bar", role: "establishes"})

      result = Authorship.authorship_for_species(species.id, "Andricus bar")

      assert result.authorship == "Melika, Nicholls & Stone, 2010"
    end
  end

  describe "suggested_establishing_author/1" do
    test "reads an authority named on the opening line" do
      assert Authorship.suggested_establishing_author(
               "Andricus foo Melika & Nicholls, n. sp.\n\nGall."
             ) == "Melika & Nicholls"

      assert Authorship.suggested_establishing_author(
               "Acalitus capparidis Flechtmann, sp.  nov.\n\nx"
             ) == "Flechtmann"
    end

    test "does not mistake the rest of a name for an authority" do
      # The same position holds subgenera and second names.
      assert Authorship.suggested_establishing_author(
               "Andricus (Callirhytis) ruginosus, n. sp.\n\nx"
             ) == nil

      assert Authorship.suggested_establishing_author("Cecidomyia? semenivora, n. sp.\n\nx") ==
               nil
    end

    test "returns nothing when the line names only the species" do
      assert Authorship.suggested_establishing_author("Cynips ignota, n. sp.\n\nx") == nil
      assert Authorship.suggested_establishing_author("Andricus ignotus\n\nx") == nil
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

  describe "issues/0" do
    test "flags two readings that disagree on the year" do
      species = species!("Neuroterus umbilicatus")
      bassett = source!(%{title: "Bassett", author: "HF Bassett", pubyear: "1900"})
      later = source!(%{title: "Later", author: "Someone", pubyear: "2020"})

      described = entry!(species, bassett, "x")
      mention!(described, %{name: "Neuroterus umbilicatus", role: "establishes"})

      cited = entry!(species, later, "x")

      mention!(cited, %{
        name: "Neuroterus umbilicatus",
        role: "cites_original",
        author: "Bassett",
        year: 1990
      })

      assert [issue] = Authorship.issues()
      assert issue.type == :conflicting_attribution
      assert issue.species_name == "Neuroterus umbilicatus"
      assert length(issue.readings) == 2
    end

    test "one attribution written two ways is not a disagreement" do
      # "Pujade-Villar, 2018" and "Pujade-Villar et al., 2018" are the same
      # attribution; flagging them would bury the real conflicts.
      species = species!("Disholcaspis crystalae")
      one = source!(%{title: "A", author: "Juli Pujade-Villar", pubyear: "2018"})
      two = source!(%{title: "B", author: "Someone", pubyear: "2020"})

      described = entry!(species, one, "x")
      mention!(described, %{name: "Disholcaspis crystalae", role: "establishes"})

      cited = entry!(species, two, "x")

      mention!(cited, %{
        name: "Disholcaspis crystalae",
        role: "cites_original",
        author: "Pujade-Villar et al.",
        year: 2018
      })

      assert Authorship.issues() == []
    end

    test "flags two entries each claiming a different original description" do
      species = species!("Phylloteras poculum")
      osten = source!(%{title: "Osten Sacken", author: "Baron Osten Sacken", pubyear: "1862"})
      weld = source!(%{title: "Weld", author: "LH Weld", pubyear: "1926"})

      a = entry!(species, osten, "x")
      mention!(a, %{name: "Cecidomyia poculum", role: "establishes"})

      b = entry!(species, weld, "x")
      mention!(b, %{name: "Xystoteras poculum", role: "establishes"})

      assert [issue] = Authorship.issues()
      assert issue.type == :ambiguous_basionym
    end

    test "flags an establishing name belonging to neither the species nor a synonym" do
      species = species!("Neuroterus stonei")
      source = source!(%{title: "S", author: "A", pubyear: "1900"})
      entry = entry!(species, source, "x")

      # The detector reading a host plant as a binomial.
      mention!(entry, %{name: "Quercus arizonica", role: "establishes"})

      assert [issue] = Authorship.issues()
      assert issue.type == :unrelated_establishing_name
      assert issue.name == "Quercus arizonica"
    end

    test "a heterotypic synonym described from this species is not an issue" do
      species = species!("Neuroterus niger")
      gillette = source!(%{title: "G", author: "CP Gillette", pubyear: "1888"})
      beuten = source!(%{title: "B", author: "William Beutenmueller", pubyear: "1910"})

      own = entry!(species, gillette, "x")
      mention!(own, %{name: "Neuroterus niger", role: "establishes"})

      junior = entry!(species, beuten, "x")
      mention!(junior, %{name: "Neuroterus papillosus", role: "establishes"})

      alias_record =
        Repo.insert!(%Gallformers.Species.Alias{
          name: "Neuroterus papillosus",
          type: "scientific"
        })

      Repo.insert_all("alias_species", [
        [alias_id: alias_record.id, species_id: species.id]
      ])

      assert Authorship.issues() == []
    end

    test "flags a typed authorship the sources contradict" do
      species = species!("Druon ignotum")
      Repo.update!(Ecto.Changeset.change(species, authorship: "(Someone, 1950)"))

      bassett = source!(%{title: "New Cynipidae", author: "HF Bassett", pubyear: "1881"})
      entry = entry!(species, bassett, "x")
      mention!(entry, %{name: "Cynips ignota", role: "establishes"})

      assert [issue] = Authorship.issues()
      assert issue.type == :contradicted_direct_entry
      assert issue.typed == "(Someone, 1950)"
    end

    test "a typed authorship the sources agree with is not flagged" do
      species = species!("Druon ignotum")
      Repo.update!(Ecto.Changeset.change(species, authorship: "(Bassett, 1881)"))

      bassett = source!(%{title: "New Cynipidae", author: "HF Bassett", pubyear: "1881"})
      entry = entry!(species, bassett, "x")
      mention!(entry, %{name: "Cynips ignota", role: "establishes"})

      assert Authorship.issues() == []
    end

    test "a name merely used contributes no issues" do
      species = species!("Aceria blastofagi")
      catalog = source!(%{title: "Catalog", author: "James Amrine", pubyear: "2019"})
      entry = entry!(species, catalog, "x")

      mention!(entry, %{name: "Aceria blastofagi", role: "uses"})

      assert Authorship.issues() == []
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

  describe "authorship recorded directly on the species" do
    test "is used when no source entry establishes the name" do
      species = Repo.insert!(%Species{name: "Aulacidea hieracii", taxoncode: "gall"})
      Repo.update!(Ecto.Changeset.change(species, authorship: "(Linnaeus, 1758)"))

      result = Authorship.authorship_for_species(species.id, "Aulacidea hieracii")

      assert result.authorship == "(Linnaeus, 1758)"
      assert result.role == "recorded_directly"
      assert result.basionym == nil
    end

    test "is superseded once an entry establishes the name" do
      species = species!("Druon ignotum")
      Repo.update!(Ecto.Changeset.change(species, authorship: "(Someone, 1900)"))

      bassett = source!(%{title: "New Cynipidae", author: "HF Bassett", pubyear: "1881"})
      entry = entry!(species, bassett, "Cynips ignota, n. sp.")
      mention!(entry, %{name: "Cynips ignota", role: "establishes"})

      result = Authorship.authorship_for_species(species.id, "Druon ignotum")

      assert result.authorship == "(Bassett, 1881)"
      assert result.role == "establishes"
    end

    test "applies only to the species' own name, never to a synonym" do
      species = species!("Druon ignotum")
      Repo.update!(Ecto.Changeset.change(species, authorship: "(Bassett, 1881)"))

      resolved = Authorship.authorships(species.id, ["Druon ignotum", "Cynips ignota"])

      assert resolved["Druon ignotum"].authorship == "(Bassett, 1881)"
      refute Map.has_key?(resolved, "Cynips ignota")
    end

    test "a blank value is not an authorship" do
      species = species!("Druon ignotum")
      Repo.update!(Ecto.Changeset.change(species, authorship: "   "))

      assert Authorship.authorship_for_species(species.id, "Druon ignotum") == nil
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
