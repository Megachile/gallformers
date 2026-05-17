defmodule Gallformers.Repo.Migrations.AddViabilityToPhenologyObservations do
  @moduledoc """
  Adds a `viability` column to phenology_observations.

  The previous migration (20260517170909) intentionally omitted this column
  on the assumption that the legacy phen DB's `viability` was effectively
  always empty. That was wrong: ~3,250 observations carry meaningful values
  (`viable`, `pending`, `too early`, `inquiline/parasitoid only`, `failed`,
  `too late`). These distinguish galls that completed their lifecycle from
  ones colonized by parasitoids or aborted early — a key phenology signal
  separate from `phenophase` (gall structure state) and `lifestage`
  (inducer developmental stage).
  """
  use Ecto.Migration

  def change do
    alter table(:phenology_observations) do
      add :viability, :string
    end
  end
end
