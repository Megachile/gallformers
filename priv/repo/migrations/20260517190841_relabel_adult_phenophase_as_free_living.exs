defmodule Gallformers.Repo.Migrations.RelabelAdultPhenophaseAsFreeLiving do
  @moduledoc """
  Relabels `phenophase='Adult'` to `phenophase='Free-living'` in the legacy
  imported data.

  Observers entering these rows put inducer-stage info ('Adult') in the
  phenophase column, which is supposed to describe the *gall* structure's
  state, not the inducer's developmental stage. All ~472 affected rows
  already have `lifestage='Adult'`, so the original information isn't lost
  — but the misplaced value gets recast as a proper phenophase: 'Free-living'
  (adult inducer found outside the gall, i.e., post-emergence). This is a
  new entry in the documented phenophase vocabulary (see
  `Gallformers.Phenology.Observation.phenophases/0`).

  raw_phenophase is updated alongside processed phenophase so the
  partial index on phenophase IS DISTINCT FROM raw_phenophase doesn't
  surface every relabeled row as a needs-review case.

  The Python converter applies the same transformation on the way in
  (`convert_phen_to_csv.py`) so future re-imports stay consistent.
  """
  use Ecto.Migration

  def up do
    execute("""
    UPDATE phenology_observations
    SET phenophase = 'Free-living'
    WHERE phenophase = 'Adult'
    """)

    execute("""
    UPDATE phenology_observations
    SET raw_phenophase = 'Free-living'
    WHERE raw_phenophase = 'Adult'
    """)
  end

  def down do
    execute("""
    UPDATE phenology_observations
    SET phenophase = 'Adult'
    WHERE phenophase = 'Free-living'
    """)

    execute("""
    UPDATE phenology_observations
    SET raw_phenophase = 'Adult'
    WHERE raw_phenophase = 'Free-living'
    """)
  end
end
