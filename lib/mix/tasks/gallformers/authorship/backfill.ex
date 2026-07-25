defmodule Mix.Tasks.Gallformers.Authorship.Backfill do
  @shortdoc "Records name mentions found in existing source entries"

  @moduledoc """
  Walks every species-source entry and records the taxonomic names it names,
  so authorship stops depending on a parser at read time.

  This is a one-time migration of information that is already in the entries,
  not an ongoing job. It is idempotent — re-running updates in place — so it
  is safe to run repeatedly while tuning.

  Only high-precision detections are written:

    * `establishes` where the entry announces an original description and its
      opening line yields a clean binomial
    * `cites_original` for citation lines carrying an author and a year

  Usage lines are skipped. They matter for populating synonyms, but that is
  reviewed work rather than something to write unattended.

  ## Usage

      mix gallformers.authorship.backfill --dry-run
      mix gallformers.authorship.backfill
      mix gallformers.authorship.backfill --limit 200

  ## Options

    * `--dry-run` — report what would be written, change nothing
    * `--limit N` — only consider the first N entries, for a quick look
  """
  use Boundary, check: [in: false, out: false]
  use Mix.Task

  import Ecto.Query

  alias Gallformers.Authorship
  alias Gallformers.Authorship.Classifier
  alias Gallformers.Repo
  alias Gallformers.Species.SpeciesSource

  @impl Mix.Task
  def run(args) do
    {opts, _rest, _invalid} =
      OptionParser.parse(args, strict: [dry_run: :boolean, limit: :integer])

    Mix.Task.run("app.start")

    dry_run? = Keyword.get(opts, :dry_run, false)

    entries = load_entries(Keyword.get(opts, :limit))

    Mix.shell().info("Scanning #{length(entries)} source entries…")

    tally =
      entries
      |> Enum.flat_map(&detect/1)
      |> Enum.reduce(%{establishes: 0, cites_original: 0, failed: 0}, fn mention, acc ->
        record(mention, dry_run?, acc)
      end)

    report(tally, dry_run?)
  end

  defp load_entries(limit) do
    SpeciesSource
    |> join(:inner, [ss], so in assoc(ss, :source))
    |> where([ss], not is_nil(ss.description) and ss.description != "")
    |> select([ss, so], %{
      id: ss.id,
      description: ss.description,
      author: so.author,
      pubyear: so.pubyear
    })
    |> maybe_limit(limit)
    |> Repo.all()
  end

  defp maybe_limit(query, nil), do: query
  defp maybe_limit(query, limit), do: limit(query, ^limit)

  defp detect(entry) do
    entry
    |> Classifier.mentions()
    |> Enum.map(&Map.put(&1, :species_source_id, entry.id))
  end

  defp record(mention, true = _dry_run, tally) do
    Map.update!(tally, String.to_existing_atom(mention.role), &(&1 + 1))
  end

  defp record(mention, false = _dry_run, tally) do
    case Authorship.upsert_mention(mention) do
      {:ok, _saved} ->
        Map.update!(tally, String.to_existing_atom(mention.role), &(&1 + 1))

      {:error, changeset} ->
        Mix.shell().error("  skipped #{mention.name}: #{inspect(changeset.errors)}")
        Map.update!(tally, :failed, &(&1 + 1))
    end
  end

  defp report(tally, dry_run?) do
    verb = if dry_run?, do: "would record", else: "recorded"

    Mix.shell().info("""

    #{verb}:
      establishes     #{tally.establishes}
      cites_original  #{tally.cites_original}
      failed          #{tally.failed}
    """)

    if dry_run?, do: Mix.shell().info("Dry run — nothing written.")
  end
end
