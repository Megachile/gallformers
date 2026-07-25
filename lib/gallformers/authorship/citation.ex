defmodule Gallformers.Authorship.Citation do
  @moduledoc """
  Parses the nomenclatural citation lines that source entries carry in their
  body text. Pure — strings in, structs out.

  Recent source entries often open with a synonymy, and those lines state
  authorship far more reliably than the citing publication's own metadata: a
  2009 revision reproducing `Aceria blastofagi Keifer, 1966b: 15.` is telling
  you the name is Keifer's, not its own.

  ## What separates authorship from mere usage

  The punctuation between the name and the name that follows it:

      Aceria blastofagi Keifer, 1966b: 15.            # ORIGINAL — nothing between
      Druon ignotum (Bassett, 1881), comb. nov.       # ORIGINAL — parenthetical carries a year
      Aceria blastofagi; Amrine & Stasny, 1994: 27.   # usage — semicolon
      Andricus ignota (Bassett): Ashmead, 1885: 295.  # usage — parenthetical, no year, then colon

  A semicolon or a yearless parenthetical means the publication that follows
  merely *used* the name. Only an unseparated author, or a parenthetical
  containing a year, states authorship.

  The `:plain` / `:parenthesised` shape matters downstream: a `:plain` line is
  an original combination — the basionym — while a `:parenthesised` one is a
  later combination restating inherited authorship. When both are present for
  the same author and year, the `:plain` line is the one that identifies the
  original genus.
  """

  @enforce_keys [:name, :author, :year, :shape]
  defstruct [:name, :author, :year, :shape, :source_id]

  @type shape :: :plain | :parenthesised

  @type t :: %__MODULE__{
          name: String.t(),
          author: String.t(),
          year: integer(),
          shape: shape(),
          source_id: integer() | nil
        }

  # Zoological nomenclature starts with Linnaeus, 1758. Anything earlier is a
  # misparse rather than a citation.
  @earliest_year 1758

  @binomial ~r/^([A-Z][a-zà-ÿ-]+)\s+([a-zà-ÿ-]{3,})\s*/u
  @parenthetical ~r/^\(([^)]*)\)\s*/
  # "Keifer, 1966b: 15" — the comma marks the author off from the year.
  @author_year ~r/^([A-ZÀ-Þ][^,;:()0-9]{1,60}?),\s*(1[6-9]\d{2}|20\d{2})[a-z]?/u

  # "Osten Sacken 1862: 192" — no comma, so a page reference has to do the
  # work instead. Without that requirement ordinary prose parses as a
  # citation: "Reared during April 1881 from oak twigs" has a capitalised
  # word and a year, and nothing else to disqualify it.
  @author_year_paged ~r/^([A-ZÀ-Þ][^,;:()0-9]{1,60}?)\s+(1[6-9]\d{2}|20\d{2})[a-z]?\s*:/u
  @year ~r/(1[6-9]\d{2}|20\d{2})/
  @exclusion ~r/\[[^\]]*\]/

  @doc """
  Parses every citation line in a source entry's description.

  `citing_year` is the publication year of the entry's own source, when known.
  A citation cannot postdate the publication quoting it, so anything later is
  dropped — which is what catches transcription slips like `Bassett, 1990` for
  a name published in 1900.
  """
  @spec parse(String.t() | nil, integer() | nil) :: [t()]
  def parse(nil, _citing_year), do: []

  def parse(description, citing_year) when is_binary(description) do
    description
    |> String.split("\n")
    |> Enum.map(&parse_line/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.filter(&plausible?(&1, citing_year))
    |> Enum.uniq()
  end

  @doc """
  Parses a single line, returning `nil` when it is not an authorship-bearing
  citation — prose, a bare name, or a later usage.
  """
  @spec parse_line(String.t()) :: t() | nil
  def parse_line(raw) when is_binary(raw) do
    line = raw |> String.replace(@exclusion, " ") |> String.trim()

    case Regex.run(@binomial, line) do
      [_matched, genus, epithet] ->
        rest = Regex.replace(@binomial, line, "")
        classify_remainder("#{genus} #{epithet}", rest)

      _ ->
        nil
    end
  end

  defp classify_remainder(_name, ";" <> _rest), do: nil

  defp classify_remainder(name, rest) do
    case Regex.run(@parenthetical, rest) do
      [_matched, inside] -> from_parenthetical(name, inside)
      nil -> from_plain(name, rest)
    end
  end

  # `(Bassett, 1881)` states authorship; `(Bassett):` only attributes a usage.
  defp from_parenthetical(name, inside) do
    case Regex.run(@year, inside) do
      [_matched, year] ->
        author = inside |> String.replace(~r/,?\s*#{year}[a-z]?.*$/u, "") |> String.trim()
        build(name, author, year, :parenthesised)

      nil ->
        nil
    end
  end

  defp from_plain(name, rest) do
    case Regex.run(@author_year, rest) || Regex.run(@author_year_paged, rest) do
      [_matched, author, year] -> build(name, String.trim(author), year, :plain)
      nil -> nil
    end
  end

  defp build(_name, "", _year, _shape), do: nil

  defp build(name, author, year, shape) do
    %__MODULE__{name: name, author: author, year: String.to_integer(year), shape: shape}
  end

  defp plausible?(%__MODULE__{year: year}, citing_year) do
    year >= @earliest_year and year <= ceiling(citing_year)
  end

  defp ceiling(nil), do: Date.utc_today().year
  defp ceiling(citing_year) when is_integer(citing_year), do: citing_year
  defp ceiling(_citing_year), do: Date.utc_today().year

  @doc """
  Picks the citation that identifies the original combination from a set
  already narrowed to one name.

  A `:plain` line names the original genus, so it wins over a
  `:parenthesised` one restating the same authorship. Among equals, the
  earliest year takes priority.
  """
  @spec basionym([t()]) :: t() | nil
  def basionym([]), do: nil

  def basionym(citations) do
    case Enum.filter(citations, &(&1.shape == :plain)) do
      [] -> Enum.min_by(citations, & &1.year)
      plain -> Enum.min_by(plain, & &1.year)
    end
  end
end
