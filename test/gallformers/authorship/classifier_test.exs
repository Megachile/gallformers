defmodule Gallformers.Authorship.ClassifierTest do
  use ExUnit.Case, async: true

  alias Gallformers.Authorship.Classifier

  # The real source entries attached to Druon ignotum, trimmed to the parts
  # the classifier reads. Source 20 is Bassett's original description; 554 is
  # the 2022 revision carrying the full synonymy; 14 and 9 merely use later
  # combinations.
  defp druon_sources do
    [
      %{
        id: 20,
        author: "HF Bassett",
        pubyear: "1881",
        description:
          "Cynips ignota, n. sp. \n\n Small oval cells, found singly or in small clusters"
      },
      %{
        id: 14,
        author: "LH Weld",
        pubyear: "1959",
        description: "Andricus ignotus \n\n Quercus bicolor | Leaf galls, detachable"
      },
      %{
        id: 9,
        author: "ME Jones",
        pubyear: "1926",
        description:
          "Diplolepis ignota [distinct from the rose gall of the same name] \n\n The galls on Quercus bicolor are common"
      },
      %{
        id: 58,
        author: "Gallformers",
        pubyear: "2023",
        description: "The phenotype of this gall seems to vary by region."
      },
      %{
        id: 554,
        author:
          "Victor Cuesta-Porta, George Melika, James Nicholls, Graham Stone, Juli Pujade-Villar",
        pubyear: "2022",
        description:
          "Druon ignotum (Bassett, 1881), comb. nov. \n\n Cynips ignota Bassett, 1881: 106, female, gall."
      }
    ]
  end

  describe "epithet_stem/1" do
    test "collapses Latin gender variants onto one stem" do
      assert Classifier.epithet_stem("ignota") == "ignot"
      assert Classifier.epithet_stem("ignotum") == "ignot"
      assert Classifier.epithet_stem("ignotus") == "ignot"
    end

    test "leaves short epithets intact rather than collapsing them" do
      assert Classifier.epithet_stem("rosa") == "rosa"
    end

    test "returns nil for a missing epithet" do
      assert Classifier.epithet_stem(nil) == nil
    end
  end

  describe "classify/2" do
    test "same epithet stem in a different genus is homotypic" do
      assert Classifier.classify("Druon ignotum", "Cynips ignota") == :homotypic
      assert Classifier.classify("Druon ignotum", "Andricus ignotus") == :homotypic
    end

    test "a different epithet is heterotypic" do
      assert Classifier.classify("Druon ignotum", "Andricus wooliferous") == :heterotypic
    end

    test "generation qualifiers do not affect the call" do
      assert Classifier.classify("Druon ignotum (agamic)", "Cynips ignota") == :homotypic
    end

    test "placeholder names are indeterminate" do
      assert Classifier.classify("Unknown (Cynipidae)", "Cynips ignota") == :indeterminate
      assert Classifier.classify("Druon", "Cynips ignota") == :indeterminate
    end
  end

  describe "strip_exclusions/1" do
    test "removes a bracketed homonym warning so it cannot be read as authorship" do
      line =
        "Rhodites ignota (Bassett): Dalla Torre, 1893: 127. [NOT Andricus ignota Bassett, 1900 (junior homonym).]"

      stripped = Classifier.strip_exclusions(line)

      refute stripped =~ "1900"
      assert stripped =~ "Dalla Torre, 1893"
    end
  end

  describe "leading_name/1" do
    test "reads the binomial each real source entry opens with" do
      for {description, expected} <- [
            {"Cynips ignota, n. sp. \n\n Small oval cells", "Cynips ignota"},
            {"Andricus ignotus \n\n Quercus bicolor", "Andricus ignotus"},
            {"Diplolepis ignota [distinct from the rose gall] \n\n The galls",
             "Diplolepis ignota"},
            {"Druon ignotum (Bassett, 1881), comb. nov. \n\n Cynips ignota", "Druon ignotum"}
          ] do
        assert Classifier.leading_name(description) == expected
      end
    end

    test "returns nil when the entry does not open with a binomial" do
      assert Classifier.leading_name("The phenotype of this gall varies by region.") == nil
      assert Classifier.leading_name(nil) == nil
    end
  end

  describe "original_description?/1" do
    test "detects the nomenclatural act on the first line" do
      assert Classifier.original_description?("Cynips ignota, n. sp. \n\n Small oval cells") ==
               true

      assert Classifier.original_description?("Andricus foo sp. nov.\n\nbody") == true
    end

    test "comb. nov. is not an original description" do
      refute Classifier.original_description?("Druon ignotum (Bassett, 1881), comb. nov.\n\nbody")
    end

    test "ignores a marker that appears only deeper in the body" do
      refute Classifier.original_description?("Andricus ignotus \n\n later described as n. sp.")
    end
  end

  describe "authors/1 and year/1" do
    test "reduces a source author to surnames in authorship style" do
      assert Classifier.authors("HF Bassett") == "Bassett"
      assert Classifier.authors("HF Bassett & WH Ashmead") == "Bassett & Ashmead"

      assert Classifier.authors(
               "Victor Cuesta-Porta, George Melika, James Nicholls, Graham Stone, Juli Pujade-Villar"
             ) == "Cuesta-Porta et al."
    end

    test "pulls a year out of the free-text pubyear column" do
      assert Classifier.year("1881") == "1881"
      assert Classifier.year("c. 1881") == "1881"
      assert Classifier.year(nil) == nil
      assert Classifier.year("undated") == nil
    end
  end

  describe "parenthesised?/2 and format_authorship/3" do
    test "parenthesises only when the genus has changed since the original" do
      assert Classifier.parenthesised?("Druon ignotum", "Cynips ignota") == true
      refute Classifier.parenthesised?("Cynips ignota", "Cynips ignota")
    end

    test "formats with and without parentheses" do
      assert Classifier.format_authorship("Bassett", "1881", true) == "(Bassett, 1881)"
      assert Classifier.format_authorship("Bassett", "1881", false) == "Bassett, 1881"
      assert Classifier.format_authorship(nil, "1881", false) == nil
      assert Classifier.format_authorship("Bassett", nil, false) == nil
    end
  end

  describe "derive/3" do
    test "recovers the published authorship for Druon ignotum" do
      result = Classifier.derive("Druon ignotum", druon_sources())

      assert result.authorship == "(Bassett, 1881)"
      assert result.confidence == :high
      assert result.basionym == "Cynips ignota"
    end

    test "reports corroboration when both lines of evidence agree" do
      # Bassett's 1881 entry announces the description; the 2022 revision's
      # synonymy states the same authorship. Two independent readings agreeing
      # is the strongest evidence available.
      result = Classifier.derive("Druon ignotum", druon_sources())

      assert result.reason == :corroborated
      assert result.confidence == :high
    end

    test "flags for review when the two lines of evidence disagree" do
      # The real Neuroterus umbilicatus conflict: a transcribed year of 1990
      # for a name published in 1900.
      sources = [
        %{
          id: 1,
          author: "HF Bassett",
          pubyear: "1900",
          description: "Neuroterus umbilicatus, n. sp.\n\nbody"
        },
        %{
          id: 2,
          author: "Later Author",
          pubyear: "2020",
          description: "Neuroterus umbilicatus Bassett, 1990: 4."
        }
      ]

      result = Classifier.derive("Neuroterus umbilicatus", sources)

      assert result.confidence == :review
      assert result.reason == :evidence_disagrees
      assert result.authorship == "Bassett, 1990"
      assert result.alternative == "Bassett, 1900"
    end

    test "falls back to a marked original description when no citation line exists" do
      sources = [
        %{
          id: 20,
          author: "HF Bassett",
          pubyear: "1881",
          description: "Cynips ignota, n. sp. \n\n Small oval cells"
        }
      ]

      result = Classifier.derive("Druon ignotum", sources)

      assert result.reason == :single_original_description
      assert result.authorship == "(Bassett, 1881)"
      assert result.source_id == 20
    end

    test "does not take authorship from a source that merely used the name" do
      result = Classifier.derive("Druon ignotum", druon_sources())

      refute result.authorship =~ "Weld"
      refute result.authorship =~ "1959"
      refute result.authorship =~ "Cuesta-Porta"
    end

    test "flags for review when several sources announce an original description" do
      sources = [
        %{id: 1, author: "Bassett", pubyear: "1881", description: "Cynips ignota, n. sp.\n\nx"},
        %{id: 2, author: "Ashmead", pubyear: "1885", description: "Andricus ignota, n. sp.\n\ny"}
      ]

      result = Classifier.derive("Druon ignotum", sources)

      assert result.confidence == :review
      assert result.reason == :multiple_original_descriptions
      assert Enum.sort(result.source_ids) == [1, 2]
    end

    test "sources that merely use the name yield nothing at all" do
      # Previously these produced a :candidate from whichever source was
      # oldest, which in the real data was usually a later revision or a
      # catalogue. Silence is the correct answer.
      sources = [
        %{id: 14, author: "LH Weld", pubyear: "1959", description: "Andricus ignotus \n\n body"},
        %{id: 9, author: "ME Jones", pubyear: "1926", description: "Diplolepis ignota \n\n body"}
      ]

      result = Classifier.derive("Druon ignotum", sources)

      assert result.confidence == :none
      assert result.authorship == nil
    end

    test "keeps the parentheses a citation already carries" do
      # The real Phylloteras poculum entry. The source wrote the parentheses
      # because the name moved out of Cecidomyia; the original genus never
      # appears in the line, so comparing genera would compare the name to
      # itself and wrongly drop them.
      sources = [
        %{
          id: 559,
          author: "Nicholls et al.",
          pubyear: "2022",
          description: "Phylloteras poculum (Osten Sacken, 1862), sexual generation\n\nGall."
        }
      ]

      result = Classifier.derive("Phylloteras poculum", sources)

      assert result.authorship == "(Osten Sacken, 1862)"
    end

    test "reads authorship out of a catalogue that reproduces the citation" do
      # The real Acalitus blastofagi entry: a 2009 revision whose body states
      # Keifer's 1966 name. Crediting the 2009 authors would be wrong, and the
      # 1994 catalogue line is a usage, not a description.
      sources = [
        %{
          id: 135,
          author: "Xiao-Feng Xue, Zi-Wei Song, Xiao-Yue Hong",
          pubyear: "2009",
          description:
            "Aceria blastofagi\n\nAceria blastofagi Keifer, 1966b: 15.\nAceria blastofagi; Amrine & Stasny, 1994: 27."
        }
      ]

      result = Classifier.derive("Acalitus blastofagi", sources)

      assert result.authorship == "(Keifer, 1966)"
      assert result.basionym == "Aceria blastofagi"
      refute result.authorship =~ "Xue"
      refute result.authorship =~ "Amrine"
    end

    test "returns nothing when no source leads with a usable name" do
      sources = [
        %{id: 58, author: "Gallformers", pubyear: "2023", description: "The phenotype varies."}
      ]

      result = Classifier.derive("Druon ignotum", sources)

      assert result.authorship == nil
      assert result.confidence == :none
    end

    test "an unrelated species' name is not accepted as a candidate" do
      sources = [
        %{id: 3, author: "Someone", pubyear: "1900", description: "Quercus alba \n\n body"}
      ]

      result = Classifier.derive("Druon ignotum", sources)

      assert result.confidence == :none
    end

    test "a heterotypic alias does not supply the species' authorship" do
      # Neuroterus vernus is a separate description sunk into this species. Its
      # author and year belong to the synonym, not to Neuroterus niger.
      sources = [
        %{id: 4, author: "LH Weld", pubyear: "1926", description: "Neuroterus vernus \n\n body"}
      ]

      result = Classifier.derive("Neuroterus niger", sources)

      assert result.confidence == :none
    end
  end

  describe "generation_stem/1" do
    test "strips either generation qualifier" do
      assert Classifier.generation_stem("Druon ignotum (agamic)") == "Druon ignotum"
      assert Classifier.generation_stem("Druon ignotum (sexgen)") == "Druon ignotum"
      assert Classifier.generation_stem("Druon ignotum") == "Druon ignotum"
    end
  end

  describe "derive_generations/1" do
    test "the senior name's authorship applies to both generations" do
      # Described separately, as different species, until the life cycle was
      # closed. Bassett's 1890 sexgen name is senior, so by priority it becomes
      # the valid name of both rows; Weld's 1920 agamic name survives only as a
      # deprecated synonym of the generation it was described from.
      rows = [
        %{
          name: "Neuroterus vernus (sexgen)",
          sources: [
            %{
              id: 1,
              author: "HF Bassett",
              pubyear: "1890",
              description: "Neuroterus vernus, n. sp.\n\nbody"
            }
          ]
        },
        %{
          name: "Neuroterus vernus (agamic)",
          sources: [
            %{
              id: 2,
              author: "LH Weld",
              pubyear: "1920",
              description: "Neuroterus agamica, n. sp.\n\nbody"
            }
          ]
        }
      ]

      results = Classifier.derive_generations(rows)

      assert results["Neuroterus vernus (sexgen)"].authorship == "Bassett, 1890"
      assert results["Neuroterus vernus (agamic)"].authorship == "Bassett, 1890"
      assert results["Neuroterus vernus (agamic)"].reason == :earliest_original_description
    end

    test "pools sources so a generation lacking the original description still resolves" do
      # The real Druon failure: source 20 hangs off the agamic row only, but
      # both rows bear the name it established.
      rows = [
        %{
          name: "Druon ignotum (agamic)",
          sources: druon_sources()
        },
        %{
          name: "Druon ignotum (sexgen)",
          sources: [
            %{
              id: 554,
              author: "Victor Cuesta-Porta, George Melika",
              pubyear: "2022",
              description: "Druon ignotum (Bassett, 1881), comb. nov.\n\nbody"
            }
          ]
        }
      ]

      results = Classifier.derive_generations(rows)

      assert results["Druon ignotum (agamic)"].authorship == "(Bassett, 1881)"
      assert results["Druon ignotum (sexgen)"].authorship == "(Bassett, 1881)"
      refute results["Druon ignotum (sexgen)"].authorship =~ "Cuesta-Porta"
    end

    test "a lone row keeps derive/2 semantics" do
      rows = [
        %{name: "Druon ignotum", sources: druon_sources()}
      ]

      results = Classifier.derive_generations(rows)

      assert results["Druon ignotum"].confidence == :high
      assert results["Druon ignotum"].authorship == "(Bassett, 1881)"
    end
  end

  describe "alias_authorships/2" do
    test "a heterotypic synonym keeps the author and year it was published under" do
      # Three separate descriptions sunk into one species. Each junior name
      # keeps its own authorship; it does not inherit the species'.
      sources = [
        %{
          id: 7,
          author: "Revision",
          pubyear: "2020",
          description: """
          Neuroterus niger Gillette, 1888: 12.
          Neuroterus papillosus Beutenmueller, 1910: 4.
          Neuroterus perminimus Bassett, 1900: 9.
          """
        }
      ]

      citations = Classifier.citations(sources)

      result =
        Classifier.alias_authorships(
          ["Neuroterus papillosus", "Neuroterus perminimus"],
          citations
        )

      assert result["Neuroterus papillosus"] == "Beutenmueller, 1910"
      assert result["Neuroterus perminimus"] == "Bassett, 1900"

      # ...while the species itself takes the homotypic line.
      assert Classifier.derive("Neuroterus niger", sources).authorship == "Gillette, 1888"
    end

    test "a homotypic synonym resolves to the shared basionym" do
      sources = [
        %{
          id: 8,
          author: "Revision",
          pubyear: "2020",
          description: "Cynips ignota Bassett, 1881: 106."
        }
      ]

      result =
        Classifier.alias_authorships(["Andricus ignotus"], Classifier.citations(sources))

      assert result["Andricus ignotus"] == "(Bassett, 1881)"
    end

    test "names the citations say nothing about are omitted" do
      sources = [
        %{id: 9, author: "X", pubyear: "2020", description: "Cynips ignota Bassett, 1881: 106."}
      ]

      result = Classifier.alias_authorships(["Quercus alba"], Classifier.citations(sources))

      assert result == %{}
    end
  end
end
