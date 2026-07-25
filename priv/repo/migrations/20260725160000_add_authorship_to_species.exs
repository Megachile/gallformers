defmodule Gallformers.Repo.Migrations.AddAuthorshipToSpecies do
  @moduledoc """
  An authorship recorded directly on a species, for when the publication that
  established the name is not in the database.

  Source entries remain the preferred route — a name mention traces to a
  citable publication, and this does not. But most described galls have no
  entry that establishes their name, and refusing to record what a curator
  already knows would leave those blank indefinitely.

  Read order is mentions first, this second, so a value here is superseded the
  moment the evidence arrives rather than competing with it.

  Stored as the display string, parentheses included, because without a
  basionym there is no original genus to compare against and so no way to
  derive them. That means a later reclassification does not update it; the
  parentheses are the curator's to maintain until an entry supplies the
  basionym.
  """
  use Ecto.Migration

  def change do
    alter table(:species) do
      add :authorship, :string
    end
  end
end
