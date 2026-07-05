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
      rejected report). Mentions are resolved against the real plant-species
      dictionary, so non-plant capitalized words (the inducer, linked galls,
      morphology terms) simply drop out.

  Everything is computed on demand from live data — no stored state, no
  dismissal table. Reconciliation happens by editing the structured data or the
  public GF Notes, both of which change what this check sees next load.
  """

  import Ecto.Query

  alias Gallformers.Galls.{GallHost, HostMentions, HostNameMatcher}
  alias Gallformers.Repo
  alias Gallformers.Species.{Alias, Species, SpeciesSource}
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
          has_gf_notes: boolean(),
          snippet: String.t()
        }

  @type filter :: %{
          optional(:gall_taxon_id) => integer() | nil,
          optional(:host_taxon_id) => integer() | nil,
          optional(:direction) => :a | :b | :both,
          optional(:has_gf_notes) => :any | :with | :without,
          optional(:limit) => pos_integer()
        }

  @doc """
  Computes host-association discrepancies for the filtered scope.

  Returns `%{items: [discrepancy], total: integer, truncated: boolean}` where
  `items` is capped at the filter's `:limit` (default #{@default_limit}) but
  `total` reflects the full count for the scope.

  `:direction` selects `:a` (undocumented associations, default), `:b`
  (unassociated literature mentions), or `:both`.

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
    direction = normalize_direction(filter[:direction])

    assocs = load_associations(gall_taxon_id, host_taxon_id)

    b_gall_ids =
      if direction in [:b, :both],
        do: b_gall_scope(assocs, gall_taxon_id),
        else: []

    gall_ids = (Enum.map(assocs, & &1.gall_id) ++ b_gall_ids) |> Enum.uniq()
    descriptions = load_descriptions(gall_ids)
    gall_names = load_gall_names(gall_ids)

    a_items =
      if direction in [:a, :both],
        do: direction_a(assocs, descriptions, gall_names, has_gf_notes),
        else: []

    b_items =
      if direction in [:b, :both],
        do: direction_b(b_gall_ids, descriptions, gall_names, host_taxon_id, has_gf_notes),
        else: []

    all = Enum.sort_by(a_items ++ b_items, &{&1.gall_name, &1.direction, &1.host_name})

    %{items: Enum.take(all, limit), total: length(all), truncated: length(all) > limit}
  end

  # --- Direction A: host in gallhost, not named in any source ------------------

  defp direction_a(assocs, descriptions, gall_names, has_gf_notes) do
    assocs
    |> Enum.filter(fn a ->
      descs = descriptions[a.gall_id]
      keep_by_notes?(descs, has_gf_notes) and undocumented?(a, descs)
    end)
    |> Enum.map(fn a -> to_a_discrepancy(a, gall_names, descriptions[a.gall_id]) end)
  end

  defp undocumented?(_assoc, nil), do: true

  defp undocumented?(assoc, descs) do
    host = %{name: assoc.host_name, genus_placeholder: assoc.genus_placeholder}
    not Enum.any?(descs, fn d -> HostNameMatcher.named_in?(host, d.description) end)
  end

  # --- Direction B: plant named in prose, no gallhost row ----------------------

  defp direction_b(gall_ids, descriptions, gall_names, host_taxon_id, has_gf_notes) do
    index = plant_index()
    existing = load_host_ids_by_gall(gall_ids)
    host_scope = host_scope_set(host_taxon_id)

    Enum.flat_map(gall_ids, fn gid ->
      descs = descriptions[gid] || []

      if descs == [] or not keep_by_notes?(descs, has_gf_notes) do
        []
      else
        mentions_for_gall(gid, descs, gall_names, index, existing, host_scope)
      end
    end)
  end

  defp mentions_for_gall(gid, descs, gall_names, index, existing, host_scope) do
    have = Map.get(existing, gid, MapSet.new())
    texts = Enum.map(descs, & &1.description)

    descs
    |> Enum.flat_map(fn d -> HostMentions.extract(d.description) end)
    |> Enum.uniq()
    |> Enum.reduce(%{}, fn key, acc ->
      resolve_mention(acc, key, index, have, host_scope, texts)
    end)
    |> Enum.map(fn {host_id, host_name} ->
      to_b_discrepancy(gid, host_id, host_name, gall_names, descs, texts)
    end)
  end

  defp resolve_mention(acc, {genus, epithet}, index, have, host_scope, texts) do
    with {host_id, host_name} <- Map.get(index, {genus, epithet}),
         false <- MapSet.member?(have, host_id),
         true <- in_host_scope?(host_scope, host_id),
         false <- text_flagged?(host_name, texts) do
      Map.put_new(acc, host_id, host_name)
    else
      _ -> acc
    end
  end

  defp in_host_scope?(nil, _host_id), do: true
  defp in_host_scope?(scope, host_id), do: MapSet.member?(scope, host_id)

  defp text_flagged?(host_name, texts) do
    host = %{name: host_name, genus_placeholder: false}
    Enum.any?(texts, &HostNameMatcher.text_flag?(host, &1))
  end

  # --- Scope + loaders ---------------------------------------------------------

  # Direction B needs the full gall scope (incl. galls with zero hosts), which
  # can only come from the taxon filter — not from gallhost.
  defp b_gall_scope(_assocs, gall_taxon_id) when is_integer(gall_taxon_id),
    do: Tree.species_ids_under_taxon(gall_taxon_id, "gall")

  defp b_gall_scope(assocs, nil), do: assocs |> Enum.map(& &1.gall_id) |> Enum.uniq()

  defp host_scope_set(nil), do: nil

  defp host_scope_set(host_taxon_id),
    do: MapSet.new(Tree.species_ids_under_taxon(host_taxon_id, "plant"))

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
          genus_placeholder: hs.genus_placeholder
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

  defp load_host_ids_by_gall([]), do: %{}

  defp load_host_ids_by_gall(gall_ids) do
    from(gh in GallHost,
      where: gh.gall_species_id in ^gall_ids,
      select: {gh.gall_species_id, gh.host_species_id}
    )
    |> Repo.all()
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Map.new(fn {gid, host_ids} -> {gid, MapSet.new(host_ids)} end)
  end

  # {genus, epithet} => {species_id, canonical_name} for every plant species,
  # plus its aliases. Current names win over aliases (Map.put_new).
  defp plant_index do
    names =
      from(s in Species,
        where: s.taxoncode == "plant" and s.genus_placeholder == false,
        select: {s.id, s.name}
      )
      |> Repo.all()

    aliases =
      from(a in Alias,
        join: link in "alias_species",
        on: link.alias_id == a.id,
        join: s in Species,
        on: s.id == link.species_id,
        where: s.taxoncode == "plant",
        select: {s.id, s.name, a.name}
      )
      |> Repo.all()

    base = Enum.reduce(names, %{}, fn {id, name}, acc -> put_index(acc, name, {id, name}) end)

    Enum.reduce(aliases, base, fn {id, canon, alias_name}, acc ->
      put_index(acc, alias_name, {id, canon})
    end)
  end

  defp put_index(acc, name, value) do
    case HostNameMatcher.parse_name(%{name: name, genus_placeholder: false}) do
      %{epithet: nil} -> acc
      %{genus: genus, epithet: epithet} -> Map.put_new(acc, {genus, epithet}, value)
    end
  end

  # --- Discrepancy builders ----------------------------------------------------

  defp to_a_discrepancy(assoc, gall_names, descs) do
    descs = descs || []

    %{
      gall_id: assoc.gall_id,
      gall_name: Map.get(gall_names, assoc.gall_id, "?"),
      host_id: assoc.host_id,
      host_name: assoc.host_name,
      genus_placeholder: assoc.genus_placeholder,
      direction: :undocumented_association,
      source_count: length(descs),
      has_gf_notes: has_gf_notes?(descs),
      snippet: ""
    }
  end

  defp to_b_discrepancy(gid, host_id, host_name, gall_names, descs, texts) do
    %{
      gall_id: gid,
      gall_name: Map.get(gall_names, gid, "?"),
      host_id: host_id,
      host_name: host_name,
      genus_placeholder: false,
      direction: :unassociated_mention,
      source_count: length(descs),
      has_gf_notes: has_gf_notes?(descs),
      snippet: snippet_for(host_name, texts)
    }
  end

  defp snippet_for(host_name, texts) do
    parts = String.split(host_name)
    epithet = parts |> Enum.at(1, "") |> String.downcase()
    genus = parts |> Enum.at(0, "") |> String.downcase()

    # Prefer the epithet; fall back to the genus (covers alias-resolved mentions
    # where the text used a synonym that shares the genus).
    [epithet, genus]
    |> Enum.reject(&(&1 == ""))
    |> Enum.find_value("", fn term ->
      Enum.find_value(texts, fn text -> window_around(text, term) end)
    end)
  end

  defp window_around(text, epithet) do
    case :binary.match(String.downcase(text), epithet) do
      {pos, len} ->
        text
        |> String.slice(max(pos - 30, 0), len + 90)
        |> String.replace(~r/\s+/, " ")
        |> String.trim()

      :nomatch ->
        nil
    end
  end

  # --- Helpers -----------------------------------------------------------------

  defp normalize_direction(d) when d in [:b, "b"], do: :b
  defp normalize_direction(d) when d in [:both, "both"], do: :both
  defp normalize_direction(_), do: :a

  defp keep_by_notes?(_descs, :any), do: true
  defp keep_by_notes?(descs, :with), do: has_gf_notes?(descs)
  defp keep_by_notes?(descs, :without), do: not has_gf_notes?(descs)

  defp has_gf_notes?(nil), do: false
  defp has_gf_notes?(descs), do: Enum.any?(descs, &(&1.source_id == @gf_notes_source_id))

  @doc "The Gallformers ID Notes source id (source 58)."
  def gf_notes_source_id, do: @gf_notes_source_id
end
