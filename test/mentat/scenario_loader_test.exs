defmodule Mentat.ScenarioLoaderTest do
  use ExUnit.Case, async: true

  alias Mentat.ScenarioLoader

  describe "load/1" do
    test "loads world_01 successfully" do
      assert {:ok, data} = ScenarioLoader.load("world_01")
      assert is_list(data.tiles)
      assert is_list(data.nations)
      assert is_list(data.structures)
    end

    test "returns correct tile count" do
      {:ok, data} = ScenarioLoader.load("world_01")
      assert length(data.tiles) == 55
    end

    test "all five nations are present" do
      {:ok, data} = ScenarioLoader.load("world_01")
      nation_ids = Enum.map(data.nations, & &1.id) |> Enum.sort()
      assert nation_ids == ["drenmoor", "karan", "nordavia", "solmark", "vestmark"]
    end

    test "adjacency lists are bidirectional" do
      {:ok, data} = ScenarioLoader.load("world_01")
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
      {:ok, data} = ScenarioLoader.load("world_01")
      tile = Enum.find(data.tiles, &(&1.id == "t_4_1"))

      assert tile.type == "plains"
      assert tile.x == 4
      assert tile.y == 1
      assert is_list(tile.adjacent)
      assert is_boolean(tile.traversable)
      assert is_integer(tile.movement_cost)
    end

    test "nations have political rules parsed" do
      {:ok, data} = ScenarioLoader.load("world_01")
      nordavia = Enum.find(data.nations, &(&1.id == "nordavia"))

      assert length(nordavia.political_rules) == 3

      war_rule = Enum.find(nordavia.political_rules, &(&1.action == "declare_war"))
      assert war_rule.requires == ["parliamentary_vote"]
      assert war_rule.resolves_in_ticks == 168
    end

    test "structures reference valid tiles and nations" do
      {:ok, data} = ScenarioLoader.load("world_01")
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
