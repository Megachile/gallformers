defmodule Gallformers.Galls.HostMentionsTest do
  @moduledoc "Unit tests for the pure plant-name mention extractor (Direction B)."
  use ExUnit.Case, async: true

  alias Gallformers.Galls.HostMentions, as: E

  test "extracts a full binomial" do
    assert {"quercus", "alba"} in E.extract("galls on Quercus alba leaves")
  end

  test "extracts hybrid binomials past the marker" do
    assert {"quercus", "undulata"} in E.extract("on Quercus × undulata")
  end

  test "extracts each species in an elided-genus list" do
    got = E.extract("Andricus parmula on Quercus douglasii, dumosa, durata, lobata")
    assert {"quercus", "douglasii"} in got
    assert {"quercus", "dumosa"} in got
    assert {"quercus", "durata"} in got
    assert {"quercus", "lobata"} in got
  end

  test "resolves an abbreviated genus against a full genus in the same text" do
    got = E.extract("Quercus alba, and also Q. rubra nearby")
    assert {"quercus", "alba"} in got
    assert {"quercus", "rubra"} in got
  end

  test "does not resolve an abbreviation with no matching spelled-out genus" do
    got = E.extract("found on Z. mystery here")
    refute {"z", "mystery"} in got
    refute Enum.any?(got, fn {_g, e} -> e == "mystery" end)
  end

  test "returns [] for nil/empty" do
    assert E.extract(nil) == []
    assert E.extract("") == []
  end

  test "yields unique pairs" do
    got = E.extract("Quercus alba and again Quercus alba")
    assert Enum.count(got, &(&1 == {"quercus", "alba"})) == 1
  end
end
