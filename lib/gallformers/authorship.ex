defmodule Gallformers.Authorship do
  @moduledoc """
  Taxonomic authorship for species names and their scientific synonyms.

  The domain rule this context exists to encode: author and year attach to a
  name's *original description*, never to a later usage of that name. A source
  that merely uses a combination contributes nothing to its authorship.

  Nothing about authorship is stored on a name. What is stored is which names
  a source entry names, and in what capacity — see
  `Gallformers.Authorship.NameMention`. An authorship string is assembled from
  those records on read:

      Cynips ignota established by source 20 (HF Bassett, 1881)
      current name Druon ignotum, a different genus
      -> "(Bassett, 1881)"

  `Gallformers.Authorship.Classifier` holds the pure logic and is also the
  detector used to prefill the admin form and drive the one-time backfill.
  Once the mentions are recorded, nothing at read time parses prose.
  """

  use Boundary,
    deps: [
      Gallformers.ChangesetHelpers,
      Gallformers.Repo,
      Gallformers.SchemaFields,
      Gallformers.Sources,
      Gallformers.Species,
      Gallformers.TaxonName
    ],
    exports: :all

  import Ecto.Query

  alias Gallformers.Authorship.Classifier
  alias Gallformers.Authorship.NameMention
  alias Gallformers.Repo

  @typedoc """
  A mention joined to the publication that carries it. `source_author` and
  `source_pubyear` supply the attribution for `establishes` rows, where
  duplicating them onto the mention would let them drift.
  """
  @type resolved_mention :: %{
          name: String.t(),
          role: String.t(),
          author: String.t() | nil,
          year: integer() | nil,
          parenthesised: boolean(),
          species_source_id: integer(),
          source_id: integer(),
          source_title: String.t() | nil,
          source_author: String.t() | nil,
          source_pubyear: String.t() | nil
        }

  @doc """
  Every name mention recorded against a species' source entries.
  """
  @spec mentions_for_species(integer()) :: [resolved_mention()]
  def mentions_for_species(species_id) do
    from(m in NameMention,
      join: ss in assoc(m, :species_source),
      join: so in assoc(ss, :source),
      where: ss.species_id == ^species_id,
      select: %{
        name: m.name,
        role: m.role,
        author: m.author,
        year: m.year,
        parenthesised: m.parenthesised,
        species_source_id: ss.id,
        source_id: so.id,
        source_title: so.title,
        source_author: so.author,
        source_pubyear: so.pubyear
      }
    )
    |> Repo.all()
  end

  @doc """
  Mentions recorded against one source entry, for the admin form.
  """
  @spec mentions_for_entry(integer()) :: [NameMention.t()]
  def mentions_for_entry(species_source_id) do
    NameMention
    |> where(species_source_id: ^species_source_id)
    |> order_by(:name)
    |> Repo.all()
  end

  @doc """
  Resolves one name's authorship from a species' mentions.

  Only mentions naming something homotypic with `name` are relevant: a
  heterotypic mention belongs to a different basionym, which is exactly how a
  junior synonym keeps the author and year it was published under.

  An `establishes` mention wins over a `cites_original` one — the entry that
  *is* the description beats an entry reporting it second-hand. Among equals,
  the earliest year takes priority.

  Returns `nil` when nothing on record says anything about this name.
  """
  @spec authorship(String.t(), [resolved_mention()]) :: map() | nil
  def authorship(name, mentions) do
    mentions
    |> Enum.filter(&relevant?(&1, name))
    |> Enum.map(&attribute/1)
    |> Enum.reject(&is_nil(&1.year))
    |> best(name)
    |> case do
      nil -> nil
      winner -> render(name, winner)
    end
  end

  @doc """
  Authorship for many names at once, sharing one query.

  Used by the gall edit page, which needs the accepted name and every
  scientific synonym.
  """
  @spec authorships(integer(), [String.t()]) :: %{String.t() => map()}
  def authorships(species_id, names) do
    mentions = mentions_for_species(species_id)

    names
    |> Enum.map(&{&1, authorship(&1, mentions)})
    |> Enum.reject(fn {_name, result} -> is_nil(result) end)
    |> Map.new()
  end

  @doc """
  Authorship for one species, loading its mentions in the process.

  Convenience for callers that need a single name; prefer `authorships/2`
  when resolving a species together with its synonyms.
  """
  @spec authorship_for_species(integer(), String.t()) :: map() | nil
  def authorship_for_species(species_id, name) do
    authorship(name, mentions_for_species(species_id))
  end

  @doc """
  The name an entry looks like it establishes, for prefilling the admin form.

  Returns `nil` unless the entry announces an original description and its
  opening line yields a clean binomial. Only ever a suggestion — it is shown
  as a placeholder, never saved on the reader's behalf.
  """
  @spec suggested_establishing_name(String.t() | nil) :: String.t() | nil
  def suggested_establishing_name(description) do
    if Classifier.original_description?(description) do
      Classifier.leading_name(description)
    end
  end

  @doc """
  Records or updates a name mention. Re-running the backfill updates in place
  rather than accumulating duplicates.
  """
  @spec upsert_mention(map()) :: {:ok, NameMention.t()} | {:error, Ecto.Changeset.t()}
  def upsert_mention(%{species_source_id: entry_id, name: name} = attrs) do
    case Repo.get_by(NameMention, species_source_id: entry_id, name: name) do
      nil -> %NameMention{}
      existing -> existing
    end
    |> NameMention.changeset(attrs)
    |> Repo.insert_or_update()
  end

  @doc """
  Removes a name mention.
  """
  @spec delete_mention(NameMention.t()) :: {:ok, NameMention.t()} | {:error, Ecto.Changeset.t()}
  def delete_mention(%NameMention{} = mention), do: Repo.delete(mention)

  # -- internals ------------------------------------------------------------

  defp relevant?(%{role: "uses"}, _name), do: false

  defp relevant?(%{name: mention_name}, name),
    do: Classifier.classify(name, mention_name) == :homotypic

  # An `establishes` row takes its attribution from the publication it sits
  # on; a `cites_original` row carries its own, because the publication it
  # names is usually not a source record.
  defp attribute(%{role: "establishes"} = mention) do
    %{
      name: mention.name,
      author: Classifier.authors(mention.source_author),
      year: parse_year(mention.source_pubyear),
      parenthesised: mention.parenthesised,
      role: "establishes",
      source_id: mention.source_id,
      source_title: mention.source_title,
      species_source_id: mention.species_source_id
    }
  end

  defp attribute(mention) do
    %{
      name: mention.name,
      author: mention.author,
      year: mention.year,
      parenthesised: mention.parenthesised,
      role: mention.role,
      source_id: mention.source_id,
      source_title: mention.source_title,
      species_source_id: mention.species_source_id
    }
  end

  defp best([], _name), do: nil

  # Precedence, in order:
  #
  # 1. Earliest year. Priority is the actual nomenclatural rule and outranks
  #    everything else — Philonix fulvicollis is Fitch, 1859 no matter which
  #    later work restates it. This is also what corrects Neuroterus
  #    umbilicatus, cited elsewhere as 1990 for a name published in 1900.
  # 2. `establishes` over `cites_original`. The recorded fact that an entry
  #    *is* a description is trusted over a second-hand report of one. Where
  #    that record names the wrong combination the fix is to correct it, not
  #    to out-guess it here.
  # 3. An unparenthesised citation over a parenthesised one — the former is an
  #    original combination, the latter explicitly a later one.
  #
  # Deliberately absent: any preference for a mention in a different genus.
  # That reads well for the accepted name and backwards for the basionym
  # itself, where it picks a later combination over the original and
  # parenthesises a name that should stand bare.
  defp best(candidates, _name) do
    Enum.min_by(candidates, fn candidate ->
      {
        candidate.year,
        if(candidate.role == "establishes", do: 0, else: 1),
        if(candidate.parenthesised, do: 1, else: 0)
      }
    end)
  end

  defp render(name, winner) do
    parenthesised? =
      winner.parenthesised or Classifier.parenthesised?(name, winner.name)

    %{
      authorship:
        Classifier.format_authorship(winner.author, to_string(winner.year), parenthesised?),
      basionym: winner.name,
      role: winner.role,
      source_id: winner.source_id,
      source_title: winner.source_title,
      species_source_id: winner.species_source_id
    }
  end

  defp parse_year(pubyear) do
    case Classifier.year(pubyear) do
      nil -> nil
      parsed -> String.to_integer(parsed)
    end
  end
end
