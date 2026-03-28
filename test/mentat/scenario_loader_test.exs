defmodule Mentat.ScenarioLoaderTest do
  use ExUnit.Case, async: true

  alias Mentat.ScenarioLoader

  describe "load/1" do
    test "loads world_standard_42 successfully" do
      assert {:ok, data} = ScenarioLoader.load("world_standard_42")
      assert is_list(data.tiles)
      assert is_list(data.nations)
      assert is_list(data.structures)
    end

    test "returns correct tile count" do
      {:ok, data} = ScenarioLoader.load("world_standard_42")
      assert length(data.tiles) == 396
    end

    test "all five nations are present" do
      {:ok, data} = ScenarioLoader.load("world_standard_42")
      nation_ids = Enum.map(data.nations, & &1.id) |> Enum.sort()
      assert nation_ids == ["nation_1", "nation_2", "nation_3", "nation_4", "nation_5"]
    end

    test "adjacency lists are bidirectional" do
      {:ok, data} = ScenarioLoader.load("world_standard_42")
      tile_map = Map.new(data.tiles, fn tile -> {tile.id, tile} end)

      for tile <- data.tiles, neighbor_id <- tile.adjacent do
        neighbor = Map.fetch!(tile_map, neighbor_id)

        assert tile.id in neighbor.adjacent,
               "tile #{tile.id} lists #{neighbor_id} as adjacent, but #{neighbor_id} does not list #{tile.id}"
      end
    end

    test "returns error for nonexistent scenario" do
      assert {:error, _reason} = ScenarioLoader.load("nonexistent")
    end

    test "tiles have correct types" do
      {:ok, data} = ScenarioLoader.load("world_standard_42")
      tile = Enum.find(data.tiles, &(&1.id == "t_2"))

      assert tile.type == "coast"
      assert tile.x == 519
      assert tile.y == 287
      assert is_list(tile.adjacent)
      assert is_boolean(tile.traversable)
      assert is_integer(tile.movement_cost)
    end

    test "nations have political rules parsed" do
      {:ok, data} = ScenarioLoader.load("world_standard_42")
      nation = Enum.find(data.nations, &(&1.id == "nation_1"))

      assert length(nation.political_rules) == 3

      war_rule = Enum.find(nation.political_rules, &(&1.action == "declare_war"))
      assert war_rule.requires == ["parliamentary_vote"]
      assert war_rule.resolves_in_ticks == 168
    end

    test "structures have tier, population, and flags fields" do
      {:ok, data} = ScenarioLoader.load("world_standard_42")

      for structure <- data.structures do
        assert is_integer(structure.tier) or is_nil(structure.tier)
        assert is_integer(structure.population)
        assert is_list(structure.flags)
      end
    end

    test "tier is inferred from type when not in JSON" do
      {:ok, data} = ScenarioLoader.load("world_standard_42")

      capitals = Enum.filter(data.structures, fn s -> s.type == "capital" end)
      assert length(capitals) > 0

      for capital <- capitals do
        assert capital.tier == 1, "Capital should have tier 1, got #{inspect(capital.tier)}"
      end
    end

    test "structures reference valid tiles and nations" do
      {:ok, data} = ScenarioLoader.load("world_standard_42")
      tile_ids = MapSet.new(data.tiles, & &1.id)
      nation_ids = MapSet.new(data.nations, & &1.id)

      for structure <- data.structures do
        assert structure.tile_id in tile_ids,
               "structure references unknown tile #{structure.tile_id}"

        assert structure.nation_id in nation_ids,
               "structure references unknown nation #{structure.nation_id}"
      end
    end
  end
end
