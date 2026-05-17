defmodule Gallformers.Phenology do
  @moduledoc """
  The Phenology context.

  Provides functions for working with phenological observations of galls and
  the iNaturalist blacklist that suppresses rejected imports.

  See `research/phenology-data-layer-proposal.md` for the design rationale,
  including the raw vs processed field split and the implicit-correction-rule
  encoding.

  This module ships the schema + minimal CRUD as PR #1. The import pipeline
  (literature CSV, automated iNat fetch, admin review UI) lives in subsequent
  PRs from the proposal sequence.
  """
  use Boundary,
    deps: [
      Gallformers.Repo,
      Gallformers.ChangesetHelpers,
      Gallformers.SchemaFields,
      Gallformers.Species
    ],
    exports: :all

  import Ecto.Query

  alias Gallformers.Phenology.Blacklist
  alias Gallformers.Phenology.Observation
  alias Gallformers.Repo

  # ----------------------------------------------------------------------
  # Observations
  # ----------------------------------------------------------------------

  @doc """
  Returns observations for a single gall species, ordered by date.
  """
  @spec list_observations_for_species(integer()) :: [Observation.t()]
  def list_observations_for_species(species_id) do
    from(o in Observation,
      where: o.species_id == ^species_id,
      order_by: [asc: o.date]
    )
    |> Repo.all()
  end

  @doc """
  Returns the count of observations for a gall species.
  """
  @spec count_observations_for_species(integer()) :: non_neg_integer()
  def count_observations_for_species(species_id) do
    from(o in Observation,
      where: o.species_id == ^species_id,
      select: count(o.id)
    )
    |> Repo.one()
  end

  @doc """
  Returns observations whose raw and processed phenophase disagree — i.e. an
  admin correction is in effect, or upstream data drifted and the correction
  needs re-review.
  """
  @spec list_observations_needing_review() :: [Observation.t()]
  def list_observations_needing_review do
    from(o in Observation,
      where: fragment("? IS DISTINCT FROM ?", o.phenophase, o.raw_phenophase),
      order_by: [desc: o.updated_at]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single observation. Raises if not found.
  """
  @spec get_observation!(integer()) :: Observation.t()
  def get_observation!(id), do: Repo.get!(Observation, id)

  @doc """
  Creates an observation. For a fresh import (literature or iNat), raw and
  processed fields are typically set identically.
  """
  @spec create_observation(map()) :: {:ok, Observation.t()} | {:error, Ecto.Changeset.t()}
  def create_observation(attrs) do
    %Observation{}
    |> Observation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an observation. Typically used by the admin review UI to set
  processed fields (phenophase, etc.) without touching the raw_* columns.
  """
  @spec update_observation(Observation.t(), map()) ::
          {:ok, Observation.t()} | {:error, Ecto.Changeset.t()}
  def update_observation(%Observation{} = observation, attrs) do
    observation
    |> Observation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an observation.
  """
  @spec delete_observation(Observation.t()) ::
          {:ok, Observation.t()} | {:error, Ecto.Changeset.t()}
  def delete_observation(%Observation{} = observation), do: Repo.delete(observation)

  @doc """
  Returns a blank changeset for forms.
  """
  @spec change_observation(Observation.t(), map()) :: Ecto.Changeset.t()
  def change_observation(%Observation{} = observation, attrs \\ %{}),
    do: Observation.changeset(observation, attrs)

  # ----------------------------------------------------------------------
  # Blacklist
  # ----------------------------------------------------------------------

  @doc """
  Returns true if the given iNaturalist observation ID has been blacklisted.
  Used by the automated fetcher to skip rejected observations.
  """
  @spec blacklisted?(integer()) :: boolean()
  def blacklisted?(inat_id) when is_integer(inat_id) do
    Repo.exists?(from b in Blacklist, where: b.inat_id == ^inat_id)
  end

  @doc """
  Adds an iNat observation to the blacklist so it won't be re-imported.
  """
  @spec blacklist(map()) :: {:ok, Blacklist.t()} | {:error, Ecto.Changeset.t()}
  def blacklist(attrs) do
    %Blacklist{}
    |> Blacklist.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns all blacklist entries.
  """
  @spec list_blacklist() :: [Blacklist.t()]
  def list_blacklist do
    from(b in Blacklist, order_by: [desc: b.inserted_at])
    |> Repo.all()
  end

  @doc """
  Removes a blacklist entry (e.g. an admin decided to re-allow an observation).
  """
  @spec unblacklist(Blacklist.t()) ::
          {:ok, Blacklist.t()} | {:error, Ecto.Changeset.t()}
  def unblacklist(%Blacklist{} = blacklist), do: Repo.delete(blacklist)
end
