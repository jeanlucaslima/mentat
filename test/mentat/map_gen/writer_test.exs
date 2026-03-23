defmodule Mentat.MapGen.WriterTest do
  use ExUnit.Case, async: true

  alias Mentat.MapGen.Writer

  describe "validate/2" do
    test "catches non-bidirectional adjacency" do
      cells = [
        %{
          index: 0,
          adjacent: [1],
          type: "plains",
          traversable: true,
          polygon: [{0, 0}, {1, 0}, {0, 1}]
        },
        %{
          index: 1,
          adjacent: [],
          type: "plains",
          traversable: true,
          polygon: [{1, 0}, {2, 0}, {1, 1}]
        }
      ]

      nations = []
      assert {:error, msg} = Writer.validate(cells, nations)
      assert msg =~ "Non-bidirectional"
    end

    test "catches ocean capital" do
      cells = [
        %{
          index: 0,
          adjacent: [1],
          type: "ocean",
          traversable: false,
          polygon: [{0, 0}, {1, 0}, {0, 1}]
        },
        %{
          index: 1,
          adjacent: [0],
          type: "plains",
          traversable: true,
          polygon: [{1, 0}, {2, 0}, {1, 1}]
        }
      ]

      nations = [%{capital_tile_id: "t_0", name: "Test"}]
      assert {:error, msg} = Writer.validate(cells, nations)
      assert msg =~ "non-land"
    end

    test "catches duplicate capitals" do
      cells = [
        %{
          index: 0,
          adjacent: [1],
          type: "plains",
          traversable: true,
          polygon: [{0, 0}, {1, 0}, {0, 1}]
        },
        %{
          index: 1,
          adjacent: [0],
          type: "plains",
          traversable: true,
          polygon: [{1, 0}, {2, 0}, {1, 1}]
        }
      ]

      nations = [
        %{capital_tile_id: "t_0", name: "A"},
        %{capital_tile_id: "t_0", name: "B"}
      ]

      assert {:error, msg} = Writer.validate(cells, nations)
      assert msg =~ "Duplicate"
    end

    test "valid input passes" do
      cells = [
        %{
          index: 0,
          adjacent: [1],
          type: "plains",
          traversable: true,
          polygon: [{0, 0}, {1, 0}, {0, 1}]
        },
        %{
          index: 1,
          adjacent: [0],
          type: "plains",
          traversable: true,
          polygon: [{1, 0}, {2, 0}, {1, 1}]
        }
      ]

      nations = [%{capital_tile_id: "t_0", name: "A"}]
      assert :ok = Writer.validate(cells, nations)
    end
  end

  describe "write/4" do
    @tag :tmp_dir
    test "writes three JSON files", %{tmp_dir: tmp_dir} do
      cells = [
        %{
          index: 0,
          adjacent: [1, 2],
          type: "plains",
          traversable: true,
          polygon: [{0.0, 0.0}, {10.0, 0.0}, {5.0, 10.0}],
          cx: 5.0,
          cy: 3.3,
          movement_cost: 1,
          defensive_bonus: 0,
          resource: %{type: "grain", base_amount: 30},
          river_edges: []
        },
        %{
          index: 1,
          adjacent: [0, 2],
          type: "ocean",
          traversable: false,
          polygon: [{10.0, 0.0}, {20.0, 0.0}, {15.0, 10.0}],
          cx: 15.0,
          cy: 3.3,
          movement_cost: 99,
          defensive_bonus: 0,
          resource: %{type: nil, base_amount: 0},
          river_edges: []
        },
        %{
          index: 2,
          adjacent: [0, 1],
          type: "plains",
          traversable: true,
          polygon: [{5.0, 10.0}, {15.0, 10.0}, {10.0, 20.0}],
          cx: 10.0,
          cy: 13.3,
          movement_cost: 1,
          defensive_bonus: 0,
          resource: %{type: nil, base_amount: 0},
          river_edges: []
        }
      ]

      nations = [
        %{
          id: "n1",
          name: "Test Nation",
          color: "#FF0000",
          government_type: "democracy",
          starting_tiles: ["t_0"],
          capital_tile_id: "t_0",
          starting_resources: %{"grain" => 300, "troops" => 150},
          troop_positions: %{"t_0" => 150},
          internal_stability: 70,
          public_approval: 65,
          political_rules: [
            %{action: "declare_war", requires: ["vote"], resolves_in_ticks: 168}
          ]
        }
      ]

      assert :ok = Writer.write("test_scenario", cells, nations, tmp_dir)
      assert File.exists?(Path.join([tmp_dir, "test_scenario", "map.json"]))
      assert File.exists?(Path.join([tmp_dir, "test_scenario", "nations.json"]))
      assert File.exists?(Path.join([tmp_dir, "test_scenario", "structures.json"]))

      {:ok, map_data} = File.read(Path.join([tmp_dir, "test_scenario", "map.json"]))
      parsed = Jason.decode!(map_data)
      assert length(parsed["tiles"]) == 3
    end
  end
end
