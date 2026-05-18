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
  alias Gallformers.Species.Species

  # ----------------------------------------------------------------------
  # Observations
  # ----------------------------------------------------------------------

  @doc """
  Returns gall species that have at least one phenology observation, with
  the observation count attached. Ordered by species name. Used by the
  phenology explorer's species selector and by per-gall data-availability
  widgets.
  """
  @spec list_species_with_counts() :: [
          %{species_id: integer(), name: String.t(), n_obs: non_neg_integer()}
        ]
  def list_species_with_counts do
    from(o in Observation,
      join: s in Species,
      on: s.id == o.species_id,
      group_by: [s.id, s.name],
      order_by: s.name,
      select: %{species_id: s.id, name: s.name, n_obs: count(o.id)}
    )
    |> Repo.all()
  end

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
  Returns observations matching the given filters, with denormalized species
  name. Used by the public `/phenology` explorer to drive its multi-species
  scatter; each returned map is shaped for direct passing to the chart hook.

  Filters (all optional):
    * `:search` — list of name fragments. Returned obs belong to species
      whose name ILIKEs at least one fragment. Empty / nil = no name filter.
    * `:generation` — `:all` (default), `:sexgen`, or `:agamic`. Matches on
      the `(sexgen)` / `(agamic)` suffix convention in `species.name`.
    * `:phenophases` — list of phenophase values to keep. Empty / nil =
      no phenophase filter (all obs returned regardless of phenophase).

  Always scoped to `species.taxoncode == "gall"` so host-plant rows can't
  leak in if they ever land in this table.
  """
  @spec search_observations(map()) :: [map()]
  def search_observations(filters \\ %{}) do
    from(o in Observation,
      join: s in Species,
      on: s.id == o.species_id,
      left_join: h in Species,
      on: h.id == o.host_species_id,
      where: s.taxoncode == "gall",
      order_by: [asc: o.date],
      select: %{
        id: o.id,
        species_id: o.species_id,
        species_name: s.name,
        host_species_id: o.host_species_id,
        host_species_name: h.name,
        date: o.date,
        doy: o.doy,
        phenophase: o.phenophase,
        lifestage: o.lifestage,
        viability: o.viability,
        latitude: o.latitude,
        longitude: o.longitude,
        source_type: o.source_type,
        source_url: o.source_url,
        page_url: o.page_url,
        site: o.site,
        state: o.state,
        country: o.country
      }
    )
    |> apply_search_filter(Map.get(filters, :search))
    |> apply_generation_filter(Map.get(filters, :generation, :all))
    |> apply_phenophase_filter(Map.get(filters, :phenophases))
    |> Repo.all()
  end

  defp apply_search_filter(query, nil), do: query
  defp apply_search_filter(query, []), do: query

  defp apply_search_filter(query, terms) when is_list(terms) do
    patterns =
      terms
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.map(&"%#{&1}%")

    case patterns do
      [] ->
        query

      _ ->
        # OR across all name patterns: search matches "any of these fragments
        # anywhere in the species name."
        dyn =
          Enum.reduce(patterns, false, fn pattern, acc ->
            dynamic([_, s], ^acc or ilike(s.name, ^pattern))
          end)

        from(q in query, where: ^dyn)
    end
  end

  defp apply_generation_filter(query, :sexgen) do
    from([_, s] in query, where: ilike(s.name, "%(sexgen)%"))
  end

  defp apply_generation_filter(query, :agamic) do
    from([_, s] in query, where: ilike(s.name, "%(agamic)%"))
  end

  defp apply_generation_filter(query, _), do: query

  # `nil` means "no filter / key not provided" — kept for non-LV callers that
  # don't pass a `:phenophases` key. `[]` means "filter to nothing" — the
  # explorer uses this to honor an all-unchecked UI state strictly. The two
  # are intentionally distinguished.
  defp apply_phenophase_filter(query, nil), do: query
  defp apply_phenophase_filter(query, []), do: from(o in query, where: false)

  defp apply_phenophase_filter(query, phenophases) when is_list(phenophases) do
    from(o in query, where: o.phenophase in ^phenophases)
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
