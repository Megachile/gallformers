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

  defp druon_aliases do
    [
      "Andricus ignota",
      "Andricus ignotus",
      "Cynips ignota",
      "Diplolepis ignota",
      "Dryophanta ignota",
      "Rhodites ignota"
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
      result = Classifier.derive("Druon ignotum", druon_aliases(), druon_sources())

      assert result.authorship == "(Bassett, 1881)"
      assert result.confidence == :high
      assert result.reason == :single_original_description
      assert result.basionym == "Cynips ignota"
      assert result.source_id == 20
    end

    test "does not take authorship from a source that merely used the name" do
      result = Classifier.derive("Druon ignotum", druon_aliases(), druon_sources())

      refute result.authorship =~ "Weld"
      refute result.authorship =~ "1959"
      refute result.authorship =~ "Cuesta-Porta"
    end

    test "flags for review when several sources announce an original description" do
      sources = [
        %{id: 1, author: "Bassett", pubyear: "1881", description: "Cynips ignota, n. sp.\n\nx"},
        %{id: 2, author: "Ashmead", pubyear: "1885", description: "Andricus ignota, n. sp.\n\ny"}
      ]

      result = Classifier.derive("Druon ignotum", [], sources)

      assert result.confidence == :review
      assert result.reason == :multiple_original_descriptions
      assert Enum.sort(result.source_ids) == [1, 2]
    end

    test "proposes the oldest source leading with one of the species' own names" do
      sources = [
        %{id: 14, author: "LH Weld", pubyear: "1959", description: "Andricus ignotus \n\n body"},
        %{id: 9, author: "ME Jones", pubyear: "1926", description: "Diplolepis ignota \n\n body"}
      ]

      result = Classifier.derive("Druon ignotum", druon_aliases(), sources)

      assert result.confidence == :candidate
      assert result.reason == :oldest_source_leading_with_own_name
      assert result.basionym == "Diplolepis ignota"
      assert result.authorship == "(Jones, 1926)"
    end

    test "returns nothing when no source leads with a usable name" do
      sources = [
        %{id: 58, author: "Gallformers", pubyear: "2023", description: "The phenotype varies."}
      ]

      result = Classifier.derive("Druon ignotum", [], sources)

      assert result.authorship == nil
      assert result.confidence == :none
    end

    test "an unrelated species' name is not accepted as a candidate" do
      sources = [
        %{id: 3, author: "Someone", pubyear: "1900", description: "Quercus alba \n\n body"}
      ]

      result = Classifier.derive("Druon ignotum", druon_aliases(), sources)

      assert result.confidence == :none
    end
  end
end
