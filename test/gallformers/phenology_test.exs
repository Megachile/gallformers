defmodule Gallformers.PhenologyTest do
  @moduledoc """
  Unit tests for the Phenology context (schema + minimal CRUD).
  Subsequent PRs will add import/review/visualization tests.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Phenology
  alias Gallformers.Phenology.Observation
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.Taxonomy

  defp create_gall_species(name \\ "Acraspis testica (agamic)") do
    {:ok, sp} =
      Repo.insert(%Species{name: name, taxoncode: "gall", datacomplete: false})

    sp
  end

  # Insert a taxonomy node directly (bypassing the changeset so tests can build
  # arbitrary trees without satisfying every create-time validation).
  defp insert_taxon(attrs) do
    {:ok, node} =
      Repo.insert(struct(Taxonomy, Map.put_new(attrs, :is_placeholder, false)))

    node
  end

  # Link a species to a taxonomy node via the species_taxonomy join table.
  defp link_taxon(species_id, taxonomy_id) do
    Repo.insert_all("species_taxonomy", [
      %{species_id: species_id, taxonomy_id: taxonomy_id}
    ])
  end

  # gall_traits is the 1:1 extension row the ID-tool filter engine inner-joins
  # on; a gall must have one to match any trait filter.
  defp insert_gall_traits(species_id) do
    Repo.insert_all("gall_traits", [%{species_id: species_id}])
  end

  defp insert_filter_field(table, column, name) do
    {1, [%{id: id}]} = Repo.insert_all(table, [%{column => name}], returning: [:id])
    id
  end

  defp link_color(species_id, color_id) do
    Repo.insert_all("gall_color", [%{species_id: species_id, color_id: color_id}])
  end

  defp link_shape(species_id, shape_id) do
    Repo.insert_all("gall_shape", [%{species_id: species_id, shape_id: shape_id}])
  end

  defp valid_attrs(species_id, overrides \\ %{}) do
    Map.merge(
      %{
        species_id: species_id,
        source_type: "literature",
        date: ~D[2024-06-15],
        doy: 167,
        latitude: 42.0,
        longitude: -83.0
      },
      overrides
    )
  end

  describe "create_observation/1" do
    test "creates a literature observation with valid attrs" do
      sp = create_gall_species()
      attrs = valid_attrs(sp.id, %{phenophase: "maturing", site: "Ann Arbor"})

      assert {:ok, %Observation{} = obs} = Phenology.create_observation(attrs)
      assert obs.species_id == sp.id
      assert obs.source_type == "literature"
      assert obs.phenophase == "maturing"
      assert obs.site == "Ann Arbor"
    end

    test "rejects missing required fields" do
      assert {:error, changeset} = Phenology.create_observation(%{})
      assert "can't be blank" in errors_on(changeset).species_id
      assert "can't be blank" in errors_on(changeset).source_type
      assert "can't be blank" in errors_on(changeset).date
    end

    test "rejects invalid source_type" do
      sp = create_gall_species()
      attrs = valid_attrs(sp.id, %{source_type: "twitter"})

      assert {:error, changeset} = Phenology.create_observation(attrs)
      assert "is invalid" in errors_on(changeset).source_type
    end

    test "requires inat_id when source_type is inat" do
      sp = create_gall_species()
      attrs = valid_attrs(sp.id, %{source_type: "inat"})

      assert {:error, changeset} = Phenology.create_observation(attrs)
      assert "is required when source_type is \"inat\"" in errors_on(changeset).inat_id
    end

    test "rejects inat_id when source_type is literature" do
      sp = create_gall_species()
      attrs = valid_attrs(sp.id, %{source_type: "literature", inat_id: 12_345})

      assert {:error, changeset} = Phenology.create_observation(attrs)
      assert "must be nil when source_type is \"literature\"" in errors_on(changeset).inat_id
    end

    test "accepts an iNat observation with an inat_id" do
      sp = create_gall_species()
      attrs = valid_attrs(sp.id, %{source_type: "inat", inat_id: 987_654})

      assert {:ok, obs} = Phenology.create_observation(attrs)
      assert obs.inat_id == 987_654
    end

    test "rejects out-of-range latitude / longitude / doy" do
      sp = create_gall_species()

      for {field, bad} <- [latitude: 95.0, longitude: -200.0, doy: 400] do
        attrs = valid_attrs(sp.id, %{field => bad})
        assert {:error, changeset} = Phenology.create_observation(attrs)
        assert Map.has_key?(errors_on(changeset), field)
      end
    end

    test "enforces unique inat_id" do
      sp = create_gall_species()
      attrs = valid_attrs(sp.id, %{source_type: "inat", inat_id: 555})

      assert {:ok, _} = Phenology.create_observation(attrs)
      assert {:error, changeset} = Phenology.create_observation(attrs)
      assert "has already been taken" in errors_on(changeset).inat_id
    end
  end

  describe "list_observations_for_species/1" do
    test "returns observations ordered by date" do
      sp = create_gall_species()

      {:ok, late} =
        Phenology.create_observation(valid_attrs(sp.id, %{date: ~D[2024-08-01], doy: 214}))

      {:ok, early} =
        Phenology.create_observation(valid_attrs(sp.id, %{date: ~D[2024-05-01], doy: 122}))

      assert [^early, ^late] = Phenology.list_observations_for_species(sp.id)
    end

    test "ignores observations from other species" do
      sp1 = create_gall_species("Acraspis a (agamic)")
      sp2 = create_gall_species("Acraspis b (agamic)")

      {:ok, _} = Phenology.create_observation(valid_attrs(sp1.id))
      {:ok, _} = Phenology.create_observation(valid_attrs(sp2.id))

      assert [obs] = Phenology.list_observations_for_species(sp1.id)
      assert obs.species_id == sp1.id
    end
  end

  describe "list_observations_needing_review/0" do
    test "returns observations where raw and processed phenophase disagree" do
      sp = create_gall_species()

      {:ok, agree} =
        Phenology.create_observation(
          valid_attrs(sp.id, %{raw_phenophase: "maturing", phenophase: "maturing"})
        )

      {:ok, disagree} =
        Phenology.create_observation(
          valid_attrs(sp.id, %{raw_phenophase: "Adult", phenophase: "developing"})
        )

      ids = Phenology.list_observations_needing_review() |> Enum.map(& &1.id)
      assert disagree.id in ids
      refute agree.id in ids
    end
  end

  describe "search_observations/1" do
    setup do
      sp_acraspis = create_gall_species("Acraspis erinacei (agamic)")
      sp_aulacidea = create_gall_species("Aulacidea solidaginis (sexgen)")
      sp_andricus = create_gall_species("Andricus quercuscalifornicus (agamic)")

      {:ok, _} =
        Phenology.create_observation(valid_attrs(sp_acraspis.id, %{phenophase: "developing"}))

      {:ok, _} =
        Phenology.create_observation(valid_attrs(sp_aulacidea.id, %{phenophase: "Free-living"}))

      {:ok, _} =
        Phenology.create_observation(valid_attrs(sp_andricus.id, %{phenophase: "maturing"}))

      %{acraspis: sp_acraspis, aulacidea: sp_aulacidea, andricus: sp_andricus}
    end

    test "no filters returns all gall obs with denormalized species name" do
      results = Phenology.search_observations()
      assert length(results) == 3
      names = Enum.map(results, & &1.species_name) |> Enum.sort()

      assert names == [
               "Acraspis erinacei (agamic)",
               "Andricus quercuscalifornicus (agamic)",
               "Aulacidea solidaginis (sexgen)"
             ]
    end

    test "search term filters by ILIKE on species name" do
      results = Phenology.search_observations(%{search: ["Acraspis"]})
      assert length(results) == 1
      assert hd(results).species_name == "Acraspis erinacei (agamic)"
    end

    test "multiple search terms OR together" do
      results = Phenology.search_observations(%{search: ["Acraspis", "Aulacidea"]})
      assert length(results) == 2
    end

    test "blank search terms are dropped (no filter applied)" do
      assert Phenology.search_observations(%{search: ["", "  "]}) |> length() == 3
    end

    test "generation :sexgen matches only (sexgen) species" do
      results = Phenology.search_observations(%{generation: :sexgen})
      assert length(results) == 1
      assert hd(results).species_name == "Aulacidea solidaginis (sexgen)"
    end

    test "generation :agamic matches only (agamic) species" do
      results = Phenology.search_observations(%{generation: :agamic})
      assert length(results) == 2
    end

    test "phenophases filter restricts to the given phenophases" do
      results = Phenology.search_observations(%{phenophases: ["maturing"]})
      assert length(results) == 1
      assert hd(results).phenophase == "maturing"
    end

    test "filters compose (search + generation)" do
      results =
        Phenology.search_observations(%{
          search: ["Acraspis", "Aulacidea"],
          generation: :sexgen
        })

      assert length(results) == 1
      assert hd(results).species_name == "Aulacidea solidaginis (sexgen)"
    end

    test "excludes host-plant rows (taxoncode != gall)" do
      {:ok, plant} =
        Repo.insert(%Species{name: "Quercus plant", taxoncode: "plant", datacomplete: false})

      # Insert directly bypassing changeset validation since plant species
      # shouldn't have phenology obs in practice.
      assert {:ok, _} =
               Phenology.create_observation(valid_attrs(plant.id, %{phenophase: "maturing"}))

      results = Phenology.search_observations()
      assert length(results) == 3
      refute Enum.any?(results, &(&1.species_name == "Quercus plant"))
    end
  end

  describe "taxonomic filter" do
    # Builds a small tree:  Cynipidae (family)
    #                         └─ Cynipini (intermediate, rank Tribe)
    #                             └─ Acraspis (genus) ─ sp_acraspis
    #                         └─ Aulacidea (genus, directly under family) ─ sp_aulacidea
    # plus a genus in another family: Eurosta (Tephritidae) ─ sp_eurosta
    setup do
      cynipidae = insert_taxon(%{name: "Cynipidae", type: "family", description: "Wasp"})

      cynipini =
        insert_taxon(%{
          name: "Cynipini",
          type: "intermediate",
          rank: "Tribe",
          parent_id: cynipidae.id
        })

      acraspis = insert_taxon(%{name: "Acraspis", type: "genus", parent_id: cynipini.id})
      aulacidea = insert_taxon(%{name: "Aulacidea", type: "genus", parent_id: cynipidae.id})

      tephritidae = insert_taxon(%{name: "Tephritidae", type: "family", description: "Fly"})
      eurosta = insert_taxon(%{name: "Eurosta", type: "genus", parent_id: tephritidae.id})

      sp_acraspis = create_gall_species("Acraspis erinacei (agamic)")
      sp_aulacidea = create_gall_species("Aulacidea nabali (sexgen)")
      sp_eurosta = create_gall_species("Eurosta solidaginis")
      link_taxon(sp_acraspis.id, acraspis.id)
      link_taxon(sp_aulacidea.id, aulacidea.id)
      link_taxon(sp_eurosta.id, eurosta.id)

      {:ok, _} = Phenology.create_observation(valid_attrs(sp_acraspis.id))
      {:ok, _} = Phenology.create_observation(valid_attrs(sp_aulacidea.id))
      {:ok, _} = Phenology.create_observation(valid_attrs(sp_eurosta.id))

      %{
        cynipidae: cynipidae,
        cynipini: cynipini,
        acraspis: acraspis,
        tephritidae: tephritidae,
        sp_acraspis: sp_acraspis,
        sp_aulacidea: sp_aulacidea,
        sp_eurosta: sp_eurosta
      }
    end

    test "species_ids_under_taxon/1 collects the whole subtree", ctx do
      family = Phenology.species_ids_under_taxon(ctx.cynipidae.id) |> Enum.sort()
      assert family == Enum.sort([ctx.sp_acraspis.id, ctx.sp_aulacidea.id])

      # An intermediate (tribe) node only reaches genera below it.
      assert Phenology.species_ids_under_taxon(ctx.cynipini.id) == [ctx.sp_acraspis.id]
      # A genus node reaches its own directly-linked species.
      assert Phenology.species_ids_under_taxon(ctx.acraspis.id) == [ctx.sp_acraspis.id]
    end

    test "species_ids_under_taxon/1 returns [] for an unknown id" do
      assert Phenology.species_ids_under_taxon(9_999_999) == []
    end

    test "search_observations filters by family (walks through the tribe)", ctx do
      results = Phenology.search_observations(%{taxon_id: ctx.cynipidae.id})
      names = Enum.map(results, & &1.species_name) |> Enum.sort()
      assert names == ["Acraspis erinacei (agamic)", "Aulacidea nabali (sexgen)"]
      refute "Eurosta solidaginis" in names
    end

    test "search_observations filters by genus", ctx do
      results = Phenology.search_observations(%{taxon_id: ctx.acraspis.id})
      assert length(results) == 1
      assert hd(results).species_name == "Acraspis erinacei (agamic)"
    end

    test "an unknown taxon_id yields no observations", _ctx do
      assert Phenology.search_observations(%{taxon_id: 9_999_999}) == []
    end

    test "taxon filter composes with generation", ctx do
      results =
        Phenology.search_observations(%{taxon_id: ctx.cynipidae.id, generation: :sexgen})

      assert length(results) == 1
      assert hd(results).species_name == "Aulacidea nabali (sexgen)"
    end

    test "list_taxon_filter_options returns data-bearing family/tribe nodes, grouped and counted",
         _ctx do
      opts = Phenology.list_taxon_filter_options()
      by_name = Map.new(opts, &{&1.name, &1})

      # Cynipidae: 2 observed species beneath it; grouped as a Family.
      assert %{group: "Family", n_species: 2} = by_name["Cynipidae"]
      # The tribe shows up with its rank as the group label.
      assert %{group: "Tribe", n_species: 1} = by_name["Cynipini"]
      assert %{group: "Family", n_species: 1} = by_name["Tephritidae"]

      # Genera are intentionally excluded — the text search box covers those.
      refute Map.has_key?(by_name, "Acraspis")
      refute Map.has_key?(by_name, "Aulacidea")
      refute Map.has_key?(by_name, "Eurosta")
      refute Enum.any?(opts, &(&1.group == "Genus"))

      # Ordered family → tribe.
      groups = Enum.map(opts, & &1.group) |> Enum.uniq()

      assert Enum.find_index(groups, &(&1 == "Family")) <
               Enum.find_index(groups, &(&1 == "Tribe"))
    end
  end

  describe "gall-trait filter" do
    setup do
      red = insert_filter_field("color", :color, "test-red")
      green = insert_filter_field("color", :color, "test-green")
      ball = insert_filter_field("shape", :shape, "test-ball")

      # red + ball ; red only ; green only — each a gall with a gall_traits row
      sp_red_ball = create_gall_species("Acraspis redball (agamic)")
      sp_red = create_gall_species("Acraspis redonly (agamic)")
      sp_green = create_gall_species("Andricus greeny (agamic)")

      for sp <- [sp_red_ball, sp_red, sp_green], do: insert_gall_traits(sp.id)
      link_color(sp_red_ball.id, red)
      link_shape(sp_red_ball.id, ball)
      link_color(sp_red.id, red)
      link_color(sp_green.id, green)

      for sp <- [sp_red_ball, sp_red, sp_green],
          do: {:ok, _} = Phenology.create_observation(valid_attrs(sp.id))

      %{red: red, green: green, ball: ball}
    end

    test "filters by a single color (OR within facet is trivial here)", ctx do
      names =
        Phenology.search_observations(%{color_ids: [ctx.red]})
        |> Enum.map(& &1.species_name)
        |> Enum.sort()

      assert names == ["Acraspis redball (agamic)", "Acraspis redonly (agamic)"]
    end

    test "filters by shape", ctx do
      results = Phenology.search_observations(%{shape_ids: [ctx.ball]})
      assert Enum.map(results, & &1.species_name) == ["Acraspis redball (agamic)"]
    end

    test "multiple facets compose with AND across facets", ctx do
      # red AND ball → only the species carrying both
      results = Phenology.search_observations(%{color_ids: [ctx.red], shape_ids: [ctx.ball]})
      assert Enum.map(results, & &1.species_name) == ["Acraspis redball (agamic)"]
    end

    test "multiple ids within a facet are OR-ed", ctx do
      names =
        Phenology.search_observations(%{color_ids: [ctx.red, ctx.green]})
        |> Enum.map(& &1.species_name)
        |> Enum.sort()

      assert names == [
               "Acraspis redball (agamic)",
               "Acraspis redonly (agamic)",
               "Andricus greeny (agamic)"
             ]
    end

    test "empty trait lists are ignored (no filter applied)", _ctx do
      assert Phenology.search_observations(%{color_ids: [], shape_ids: []}) |> length() == 3
    end

    test "trait filter composes with name search", ctx do
      results =
        Phenology.search_observations(%{search: ["Acraspis"], color_ids: [ctx.red]})

      names = Enum.map(results, & &1.species_name) |> Enum.sort()
      assert names == ["Acraspis redball (agamic)", "Acraspis redonly (agamic)"]
    end
  end

  describe "blacklist" do
    test "blacklist/1 then blacklisted?/1 roundtrip" do
      refute Phenology.blacklisted?(42)

      assert {:ok, _} = Phenology.blacklist(%{inat_id: 42, reason: "wrong species"})
      assert Phenology.blacklisted?(42)
    end

    test "blacklist/1 rejects duplicate inat_id" do
      assert {:ok, _} = Phenology.blacklist(%{inat_id: 99})
      assert {:error, changeset} = Phenology.blacklist(%{inat_id: 99})
      assert "has already been taken" in errors_on(changeset).inat_id
    end

    test "blacklist/1 requires inat_id" do
      assert {:error, changeset} = Phenology.blacklist(%{})
      assert "can't be blank" in errors_on(changeset).inat_id
    end
  end
end
