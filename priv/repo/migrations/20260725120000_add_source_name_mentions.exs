defmodule Gallformers.Repo.Migrations.AddSourceNameMentions do
  @moduledoc """
  Records the taxonomic names a source entry names, and in what capacity.

  Authorship attaches to a name's original description, never to a later use
  of it. Until now that fact was recoverable only by running regexes over
  `species_source.description` at read time, which made the meaning of the
  data depend on a parser. This table stores it.

  Three roles, matching what the prose actually says:

    * `establishes` — this entry *is* the original description of the name.
      Author and year come from the entry's own source record, so they are
      left null here rather than duplicated.
    * `cites_original` — this entry cites the name's original description,
      published elsewhere ("Aceria blastofagi Keifer, 1966b: 15."). The
      publication is often not a source record, so author and year are stored.
    * `uses` — the entry uses the name without attributing it
      ("Aceria blastofagi; Amrine & Stasny, 1994: 27."). Carries no
      authorship, but still evidences that the combination existed.
  """
  use Ecto.Migration

  def change do
    create table(:source_name_mention) do
      add :species_source_id, references(:species_source, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :role, :string, null: false
      add :author, :string
      add :year, :integer

      # Whether the citation printed its authorship in parentheses. This is
      # not derivable after the fact: "Phylloteras poculum (Osten Sacken,
      # 1862)" is parenthesised because the name has moved genus, but the
      # original genus never appears in the line, so comparing it against the
      # current name would compare it to itself and drop the parentheses.
      add :parenthesised, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create index(:source_name_mention, [:species_source_id])
    create index(:source_name_mention, [:name])
    create index(:source_name_mention, [:role])

    # One statement per name per entry; re-running the backfill updates rather
    # than accumulating duplicates.
    create unique_index(:source_name_mention, [:species_source_id, :name])

    create constraint(:source_name_mention, :source_name_mention_role_check,
             check: "role IN ('establishes', 'cites_original', 'uses')"
           )

    create constraint(:source_name_mention, :source_name_mention_year_check,
             check: "year IS NULL OR (year >= 1758 AND year <= 2200)"
           )
  end
end
