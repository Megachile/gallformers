defmodule Gallformers.Authorship.Classifier do
  @moduledoc """
  Pure logic for recovering taxonomic authorship from the sources already
  attached to a species. No database access — every function takes strings
  or plain maps.

  ## The rule

  Author and year attach to a name's *original description*, never to a
  subsequent usage. In a homotypic series — one basionym moved between
  genera — every combination shares the original author and year, and the
  authorship is parenthesised whenever the current genus differs from the
  genus of the original description:

      Cynips ignota Bassett, 1881      # original combination
      Druon ignotum (Bassett, 1881)    # moved to Druon, so parenthesised

  A heterotypic synonym is a separate description later sunk into this
  species. It carries its own author and year, recoverable only from its own
  original-description source — not from the species' basionym.

  ## Two traps

  Bracketed content is excluded material, not authorship. In

      Rhodites ignota (Bassett): Dalla Torre, 1893: 127. [NOT Andricus ignota Bassett, 1900]

  the bracketed `Bassett, 1900` is a homonym warning. `strip_exclusions/1`
  removes it before anything else reads the line.

  In that same line the colon separates the name from the author who *used*
  it: `Dalla Torre, 1893` is not the authorship, which remains `(Bassett)`.
  Only an unparenthesised name carries its own author and year.
  """

  alias Gallformers.TaxonName

  # Latin gender endings, longest first so "orum" is preferred over "um".
  @gender_ending ~r/(orum|arum|ae|us|um|is|a|e|i|o)$/
  @min_stem_length 4

  @origin_marker ~r/\bn\.\s?sp\.|\bsp\.\s?nov\.?|\bnew species\b/i
  @exclusion ~r/\[[^\]]*\]/
  @parenthetical ~r/\([^)]*\)/
  @year_pattern ~r/\b(1[6-9]\d{2}|20\d{2})\b/
  @genus_word ~r/^[A-Z][a-zA-Z-]+$/
  @epithet_word ~r/^[a-z][a-z-]+$/
  @qualifiers ~w(agamic sexgen)

  @type relation :: :homotypic | :heterotypic | :indeterminate

  @type source :: %{
          optional(atom()) => any(),
          id: integer(),
          author: String.t() | nil,
          pubyear: String.t() | nil,
          description: String.t() | nil
        }

  @doc """
  Reduces an epithet to a gender-neutral stem so that `ignota`, `ignotum` and
  `ignotus` compare equal.

  Falls back to the unmodified epithet when stripping would leave fewer than
  #{@min_stem_length} characters, which keeps short epithets from collapsing
  into each other.

      iex> epithet_stem("ignotum")
      "ignot"
  """
  @spec epithet_stem(String.t() | nil) :: String.t() | nil
  def epithet_stem(nil), do: nil

  def epithet_stem(epithet) when is_binary(epithet) do
    base = epithet |> String.trim() |> String.downcase()
    stripped = Regex.replace(@gender_ending, base, "")

    if String.length(stripped) >= @min_stem_length, do: stripped, else: base
  end

  @doc """
  Decides whether a scientific alias is the same basionym as the species
  (homotypic, so it inherits the species' author and year) or an independent
  description (heterotypic, so it needs its own source).

  Returns `:indeterminate` when either name cannot be resolved to a
  genus/epithet pair — placeholder "Unknown (Family)" records, mostly.

      iex> classify("Druon ignotum", "Cynips ignota")
      :homotypic
  """
  @spec classify(String.t(), String.t()) :: relation()
  def classify(species_name, alias_name)
      when is_binary(species_name) and is_binary(alias_name) do
    species = TaxonName.parse(species_name)
    alias_name = TaxonName.parse(alias_name)

    cond do
      species.unknown? or alias_name.unknown? -> :indeterminate
      is_nil(species.epithet) or is_nil(alias_name.epithet) -> :indeterminate
      epithet_stem(species.epithet) == epithet_stem(alias_name.epithet) -> :homotypic
      true -> :heterotypic
    end
  end

  @doc """
  Removes bracketed exclusions (`[NOT ...]`, `[distinct from ...]`) so their
  contents are never mistaken for authorship.
  """
  @spec strip_exclusions(String.t()) :: String.t()
  def strip_exclusions(text) when is_binary(text),
    do: String.replace(text, @exclusion, " ")

  @doc """
  Extracts the binomial a source entry leads with, following the house
  convention that a `species_source` description opens with the name that
  source used.

  Returns `nil` when the opening does not look like a binomial.

      iex> leading_name("Cynips ignota, n. sp.\\n\\nSmall oval cells...")
      "Cynips ignota"
  """
  @spec leading_name(String.t() | nil) :: String.t() | nil
  def leading_name(nil), do: nil

  def leading_name(description) when is_binary(description) do
    description
    |> first_line()
    |> strip_exclusions()
    |> String.replace(@parenthetical, " ")
    |> String.split(",", parts: 2)
    |> hd()
    |> binomial()
  end

  @doc """
  True when the source entry announces an original description (`n. sp.`,
  `sp. nov.`, `new species`).

  Only the first line is considered — the house convention puts the
  nomenclatural act next to the name, and scanning the whole description
  picks up incidental mentions of other taxa.
  """
  @spec original_description?(String.t() | nil) :: boolean()
  def original_description?(nil), do: false

  def original_description?(description) when is_binary(description) do
    description
    |> first_line()
    |> strip_exclusions()
    |> then(&Regex.match?(@origin_marker, &1))
  end

  @doc """
  Formats a `source.author` string into authorship style: surnames only, with
  `&` for two authors and `et al.` for three or more.

      iex> authors("HF Bassett")
      "Bassett"
  """
  @spec authors(String.t() | nil) :: String.t() | nil
  def authors(nil), do: nil

  def authors(author_string) when is_binary(author_string) do
    author_string
    |> String.split(~r/\s*(?:,|;|&|\band\b)\s*/, trim: true)
    |> Enum.map(&surname/1)
    |> Enum.reject(&(&1 in [nil, ""]))
    |> format_author_list()
  end

  @doc """
  Pulls a four-digit year out of a `source.pubyear`, which is a free-text
  string column.
  """
  @spec year(String.t() | integer() | nil) :: String.t() | nil
  def year(nil), do: nil

  def year(pubyear) do
    case Regex.run(@year_pattern, to_string(pubyear)) do
      [matched | _] -> matched
      nil -> nil
    end
  end

  @doc """
  True when authorship should be parenthesised — that is, when the current
  genus differs from the genus of the original description.
  """
  @spec parenthesised?(String.t(), String.t()) :: boolean()
  def parenthesised?(current_name, original_name)
      when is_binary(current_name) and is_binary(original_name) do
    TaxonName.parse(current_name).genus != TaxonName.parse(original_name).genus
  end

  @doc """
  Assembles an authorship string.

      iex> format_authorship("Bassett", "1881", true)
      "(Bassett, 1881)"
  """
  @spec format_authorship(String.t() | nil, String.t() | nil, boolean()) :: String.t() | nil
  def format_authorship(nil, _year, _parenthesised?), do: nil
  def format_authorship(_authors, nil, _parenthesised?), do: nil

  def format_authorship(authors, year, parenthesised?) do
    base = "#{authors}, #{year}"
    if parenthesised?, do: "(#{base})", else: base
  end

  @doc """
  Derives authorship for a species from the sources attached to it.

  Returns a map with `:authorship` (nil when nothing could be derived),
  `:confidence` and `:reason`, plus the basionym and source it came from so a
  reviewer can check the call.

  Confidence is:

    * `:high` — exactly one attached source announces an original description
      *of this name*
    * `:review` — several do, so a human picks
    * `:candidate` — none announce one, but the oldest attached source leads
      with a homotypic name. Proposed, never applied blind.
    * `:none` — nothing to go on

  A source announcing an original description of some *other* name — a junior
  synonym described from this species, say — is not a basionym candidate. Its
  author and year belong to that synonym.

  Aliases are deliberately not consulted: a homotypic alias shares the
  species' epithet stem and so is already matched by `own_name?`, and a
  heterotypic one carries authorship that is not this species'.
  """
  @spec derive(String.t(), [source()]) :: map()
  def derive(species_name, sources) do
    scored = Enum.map(sources, &score(species_name, &1))

    case Enum.filter(scored, &basionym_candidate?/1) do
      [only] -> build(species_name, only, :high, :single_original_description)
      [] -> candidate(species_name, scored)
      several -> ambiguous(species_name, several)
    end
  end

  @doc """
  Strips the generation qualifier from a species name, giving the name the two
  generations of one wasp share.

      iex> generation_stem("Druon ignotum (agamic)")
      "Druon ignotum"
  """
  @spec generation_stem(String.t()) :: String.t()
  def generation_stem(name) when is_binary(name) do
    name |> String.replace(~r/\s*\((?:#{Enum.join(@qualifiers, "|")})\)\s*/, " ") |> String.trim()
  end

  @doc """
  Derives authorship for all generations of one wasp at once.

  The two generations were often described separately, as different species,
  until someone closed the life cycle. From that point both rows carry the
  same valid name, so they carry the same authorship: the senior one, by
  priority. Sources are therefore pooled across the generations — the valid
  name's original description is frequently attached to only one of the rows.

  Aliases are *not* pooled. A junior name stays a deprecated synonym of the
  generation it was described from, and keeps its own author and year. That
  separation is automatic here: a junior name has a different epithet, so it
  is heterotypic with the valid name and never competes to be the basionym.

  Takes a list of `%{name:, sources:}` and returns a map of name to result. A
  single-element list falls through to `derive/2`, which keeps the `:review`
  signal meaningful for species that are not generation-split.
  """
  @spec derive_generations([%{name: String.t(), sources: [source()]}]) :: %{String.t() => map()}
  def derive_generations([single]) do
    %{single.name => derive(single.name, single.sources)}
  end

  def derive_generations([first | _] = rows) do
    valid_name = generation_stem(first.name)

    pooled =
      rows
      |> Enum.flat_map(& &1.sources)
      |> Enum.map(&score(valid_name, &1))

    case Enum.filter(pooled, &basionym_candidate?/1) do
      [] -> pooled_candidate(valid_name, pooled, rows)
      candidates -> senior_result(valid_name, candidates, rows)
    end
  end

  # No marked original description anywhere in the pair. Fall back to the
  # oldest pooled source leading with a homotypic name, and give both rows the
  # same answer — priority applies here too, and two generations of one wasp
  # showing different authorship is always wrong.
  defp pooled_candidate(valid_name, pooled, rows) do
    pooled
    |> Enum.filter(fn scored -> scored.own_name? and not is_nil(scored.year) end)
    |> Enum.min_by(& &1.year, fn -> nil end)
    |> case do
      nil -> Map.new(rows, &{&1.name, none()})
      oldest -> share(rows, build(valid_name, oldest, :candidate, :oldest_pooled_source))
    end
  end

  defp basionym_candidate?(scored) do
    scored.original_description? and scored.own_name? and not is_nil(scored.year)
  end

  # Priority: the earliest available name wins, and applies to both generations.
  defp senior_result(valid_name, candidates, rows) do
    senior = Enum.min_by(candidates, & &1.year)

    share(rows, build(valid_name, senior, :high, :earliest_original_description))
  end

  defp share(rows, result), do: Map.new(rows, &{&1.name, result})

  # -- internals ------------------------------------------------------------

  defp score(species_name, source) do
    description = Map.get(source, :description)
    leading = leading_name(description)

    %{
      source_id: Map.get(source, :id),
      leading_name: leading,
      original_description?: original_description?(description) and not is_nil(leading),
      authors: authors(Map.get(source, :author)),
      year: year(Map.get(source, :pubyear)),
      own_name?: not is_nil(leading) and same_species?(species_name, leading)
    }
  end

  defp same_species?(species_name, other), do: classify(species_name, other) == :homotypic

  defp build(species_name, scored, confidence, reason) do
    parenthesised? =
      not is_nil(scored.leading_name) and parenthesised?(species_name, scored.leading_name)

    %{
      authorship: format_authorship(scored.authors, scored.year, parenthesised?),
      confidence: confidence,
      reason: reason,
      basionym: scored.leading_name,
      source_id: scored.source_id
    }
  end

  # No source announces an original description. The oldest attached source
  # that leads with one of this species' own names is a plausible stand-in,
  # but it is only ever proposed for review.
  #
  # Only homotypic leading names qualify. A heterotypic alias carries its own
  # author and year — those belong to the synonym, not to this species — so
  # matching against the alias list would import the wrong authorship.
  defp candidate(species_name, scored) do
    scored
    |> Enum.filter(fn s -> s.own_name? and not is_nil(s.year) end)
    |> Enum.min_by(& &1.year, fn -> nil end)
    |> case do
      nil -> none()
      oldest -> build(species_name, oldest, :candidate, :oldest_source_leading_with_own_name)
    end
  end

  defp ambiguous(species_name, several) do
    species_name
    |> build(hd(several), :review, :multiple_original_descriptions)
    |> Map.put(:source_ids, Enum.map(several, & &1.source_id))
  end

  defp none do
    %{
      authorship: nil,
      confidence: :none,
      reason: :no_usable_source,
      basionym: nil,
      source_id: nil
    }
  end

  defp first_line(text) do
    text |> String.split("\n", parts: 2) |> hd() |> String.trim()
  end

  # The house convention puts the name alone on the opening line, so a name
  # line normalises down to exactly a binomial (optionally with a generation
  # qualifier). Anything longer is prose — "The phenotype of this gall varies"
  # would otherwise parse as a genus and epithet.
  defp binomial(segment) do
    case String.split(segment, ~r/\s+/, trim: true) do
      [genus, epithet] -> validate_binomial(genus, epithet)
      [genus, epithet, qualifier] -> qualified_binomial(genus, epithet, qualifier)
      _ -> nil
    end
  end

  defp qualified_binomial(genus, epithet, qualifier) do
    if String.trim(qualifier, ".") in @qualifiers do
      validate_binomial(genus, epithet)
    end
  end

  defp validate_binomial(genus, epithet) do
    genus = strip_trailing_punctuation(genus)
    epithet = strip_trailing_punctuation(epithet)

    if Regex.match?(@genus_word, genus) and Regex.match?(@epithet_word, epithet) do
      "#{genus} #{epithet}"
    end
  end

  defp strip_trailing_punctuation(word), do: String.replace(word, ~r/[^\p{L}-]+$/u, "")

  defp surname(person) do
    person |> String.trim() |> String.split(~r/\s+/, trim: true) |> List.last()
  end

  defp format_author_list([]), do: nil
  defp format_author_list([one]), do: one
  defp format_author_list([first, second]), do: "#{first} & #{second}"
  defp format_author_list([first | _rest]), do: "#{first} et al."
end
