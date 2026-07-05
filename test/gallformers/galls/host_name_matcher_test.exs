defmodule Gallformers.Galls.HostNameMatcherTest do
  @moduledoc "Unit tests for the pure host-name-in-source-text matcher."
  use ExUnit.Case, async: true

  alias Gallformers.Galls.HostNameMatcher, as: M

  defp host(name, placeholder \\ false), do: %{name: name, genus_placeholder: placeholder}

  describe "named_in?/2 — binomial hosts" do
    test "matches verbatim current name (case-insensitive)" do
      assert M.named_in?(host("Quercus alba"), "found on Quercus alba in spring") == true
      assert M.named_in?(host("Quercus alba"), "reported from QUERCUS ALBA") == true
    end

    test "matches abbreviated genus form" do
      assert M.named_in?(host("Quercus alba"), "galls on Q. alba only") == true
      assert M.named_in?(host("Quercus alba"), "on Q.alba (no space)") == true
    end

    test "matches current epithet inside brackets (old-name convention)" do
      assert M.named_in?(host("Quercus sinuata"), "on Quercus durandii [sinuata]") == true
      assert M.named_in?(host("Quercus sinuata"), "on Quercus durandii [Quercus sinuata]") == true
    end

    test "matches an elided-genus list (name not intact as a binomial)" do
      # "Quercus alba, bicolor, macrocarpa" documents Q. bicolor + Q. macrocarpa
      text = "on Quercus alba, bicolor, macrocarpa, prinoides"
      assert M.named_in?(host("Quercus bicolor"), text) == true
      assert M.named_in?(host("Quercus macrocarpa"), text) == true
    end

    test "matches when genus and epithet co-occur out of order in the text" do
      assert M.named_in?(host("Quercus stellata"), "Quercus galls; the stellata form is distinct") ==
               true
    end

    test "short epithet does not match via co-occurrence alone (guard)" do
      # epithet under 4 chars only counts when the intact/abbreviated name is present
      refute M.named_in?(host("Genus abc"), "Genus present here and abc elsewhere")
      assert M.named_in?(host("Genus abc"), "found on Genus abc directly") == true
    end

    test "parses hybrid names past the × / x marker" do
      # epithet is the real specific epithet, not the hybrid marker
      assert M.parse_name(host("Quercus x alvordiana")).epithet == "alvordiana"
      assert M.parse_name(host("Quercus ×undulata")).epithet == "undulata"

      assert M.named_in?(host("Quercus x alvordiana"), "on Quercus alvordiana leaves") == true
      assert M.named_in?(host("Quercus ×undulata"), "galls on Quercus undulata") == true
    end

    test "does not match when the name is absent" do
      refute M.named_in?(host("Quercus alba"), "found on Quercus rubra and Q. velutina")
    end

    test "does not match a different epithet that shares a prefix" do
      refute M.named_in?(host("Quercus alba"), "on Quercus albacans")
    end

    test "genus alone does not document a specific binomial host" do
      refute M.named_in?(host("Quercus alba"), "several oaks in the genus Quercus")
    end

    test "nil / empty text is never a match" do
      refute M.named_in?(host("Quercus alba"), nil)
      refute M.named_in?(host("Quercus alba"), "")
    end
  end

  describe "named_in?/2 — genus-level / placeholder hosts" do
    test "placeholder host matches on the genus alone" do
      assert M.named_in?(host("Quercus spp", true), "on various Quercus species") == true
    end

    test "unflagged 'Genus spp' name is still treated as genus-level" do
      assert M.named_in?(host("Quercus spp"), "on Quercus") == true
    end

    test "placeholder host does not match an unrelated genus" do
      refute M.named_in?(host("Quercus spp", true), "on Acer and Salix")
    end
  end

  describe "text_flag?/2 — rejected literature host" do
    test "flags an epithet followed by a rejection marker" do
      assert M.text_flag?(host("Quercus falsa"), "Quercus falsa [not a host], see notes") == true
      assert M.text_flag?(host("Quercus falsa"), "reported as falsa [rejected here]") == true
    end

    test "does not flag a plain mention with no marker" do
      refute M.text_flag?(host("Quercus falsa"), "also found on Quercus falsa")
    end

    test "does not flag a marker attached to a different name" do
      refute M.text_flag?(
               host("Quercus falsa"),
               "Quercus rubra [rejected]; Quercus falsa is valid"
             )
    end
  end
end
