defmodule Gallformers.Authorship.CitationTest do
  use ExUnit.Case, async: true

  alias Gallformers.Authorship.Citation

  describe "parse_line/1 — authorship versus usage" do
    test "an unseparated author states the original combination" do
      assert %Citation{name: "Aceria blastofagi", author: "Keifer", year: 1966, shape: :plain} =
               Citation.parse_line("Aceria blastofagi Keifer, 1966b: 15.")
    end

    test "a parenthetical carrying a year states inherited authorship" do
      assert %Citation{
               name: "Druon ignotum",
               author: "Bassett",
               year: 1881,
               shape: :parenthesised
             } =
               Citation.parse_line("Druon ignotum (Bassett, 1881), comb. nov.")
    end

    test "a semicolon marks a later usage, not authorship" do
      assert Citation.parse_line("Aceria blastofagi; Amrine & Stasny, 1994: 27.") == nil
    end

    test "a yearless parenthetical followed by a colon marks a later usage" do
      assert Citation.parse_line("Andricus ignota (Bassett): Ashmead, 1885: 295.") == nil

      assert Citation.parse_line("Diplolepis ignota (Bassett): Dalla Torre & Kieffer, 1910: 360.") ==
               nil
    end

    test "bracketed homonym warnings cannot supply authorship" do
      line =
        "Rhodites ignota (Bassett): Dalla Torre, 1893: 127. [NOT Andricus ignota Bassett, 1900]"

      assert Citation.parse_line(line) == nil
    end

    test "multi-author names survive intact" do
      assert %Citation{author: "Tooker & Hanks", year: 2004} =
               Citation.parse_line("Antistrophus meganae Tooker & Hanks, 2004: 33.")
    end

    test "prose is not a citation" do
      assert Citation.parse_line("The phenotype of this gall varies by region.") == nil
      assert Citation.parse_line("Reared during April 1881 from oak twigs.") == nil
      assert Citation.parse_line("Andricus ignotus") == nil
    end
  end

  describe "parse/2 — plausibility" do
    test "drops a citation that postdates the publication quoting it" do
      # A real transcription slip: Bassett, 1900 typed as 1990 in a 1926 paper.
      text = "Neuroterus umbilicatus Bassett, 1990: 4."

      assert Citation.parse(text, 1926) == []
      assert [%Citation{year: 1990}] = Citation.parse(text, 2020)
    end

    test "drops years before the start of zoological nomenclature" do
      assert Citation.parse("Cynips quercus Linnaeus, 1puppy: 3.", 1900) == []
      assert Citation.parse("Cynips quercus Linnaeus, 1601: 3.", 1900) == []
    end

    test "collects every citation line in an entry" do
      text = """
      Druon ignotum (Bassett, 1881), comb. nov.

      Cynips ignota Bassett, 1881: 106, female, gall.
      Andricus ignota (Bassett): Ashmead, 1885: 295.
      Dryophanta ignota (Bassett): Ashmead, 1887: 127.
      """

      parsed = Citation.parse(text, 2022)

      assert length(parsed) == 2
      assert Enum.map(parsed, & &1.shape) |> Enum.sort() == [:parenthesised, :plain]
    end

    test "returns nothing for a missing description" do
      assert Citation.parse(nil, 1900) == []
    end
  end

  describe "basionym/1" do
    test "the plain line wins over a parenthesised one restating it" do
      citations =
        Citation.parse(
          "Druon ignotum (Bassett, 1881), comb. nov.\nCynips ignota Bassett, 1881: 106.",
          2022
        )

      assert %Citation{name: "Cynips ignota", shape: :plain} = Citation.basionym(citations)
    end

    test "among plain lines the earliest year takes priority" do
      citations =
        Citation.parse(
          "Neuroterus perminimus Beutenmuller, 1910: 4.\nNeuroterus perminimus Bassett, 1900: 9.",
          2020
        )

      assert %Citation{author: "Bassett", year: 1900} = Citation.basionym(citations)
    end

    test "falls back to a parenthesised line when that is all there is" do
      citations = Citation.parse("Druon ignotum (Bassett, 1881), comb. nov.", 2022)

      assert %Citation{shape: :parenthesised} = Citation.basionym(citations)
    end

    test "nothing in, nothing out" do
      assert Citation.basionym([]) == nil
    end
  end
end
