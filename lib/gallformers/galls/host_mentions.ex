defmodule Gallformers.Galls.HostMentions do
  @moduledoc """
  Pure extraction of candidate plant-name mentions from source description text,
  for the Direction-B side of `Gallformers.Galls.HostConsistency` (plants named
  in the prose that may lack a `gallhost` row).

  Returns `{genus, epithet}` pairs (downcased). The caller resolves each pair
  against the real plant-species dictionary, so this extractor can be generous —
  pairs that don't resolve to an actual plant (insect names, morphology words,
  linked gall names) are simply dropped downstream.

  Handles the forms authors use to name multiple hosts:

    * full binomials — `Quercus alba`, hybrids `Quercus × undulata`
    * elided lists — `Quercus alba, bicolor, macrocarpa` (bare epithets share the
      preceding genus)
    * genus abbreviations — `Q. rubra` (the initial resolved to a full genus
      spelled elsewhere in the same text)
  """

  @typedoc "A candidate mention: downcased genus + specific epithet."
  @type mention :: {String.t(), String.t()}

  # Genus token: Capitalized, >= 3 letters. Epithet: lowercase, >= 3 letters.
  @binomial ~r/\b([A-Z][a-z]{2,})\s+(?:×\s*)?([a-z]{3,})\b/
  @elided ~r/\b([A-Z][a-z]{2,})\s+(?:×\s*)?[a-z]{3,}((?:\s*,\s*[a-z]{3,})+)/
  @abbrev ~r/\b([A-Z])\.\s*([a-z]{3,})\b/

  @doc """
  Extracts unique candidate `{genus, epithet}` mentions (downcased) from `text`.
  """
  @spec extract(String.t() | nil) :: [mention()]
  def extract(nil), do: []
  def extract(""), do: []

  def extract(text) when is_binary(text) do
    full = binomials(text)
    genera = full |> Enum.map(&elem(&1, 0)) |> Enum.uniq()

    (full ++ elided(text) ++ abbreviations(text, genera))
    |> Enum.uniq()
  end

  defp binomials(text) do
    @binomial
    |> Regex.scan(text)
    |> Enum.map(fn [_, genus, epithet] -> {String.downcase(genus), String.downcase(epithet)} end)
  end

  # "Quercus alba, bicolor, macrocarpa" → {quercus, bicolor}, {quercus, macrocarpa}
  defp elided(text) do
    @elided
    |> Regex.scan(text)
    |> Enum.flat_map(fn [_, genus, tail] ->
      genus = String.downcase(genus)

      tail
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(fn epithet -> {genus, String.downcase(epithet)} end)
    end)
  end

  # "Q. rubra" → {quercus, rubra} when a genus starting with "q" was spelled out.
  defp abbreviations(text, genera) do
    @abbrev
    |> Regex.scan(text)
    |> Enum.flat_map(fn [_, initial, epithet] ->
      init = String.downcase(initial)

      case Enum.find(genera, &String.starts_with?(&1, init)) do
        nil -> []
        genus -> [{genus, String.downcase(epithet)}]
      end
    end)
  end
end
