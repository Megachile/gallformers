defmodule Gallformers.PhenologyTest do
  @moduledoc """
  Unit tests for the Phenology context (schema + minimal CRUD).
  Subsequent PRs will add import/review/visualization tests.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Phenology
  alias Gallformers.Phenology.Observation
  alias Gallformers.Species.Species

  defp create_gall_species(name \\ "Acraspis testica (agamic)") do
    {:ok, sp} =
      Repo.insert(%Species{name: name, taxoncode: "gall", datacomplete: false})

    sp
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
