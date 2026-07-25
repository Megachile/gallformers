defmodule Gallformers.Authorship.NameMention do
  @moduledoc """
  A taxonomic name that a source entry names, and the capacity it names it in.

  See `Gallformers.Authorship` for how these are read back into an authorship
  string. The roles are deliberately a record of what the prose says rather
  than a conclusion drawn from it — `cites_original` means the entry made that
  claim, not that we have verified the publication exists.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Gallformers.ChangesetHelpers, only: [trim_strings: 1]

  @behaviour Gallformers.SchemaFields

  @roles ~w(establishes cites_original uses)

  @required_fields [:species_source_id, :name, :role]
  @optional_fields [:author, :year, :parenthesised]

  @type role :: String.t()

  @type t :: %__MODULE__{
          id: integer() | nil,
          species_source_id: integer() | nil,
          name: String.t() | nil,
          role: role() | nil,
          author: String.t() | nil,
          year: integer() | nil,
          parenthesised: boolean()
        }

  schema "source_name_mention" do
    field :name, :string
    field :role, :string
    field :author, :string
    field :year, :integer
    field :parenthesised, :boolean, default: false

    belongs_to :species_source, Gallformers.Species.SpeciesSource

    timestamps(type: :utc_datetime)
  end

  @impl Gallformers.SchemaFields
  def required_fields, do: @required_fields

  @doc """
  The roles a mention may take.
  """
  @spec roles() :: [role()]
  def roles, do: @roles

  @doc """
  True when a mention carries authorship — that is, when it either is the
  original description or cites one.
  """
  @spec attributive?(t()) :: boolean()
  def attributive?(%__MODULE__{role: role}), do: role in ~w(establishes cites_original)

  @doc """
  Creates a changeset for a name mention.
  """
  def changeset(mention, attrs) do
    mention
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> trim_strings()
    |> validate_required(@required_fields)
    |> validate_inclusion(:role, @roles)
    |> validate_length(:name, min: 1, max: 500)
    |> validate_number(:year, greater_than_or_equal_to: 1758, less_than_or_equal_to: 2200)
    |> unique_constraint([:species_source_id, :name],
      name: :source_name_mention_species_source_id_name_index,
      message: "this entry already names that taxon"
    )
    |> foreign_key_constraint(:species_source_id)
  end
end
