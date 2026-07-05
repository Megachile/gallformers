defmodule Gallformers.Galls.HostConsistency do
  @moduledoc """
  Cross-checks a gall's structured host associations (`gallhost`) against the
  host names actually written in the prose of that gall's sources
  (`species_source.description`), and surfaces the disagreements as a review
  queue for admins.

  Internal module — public API is exposed through `Gallformers.Galls`.

  Two directions of discrepancy (hard rule, both ways, with text-flagged
  exceptions — see `Gallformers.Galls.HostNameMatcher`):

    * `:undocumented_association` (Direction A) — a host is in `gallhost` but its
      current name is not written in any of the gall's source descriptions.
      Resolved by citing a source that names it, or adding a Gallformers Note.
    * `:unassociated_mention` (Direction B) — a plant is named in a source
      description but has no `gallhost` row (and is not text-flagged as a
      rejected report). *(Direction B lands in a follow-up commit.)*

  Everything is computed on demand from live data — no stored state, no
  dismissal table. Reconciliation happens by editing the structured data or the
  public GF Notes, both of which change what this check sees next load.
  """

  import Ecto.Query

  alias Gallformers.Galls.{GallHost, HostNameMatcher}
  alias Gallformers.Repo
  alias Gallformers.Species.{Species, SpeciesSource}
  alias Gallformers.Taxonomy.Tree

  # The single canonical "Gallformers ID Notes" source (matches the hardcoded id
  # used in sources.ex / gall_live.ex / host_live.ex).
  @gf_notes_source_id 58

  @default_limit 500

  @type direction :: :undocumented_association | :unassociated_mention

  @type discrepancy :: %{
          gall_id: integer(),
          gall_name: String.t(),
          host_id: integer(),
          host_name: String.t(),
          genus_placeholder: boolean(),
          direction: direction(),
          source_count: non_neg_integer(),
          has_gf_notes: boolean()
        }

  @type filter :: %{
          optional(:gall_taxon_id) => integer() | nil,
          optional(:host_taxon_id) => integer() | nil,
          optional(:has_gf_notes) => :any | :with | :without,
          optional(:limit) => pos_integer()
        }

  @doc """
  Computes host-association discrepancies for the filtered scope.

  Returns `%{items: [discrepancy], total: integer, truncated: boolean}` where
  `items` is capped at the filter's `:limit` (default #{@default_limit}) but
  `total` reflects the full count for the scope.

  Requires at least one taxon filter (`:gall_taxon_id` or `:host_taxon_id`);
  without one it returns an empty result rather than scanning the whole DB.
  """
  @spec discrepancies(filter()) :: %{
          items: [discrepancy()],
          total: non_neg_integer(),
          truncated: boolean()
        }
  def discrepancies(filter \\ %{}) do
    gall_taxon_id = filter[:gall_taxon_id]
    host_taxon_id = filter[:host_taxon_id]

    if is_nil(gall_taxon_id) and is_nil(host_taxon_id) do
      %{items: [], total: 0, truncated: false}
    else
      run(filter, gall_taxon_id, host_taxon_id)
    end
  end

  defp run(filter, gall_taxon_id, host_taxon_id) do
    limit = filter[:limit] || @default_limit
    has_gf_notes = filter[:has_gf_notes] || :any

    assocs = load_associations(gall_taxon_id, host_taxon_id)
    gall_ids = assocs |> Enum.map(& &1.gall_id) |> Enum.uniq()

    descriptions = load_descriptions(gall_ids)
    gall_names = load_gall_names(gall_ids)

    all =
      assocs
      |> Enum.filter(fn a ->
        descs = descriptions[a.gall_id]
        keep_by_notes?(descs, has_gf_notes) and undocumented?(a, descs)
      end)
      |> Enum.map(fn a -> to_discrepancy(a, gall_names, descriptions[a.gall_id]) end)
      |> Enum.sort_by(&{&1.gall_name, &1.host_name})

    %{items: Enum.take(all, limit), total: length(all), truncated: length(all) > limit}
  end

  # --- Direction A -----------------------------------------------------------

  # host is undocumented if its current name appears in none of the gall's descriptions
  defp undocumented?(assoc, nil), do: assoc.direction_a_candidate

  defp undocumented?(assoc, descs) do
    host = %{name: assoc.host_name, genus_placeholder: assoc.genus_placeholder}
    not Enum.any?(descs, fn d -> HostNameMatcher.named_in?(host, d.description) end)
  end

  # --- Loaders ---------------------------------------------------------------

  # Loads gall↔host associations in scope, with the host's name + placeholder flag.
  defp load_associations(gall_taxon_id, host_taxon_id) do
    query =
      from(gh in GallHost,
        join: hs in Species,
        on: hs.id == gh.host_species_id,
        select: %{
          gall_id: gh.gall_species_id,
          host_id: gh.host_species_id,
          host_name: hs.name,
          genus_placeholder: hs.genus_placeholder,
          direction_a_candidate: true
        }
      )

    query
    |> scope_galls(gall_taxon_id)
    |> scope_hosts(host_taxon_id)
    |> Repo.all()
  end

  defp scope_galls(query, nil), do: query

  defp scope_galls(query, gall_taxon_id) do
    ids = Tree.species_ids_under_taxon(gall_taxon_id, "gall")
    from([gh, _hs] in query, where: gh.gall_species_id in ^ids)
  end

  defp scope_hosts(query, nil), do: query

  defp scope_hosts(query, host_taxon_id) do
    ids = Tree.species_ids_under_taxon(host_taxon_id, "plant")
    from([gh, _hs] in query, where: gh.host_species_id in ^ids)
  end

  # gall_id => [%{source_id, description}] (non-empty descriptions only)
  defp load_descriptions([]), do: %{}

  defp load_descriptions(gall_ids) do
    from(ss in SpeciesSource,
      where: ss.species_id in ^gall_ids and ss.description != "" and not is_nil(ss.description),
      select: %{gall_id: ss.species_id, source_id: ss.source_id, description: ss.description}
    )
    |> Repo.all()
    |> Enum.group_by(& &1.gall_id, &Map.take(&1, [:source_id, :description]))
  end

  defp load_gall_names([]), do: %{}

  defp load_gall_names(gall_ids) do
    from(s in Species, where: s.id in ^gall_ids, select: {s.id, s.name})
    |> Repo.all()
    |> Map.new()
  end

  # --- Helpers ---------------------------------------------------------------

  defp keep_by_notes?(_descs, :any), do: true
  defp keep_by_notes?(descs, :with), do: has_gf_notes?(descs)
  defp keep_by_notes?(descs, :without), do: not has_gf_notes?(descs)

  defp has_gf_notes?(nil), do: false
  defp has_gf_notes?(descs), do: Enum.any?(descs, &(&1.source_id == @gf_notes_source_id))

  defp to_discrepancy(assoc, gall_names, descs) do
    descs = descs || []

    %{
      gall_id: assoc.gall_id,
      gall_name: Map.get(gall_names, assoc.gall_id, "?"),
      host_id: assoc.host_id,
      host_name: assoc.host_name,
      genus_placeholder: assoc.genus_placeholder,
      direction: :undocumented_association,
      source_count: length(descs),
      has_gf_notes: has_gf_notes?(descs)
    }
  end

  @doc "The Gallformers ID Notes source id (source 58)."
  def gf_notes_source_id, do: @gf_notes_source_id
end
