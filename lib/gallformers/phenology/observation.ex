defmodule Gallformers.Phenology.Observation do
  @moduledoc """
  Ecto schema for the phenology_observations table.

  Each row is one phenological observation of a gall at a specific place and
  time. See `Gallformers.Phenology` for context-level operations and
  `research/phenology-data-layer-proposal.md` for the design rationale around
  the raw vs processed field split.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Gallformers.ChangesetHelpers, only: [trim_strings: 1]

  alias Gallformers.Species.Species

  @behaviour Gallformers.SchemaFields

  @source_types ~w(literature inat)

  @required_fields [:species_id, :source_type, :date, :doy, :latitude, :longitude]

  @optional_fields [
    :host_species_id,
    :inat_id,
    :raw_phenophase,
    :raw_date,
    :raw_latitude,
    :raw_longitude,
    :phenophase,
    :site,
    :state,
    :country,
    :lifestage,
    :seasind,
    :acchours,
    :source_url,
    :page_url
  ]

  @type t :: %__MODULE__{
          id: integer() | nil,
          species_id: integer() | nil,
          host_species_id: integer() | nil,
          source_type: String.t() | nil,
          inat_id: integer() | nil,
          raw_phenophase: String.t() | nil,
          raw_date: Date.t() | nil,
          raw_latitude: float() | nil,
          raw_longitude: float() | nil,
          phenophase: String.t() | nil,
          date: Date.t() | nil,
          doy: integer() | nil,
          latitude: float() | nil,
          longitude: float() | nil,
          site: String.t() | nil,
          state: String.t() | nil,
          country: String.t() | nil,
          lifestage: String.t() | nil,
          seasind: float() | nil,
          acchours: float() | nil,
          source_url: String.t() | nil,
          page_url: String.t() | nil
        }

  schema "phenology_observations" do
    field :source_type, :string
    field :inat_id, :integer

    field :raw_phenophase, :string
    field :raw_date, :date
    field :raw_latitude, :float
    field :raw_longitude, :float

    field :phenophase, :string
    field :date, :date
    field :doy, :integer
    field :latitude, :float
    field :longitude, :float
    field :site, :string
    field :state, :string
    field :country, :string
    field :lifestage, :string

    field :seasind, :float
    field :acchours, :float

    field :source_url, :string
    field :page_url, :string

    belongs_to :species, Species
    belongs_to :host_species, Species, foreign_key: :host_species_id

    timestamps(type: :utc_datetime)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  Returns the list of valid source_type values.
  """
  @spec source_types() :: [String.t()]
  def source_types, do: @source_types

  @doc """
  Creates a changeset for a phenology observation.

  Validates: required fields, source_type vocabulary, DOY/lat/lon ranges, and
  the cross-field rule that `inat_id` is required iff `source_type` is `"inat"`.
  """
  def changeset(observation, attrs) do
    observation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> trim_strings()
    |> validate_required(@required_fields)
    |> validate_inclusion(:source_type, @source_types)
    |> validate_number(:doy, greater_than_or_equal_to: 1, less_than_or_equal_to: 366)
    |> validate_number(:latitude, greater_than_or_equal_to: -90, less_than_or_equal_to: 90)
    |> validate_number(:longitude, greater_than_or_equal_to: -180, less_than_or_equal_to: 180)
    |> validate_inat_id_matches_source_type()
    |> foreign_key_constraint(:species_id)
    |> foreign_key_constraint(:host_species_id)
    |> unique_constraint(:inat_id, name: :idx_phenology_observations_inat_id_unique)
  end

  defp validate_inat_id_matches_source_type(changeset) do
    source_type = get_field(changeset, :source_type)
    inat_id = get_field(changeset, :inat_id)

    case {source_type, inat_id} do
      {"inat", nil} ->
        add_error(changeset, :inat_id, "is required when source_type is \"inat\"")

      {"literature", id} when not is_nil(id) ->
        add_error(changeset, :inat_id, "must be nil when source_type is \"literature\"")

      _ ->
        changeset
    end
  end
end
