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

  alias Gallformers.Authorship.Citation
  alias Gallformers.TaxonName

  # Latin gender endings, longest first so "orum" is preferred over "um".
  @gender_ending ~r/(orum|arum|ae|us|um|is|a|e|i|o)$/
  @min_stem_length 4

  # Transcriptions vary: "n. sp.", "n.sp", "sp. nov", "new species". The
  # trailing period is not reliable — Bassett's 1890 entry reads
  # "Rhodites tumidus n.sp" and was being missed for want of it.
  @origin_marker ~r/\bn\.\s?sp\b\.?|\bsp\.\s?nov\b\.?|\bnew species\b/i
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
    # The act is often set off by a comma ("Cynips ignota, n. sp.") but not
    # always ("Rhodites tumidus n.sp"), where it would otherwise read as a
    # third word and disqualify the name.
    |> String.replace(@origin_marker, " ")
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

  Two independent lines of evidence, preferred in this order:

    1. A **citation line** in some source's body text stating this name's
       authorship outright. Explicit beats inferred, and it survives being
       reproduced in a catalogue or a modern revision.
    2. An attached source that **announces an original description** (`n. sp.`)
       of this name, whose own author and year then supply the authorship.

  Confidence is:

    * `:high` — either line of evidence resolved
    * `:review` — several sources announce an original description, so a human
      picks
    * `:none` — nothing to go on

  There is deliberately no tier that falls back to the metadata of whatever
  source happens to be oldest. That was tried, and it mostly returned the
  authorship of a later revision or a catalogue: `Aceria neoessigi` came out
  as `Amrine, 2019` when the body text of that very entry reads
  `Keifer, 1940`.

  A source announcing an original description of some *other* name — a junior
  synonym described from this species, say — is not a basionym candidate. Its
  author and year belong to that synonym.
  """
  @spec derive(String.t(), [source()]) :: map()
  def derive(species_name, sources) do
    cited = authorship_from_citations(species_name, citations(sources))
    marked = marked_source_result(species_name, sources)

    reconcile(species_name, cited, marked)
  end

  defp marked_source_result(species_name, sources) do
    scored = Enum.map(sources, &score(species_name, &1))

    case Enum.filter(scored, &basionym_candidate?/1) do
      [only] -> build(species_name, only, :high, :single_original_description)
      [] -> nil
      several -> ambiguous(species_name, several)
    end
  end

  # Two independent readings of the same record. Agreement is the strongest
  # evidence available here; disagreement is a question for a person, not
  # something to settle by preferring one method. In the dev data they part
  # company over transcribed years (Bassett 1990 for 1900), misspelled genera
  # (Bassetia for Bassettia, which fakes a genus change), and transliterated
  # umlauts (Beutenmüller / Beutenmueller / Beutenmuller).
  defp reconcile(_species_name, nil, nil), do: none()
  defp reconcile(_species_name, nil, marked), do: marked
  defp reconcile(_species_name, cited, nil), do: cited

  defp reconcile(species_name, cited, marked) do
    if same_authorship?(cited.authorship, marked.authorship) do
      %{
        cited
        | authorship: preferred_spelling(cited.authorship, marked.authorship),
          reason: :corroborated
      }
      |> adopt_named_basionym(species_name, marked)
    else
      %{cited | confidence: :review, reason: :evidence_disagrees, alternative: marked.authorship}
    end
  end

  # Two readings can agree on the authorship and still differ on which name
  # carries it. A basionym in another genus is the informative one — it names
  # the original combination — where a basionym equal to the current name says
  # only that an authorship exists. Antistrophus chrysothamni is cited under
  # its current name but described as Aulax chrysothamni, and keeping the
  # latter is what lets the attribution be attached to a synonym on record.
  defp adopt_named_basionym(result, species_name, marked) do
    if names_original_genus?(marked.basionym, species_name) and
         not names_original_genus?(result.basionym, species_name) do
      %{result | basionym: marked.basionym, source_id: marked.source_id}
    else
      result
    end
  end

  defp names_original_genus?(nil, _species_name), do: false
  defp names_original_genus?(basionym, species_name), do: parenthesised?(species_name, basionym)

  defp same_authorship?(left, right), do: authorship_key(left) == authorship_key(right)

  @doc """
  Folds an authorship string down to a comparison key, so that
  `Beutenmüller`, `Beutenmueller` and `Beutenmuller` are recognised as one
  author rather than three disagreements.

  Only ever used for comparison — it is far too lossy to store or display.
  Folding the German digraphs will also collapse unrelated spellings
  (`Queiroz` and `Qiroz`), which is acceptable when the two strings are
  already two readings of the same record.
  """
  @spec authorship_key(String.t() | nil) :: String.t() | nil
  def authorship_key(nil), do: nil

  def authorship_key(authorship) when is_binary(authorship) do
    authorship
    |> String.downcase()
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\x{0300}-\x{036F}]/u, "")
    |> String.replace(~r/ue/u, "u")
    |> String.replace(~r/oe/u, "o")
    |> String.replace(~r/ae/u, "a")
  end

  # Same author, two spellings. Keep the one that needs no diacritics: it is
  # the safer thing to commit a database to, and it stays typeable.
  defp preferred_spelling(left, right) do
    if ascii?(left) or not ascii?(right), do: left, else: right
  end

  defp ascii?(nil), do: true
  defp ascii?(string), do: String.valid?(string) and byte_size(string) == String.length(string)

  @doc """
  Collects every authorship-bearing citation line across a set of sources.
  """
  @spec citations([source()]) :: [Citation.t()]
  def citations(sources) do
    Enum.flat_map(sources, fn source ->
      source
      |> Map.get(:description)
      |> Citation.parse(citing_year(source))
      |> Enum.map(&%{&1 | source_id: Map.get(source, :id)})
    end)
  end

  @doc """
  Resolves one name's authorship from a pool of citation lines.

  Only lines naming something homotypic with `name` are relevant — a
  heterotypic line belongs to a different basionym, which is precisely how a
  junior synonym keeps its own author and year. Returns `nil` when the pool
  says nothing about this name.
  """
  @spec authorship_from_citations(String.t(), [Citation.t()]) :: map() | nil
  def authorship_from_citations(name, citations) do
    citations
    |> Enum.filter(&(classify(name, &1.name) == :homotypic))
    |> Citation.basionym()
    |> case do
      nil ->
        nil

      basionym ->
        %{
          authorship:
            format_authorship(
              basionym.author,
              to_string(basionym.year),
              already_parenthesised?(basionym) or parenthesised?(name, basionym.name)
            ),
          confidence: :high,
          reason: :cited_original_description,
          basionym: basionym.name,
          source_id: basionym.source_id,
          alternative: nil
        }
    end
  end

  @doc """
  Authorship for each scientific synonym, read from the same citation pool.

  A homotypic synonym resolves to the species' own basionym; a heterotypic one
  resolves to its own, which is the whole point — the junior name keeps the
  author and year it was published under. Names the citations say nothing
  about are omitted.
  """
  @spec alias_authorships([String.t()], [Citation.t()]) :: %{String.t() => String.t()}
  def alias_authorships(alias_names, citations) do
    alias_names
    |> Enum.map(fn name -> {name, authorship_from_citations(name, citations)} end)
    |> Enum.reject(fn {_name, result} -> is_nil(result) or is_nil(result.authorship) end)
    |> Map.new(fn {name, result} -> {name, result.authorship} end)
  end

  # A `:parenthesised` citation has already made the call: the source wrote
  # `Phylloteras poculum (Osten Sacken, 1862)` precisely because the name has
  # moved genus since. Recomputing that by comparing the citation's genus to
  # the current one would compare the name to itself and wrongly drop the
  # parentheses — the original genus is not in the line at all.
  defp already_parenthesised?(%Citation{shape: :parenthesised}), do: true
  defp already_parenthesised?(%Citation{}), do: false

  defp citing_year(source) do
    case year(Map.get(source, :pubyear)) do
      nil -> nil
      parsed -> String.to_integer(parsed)
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
    pooled_sources = Enum.flat_map(rows, & &1.sources)

    cited = authorship_from_citations(valid_name, citations(pooled_sources))
    marked = pooled_marked_result(valid_name, pooled_sources)

    share(rows, reconcile(valid_name, cited, marked))
  end

  defp pooled_marked_result(valid_name, pooled_sources) do
    pooled_sources
    |> Enum.map(&score(valid_name, &1))
    |> Enum.filter(&basionym_candidate?/1)
    |> case do
      [] -> nil
      candidates -> senior(valid_name, candidates)
    end
  end

  defp basionym_candidate?(scored) do
    scored.original_description? and scored.own_name? and not is_nil(scored.year)
  end

  # Priority: the earliest available name wins, and applies to both generations.
  defp senior(valid_name, candidates) do
    senior = Enum.min_by(candidates, & &1.year)

    build(valid_name, senior, :high, :earliest_original_description)
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
      source_id: scored.source_id,
      alternative: nil
    }
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
      source_id: nil,
      alternative: nil
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
