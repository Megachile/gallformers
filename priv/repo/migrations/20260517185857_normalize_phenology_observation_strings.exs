defmodule Gallformers.Repo.Migrations.NormalizePhenologyObservationStrings do
  @moduledoc """
  One-shot data cleanup for whitespace / capitalization drift inherited from
  the legacy phen DB. Applies the same normalization rules that the Python
  converter now does on the way in (`convert_phen_to_csv.py:normalize_text/
  normalize_lifestage`), so existing imported rows match what future re-imports
  would produce.

  Fixes:

    * Trims leading/trailing whitespace on phenophase, raw_phenophase,
      lifestage, site, state, country, viability — and nulls anything that
      becomes empty after trimming.
    * Canonicalizes lifestage to one of {Egg, Larva, Pupa, Adult}:
      `'larva'` and `'adult'` get title-cased; anything outside that set
      (notably `'perimature'` — a phenophase, not a lifestage — appearing
      in the lifestage column of a single row whose phenophase is already
      `'dormant'`) becomes NULL.

  Not auto-fixed here (flag for separate decision):

    * ~472 rows with `phenophase='Adult'` (Adult is a lifestage; these have
      inducer-stage info in the wrong column).
    * ~20 rows with `phenophase='senescent'` (not in the proposal vocab
      developing/maturing/dormant/perimature/oviscar).
  """
  use Ecto.Migration

  # Columns to trim. raw_* are included so the raw/processed pair stays in
  # sync after cleanup — otherwise the partial index that flags
  # "phenophase IS DISTINCT FROM raw_phenophase" would surface every
  # whitespace-only diff as a needs-review case.
  @trim_columns ~w(phenophase raw_phenophase lifestage site state country viability)

  def up do
    Enum.each(@trim_columns, fn col ->
      execute("""
      UPDATE phenology_observations
      SET #{col} = NULLIF(trim(#{col}), '')
      WHERE #{col} IS DISTINCT FROM NULLIF(trim(#{col}), '')
      """)
    end)

    # Canonicalize lifestage capitalization. Anything outside the canonical
    # set falls through to NULL (no row currently has e.g. 'unknown' that
    # we'd want to preserve).
    execute("""
    UPDATE phenology_observations
    SET lifestage = CASE
      WHEN lower(lifestage) = 'egg'   THEN 'Egg'
      WHEN lower(lifestage) = 'larva' THEN 'Larva'
      WHEN lower(lifestage) = 'pupa'  THEN 'Pupa'
      WHEN lower(lifestage) = 'adult' THEN 'Adult'
      ELSE NULL
    END
    WHERE lifestage IS NOT NULL
      AND lifestage NOT IN ('Egg', 'Larva', 'Pupa', 'Adult')
    """)
  end

  def down do
    # Irreversible data cleanup. No-op down preserves the migration record
    # so Ecto's migration tracking stays consistent if you ever rollback past
    # this point — the original whitespace/case isn't worth restoring.
    :ok
  end
end
