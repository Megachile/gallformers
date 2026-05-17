defmodule Gallformers.Repo.Migrations.AddPhenologyTables do
  @moduledoc """
  Adds `phenology_observations` and `phenology_blacklist` tables for the native
  phenology data layer (see research/phenology-data-layer-proposal.md, PR #521).

  Design notes:

    * Raw vs processed split — raw_* columns are overwritten from upstream sources
      on each re-import; the unsuffixed columns are admin-curated and preserved.
      A disagreement between the two encodes an implicit correction rule.

    * `lifestage` records the inducer's developmental stage at the time of
      observation (egg / larva / pupa / adult / oviscar) — distinct from
      `phenophase`, which describes the gall structure itself (developing /
      maturing / dormant). Both are required to answer "when does species X
      reach lifestage Y at latitude L?", the core phenology question.

    * Derivable degree-day fields (AGDD32/AGDD50/yearend32/yearend50/percent32/
      percent50) from the legacy phen DB are intentionally NOT migrated as
      columns — they can be recomputed from date+coordinates if needed.

    * `viability` from the legacy phen DB is dropped (effectively always empty).
  """
  use Ecto.Migration

  def up do
    # ----------------------------------------------------------------------
    # phenology_observations
    # ----------------------------------------------------------------------
    create table(:phenology_observations) do
      add :species_id, references(:species, on_delete: :delete_all), null: false
      add :host_species_id, references(:species, on_delete: :nilify_all)

      add :source_type, :string, null: false
      add :inat_id, :integer

      # Raw fields — overwritten from upstream source on each re-import.
      add :raw_phenophase, :string
      add :raw_date, :date
      add :raw_latitude, :float
      add :raw_longitude, :float

      # Processed fields — admin-curated, preserved across re-imports.
      add :phenophase, :string
      add :date, :date, null: false
      add :doy, :integer, null: false
      add :latitude, :float, null: false
      add :longitude, :float, null: false
      add :site, :string
      add :state, :string
      add :country, :string

      # Developmental stage of the inducer at observation time (egg / larva /
      # pupa / adult / oviscar). Distinct from phenophase, which describes the
      # gall structure.
      add :lifestage, :string

      # Computed phenology values (function of date + coordinates).
      add :seasind, :float
      add :acchours, :float

      # Provenance.
      add :source_url, :text
      add :page_url, :text

      timestamps(type: :utc_datetime)
    end

    create index(:phenology_observations, [:species_id],
             name: :idx_phenology_observations_species_id
           )

    create index(:phenology_observations, [:species_id, :date],
             name: :idx_phenology_observations_species_date
           )

    create index(:phenology_observations, [:host_species_id],
             name: :idx_phenology_observations_host_species_id
           )

    create index(:phenology_observations, [:source_type],
             name: :idx_phenology_observations_source_type
           )

    # Unique on inat_id where present (literature obs have inat_id IS NULL).
    execute """
    CREATE UNIQUE INDEX idx_phenology_observations_inat_id_unique
    ON phenology_observations (inat_id)
    WHERE inat_id IS NOT NULL
    """

    # Partial index for the admin review queue: observations whose raw and
    # processed phenophase disagree (i.e. an admin correction is in effect, OR
    # the upstream value drifted and the correction needs re-review).
    execute """
    CREATE INDEX idx_phenology_observations_phenophase_corrected
    ON phenology_observations (species_id)
    WHERE phenophase IS DISTINCT FROM raw_phenophase
    """

    execute """
    ALTER TABLE phenology_observations
    ADD CONSTRAINT phenology_observations_source_type_check
    CHECK (source_type IN ('literature', 'inat'))
    """

    # inat_id required iff source_type='inat'; forbidden otherwise.
    execute """
    ALTER TABLE phenology_observations
    ADD CONSTRAINT phenology_observations_inat_id_matches_source_type
    CHECK (
      (source_type = 'inat' AND inat_id IS NOT NULL)
      OR
      (source_type = 'literature' AND inat_id IS NULL)
    )
    """

    execute """
    ALTER TABLE phenology_observations
    ADD CONSTRAINT phenology_observations_doy_check
    CHECK (doy BETWEEN 1 AND 366)
    """

    execute """
    ALTER TABLE phenology_observations
    ADD CONSTRAINT phenology_observations_latitude_check
    CHECK (latitude BETWEEN -90.0 AND 90.0)
    """

    execute """
    ALTER TABLE phenology_observations
    ADD CONSTRAINT phenology_observations_longitude_check
    CHECK (longitude BETWEEN -180.0 AND 180.0)
    """

    # ----------------------------------------------------------------------
    # phenology_blacklist
    # ----------------------------------------------------------------------
    create table(:phenology_blacklist) do
      add :inat_id, :integer, null: false
      add :species_id, references(:species, on_delete: :delete_all)
      add :reason, :text

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:phenology_blacklist, [:inat_id],
             name: :idx_phenology_blacklist_inat_id_unique
           )

    create index(:phenology_blacklist, [:species_id], name: :idx_phenology_blacklist_species_id)
  end

  def down do
    drop table(:phenology_blacklist)
    drop table(:phenology_observations)
  end
end
