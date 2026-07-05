defmodule Gallformers.Galls.HostNameMatcher do
  @moduledoc """
  Pure text matching for host plant names inside source description text.

  Used by `Gallformers.Galls.HostConsistency` to decide whether a host plant
  named in the structured `gallhost` table is actually mentioned in the prose
  of a gall's sources (and vice versa).

  Host names in the literature appear in several forms, all of which must count
  as "the current name is present":

    * verbatim current binomial — `Quercus alba`
    * abbreviated genus — `Q. alba` / `Q.alba`
    * bracketed current name (the `Quercus oldname [newname]` convention we use
      when an author's name is a synonym of our current name) — the current
      epithet appears inside `[...]`
    * genus-level placeholder hosts (`Quercus spp`) — the genus alone counts

  The module is deliberately pure (no DB, no Ecto) so it is cheap to unit test
  and can be exercised against arbitrary text.
  """

  @typedoc "A host as needed for matching: current `name` plus the genus-placeholder flag."
  @type host :: %{required(:name) => String.t(), required(:genus_placeholder) => boolean()}

  # Bracketed markers an admin can add next to a literature name to say
  # "this reported host is not a real association" — the text-flagged exception
  # that keeps a rejected literature mention out of the Direction-B queue.
  @reject_markers ~w(not a host rejected doubtful unconfirmed erroneous misidentif)

  @doc """
  Returns true when the host's current name is present in `text` in any of the
  accepted forms. `text` may be nil or empty.
  """
  @spec named_in?(host(), String.t() | nil) :: boolean()
  def named_in?(_host, nil), do: false
  def named_in?(_host, ""), do: false

  def named_in?(host, text) when is_binary(text) do
    case parse_name(host) do
      # Genus-only / placeholder host: the genus mentioned anywhere counts.
      %{epithet: nil, genus: genus} ->
        Regex.match?(word_regex(genus), text)

      %{genus: genus, epithet: epithet} ->
        Enum.any?(name_patterns(genus, epithet), &Regex.match?(&1, text)) or
          elided_binomial?(genus, epithet, text)
    end
  end

  # Authors routinely elide the genus in a list — "Quercus alba, bicolor,
  # macrocarpa" documents Q. bicolor and Q. macrocarpa without an intact
  # binomial. Count the current name as present when both the genus and the
  # epithet appear as standalone words anywhere in the same description.
  # The epithet must be reasonably specific (>= 4 chars) to avoid matching
  # short Latin color words used generically.
  defp elided_binomial?(genus, epithet, text) do
    String.length(epithet) >= 4 and
      Regex.match?(word_regex(genus), text) and
      Regex.match?(word_regex(epithet), text)
  end

  @doc """
  Returns true when `text` marks the host as an explicitly rejected literature
  report — the host's epithet immediately followed by a bracketed marker such as
  `[not a host]` / `[rejected]`. This is the Direction-B text-flagged exception.
  """
  @spec text_flag?(host(), String.t() | nil) :: boolean()
  def text_flag?(_host, nil), do: false
  def text_flag?(_host, ""), do: false

  def text_flag?(host, text) when is_binary(text) do
    case parse_name(host) do
      %{epithet: nil} ->
        false

      %{epithet: epithet} ->
        markers = Enum.map_join(@reject_markers, "|", &Regex.escape/1)

        pattern =
          ~r/\b#{Regex.escape(epithet)}\b[^\[\]]{0,40}\[[^\]]*(?:#{markers})/i

        Regex.match?(pattern, text)
    end
  end

  @doc """
  Splits a host name into `%{genus, epithet}` (both downcased), where `epithet`
  is nil for genus-level placeholders (`Quercus spp`) or single-token names.

  Handles hybrid names (`Quercus x alvordiana` / `Quercus ×undulata`) by
  skipping the `×`/`x` marker so the epithet is the actual specific epithet.
  """
  @spec parse_name(host()) :: %{genus: String.t(), epithet: String.t() | nil}
  def parse_name(%{name: name} = host) do
    [genus | rest] =
      name
      |> String.trim()
      |> String.split(~r/\s+/, trim: true)
      |> case do
        [] -> [""]
        tokens -> tokens
      end

    genus = String.downcase(genus)
    placeholder = Map.get(host, :genus_placeholder, false)

    epithet = if placeholder, do: nil, else: epithet_from(rest)

    %{genus: genus, epithet: epithet}
  end

  # Genus-level marker: no specific epithet.
  defp epithet_from([]), do: nil
  defp epithet_from([marker | _]) when marker in ["spp", "spp.", "sp", "sp."], do: nil
  # Hybrid marker as its own token ("Quercus x alvordiana") — use the next token.
  defp epithet_from([marker | rest]) when marker in ["x", "×", "X"], do: epithet_from(rest)

  defp epithet_from([token | _]) do
    # strip a glued hybrid marker ("×undulata") and downcase
    case token |> String.replace_prefix("×", "") |> String.downcase() do
      "" -> nil
      epithet -> epithet
    end
  end

  # Regex forms that count as "current name present" for a binomial host.
  defp name_patterns(genus, epithet) do
    g = Regex.escape(genus)
    e = Regex.escape(epithet)
    gi = String.first(genus)

    [
      # verbatim: "Quercus alba" (allowing any run of whitespace between tokens)
      ~r/\b#{g}\s+#{e}\b/i,
      # abbreviated genus: "Q. alba" / "Q.alba"
      ~r/\b#{Regex.escape(gi)}\.\s*#{e}\b/i,
      # bracketed current name: "... [newname]" or "... [Quercus newname]"
      ~r/\[[^\]]*\b#{e}\b/i
    ]
  end

  defp word_regex(word), do: ~r/\b#{Regex.escape(word)}\b/i
end
