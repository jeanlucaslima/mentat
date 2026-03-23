defmodule Mentat.NationAgent.FSMTest do
  use ExUnit.Case, async: true

  alias Mentat.NationAgent.FSM

  # Helper to build a minimal tile
  defp tile(id, opts) do
    %{
      id: id,
      adjacent: Keyword.get(opts, :adjacent, []),
      resource: Keyword.get(opts, :resource, %{type: nil, base_amount: 0}),
      traversable: Keyword.get(opts, :traversable, true),
      owner: Keyword.get(opts, :owner, nil)
    }
  end

  defp grain_resource(amount \\ 3), do: %{type: "grain", base_amount: amount}

  # A simple 3-tile chain: A -- B -- C
  defp three_tile_chain do
    %{
      "A" => tile("A", adjacent: ["B"], owner: "nation_1"),
      "B" => tile("B", adjacent: ["A", "C"]),
      "C" => tile("C", adjacent: ["B"], resource: grain_resource())
    }
  end

  defp base_snapshot(overrides) do
    Map.merge(
      %{
        id: "nation_1",
        grain: 500,
        troops: 300,
        capital_tile_id: "capital",
        troop_positions: %{"capital" => 100, "A" => 80},
        tiles: %{
          "capital" => tile("capital", adjacent: ["A"], owner: "nation_1"),
          "A" => tile("A", adjacent: ["capital", "B"], owner: "nation_1"),
          "B" => tile("B", adjacent: ["A", "C"], owner: nil),
          "C" => tile("C", adjacent: ["B"], owner: nil, resource: grain_resource())
        }
      },
      Map.new(overrides)
    )
  end

  describe "decide/1" do
    test "returns nil when troop_positions is empty" do
      snapshot = base_snapshot(troop_positions: %{})
      assert FSM.decide(snapshot) == nil
    end

    test "returns nil when nothing applies" do
      # Grain is high (no survival), troops low (no expansion), only 2 tiles (no consolidation)
      snapshot = base_snapshot(grain: 500, troops: 100)
      assert FSM.decide(snapshot) == nil
    end
  end

  describe "survival rule" do
    test "fires when grain is low and finds nearest grain tile" do
      tiles = %{
        "capital" => tile("capital", adjacent: ["front"], owner: "nation_1"),
        "front" => tile("front", adjacent: ["capital", "grain_tile"], owner: "nation_1"),
        "grain_tile" =>
          tile("grain_tile", adjacent: ["front"], owner: "enemy", resource: grain_resource())
      }

      snapshot = %{
        id: "nation_1",
        grain: 50,
        troops: 300,
        capital_tile_id: "capital",
        troop_positions: %{"capital" => 200, "front" => 100},
        tiles: tiles
      }

      action = FSM.decide(snapshot)
      assert action != nil
      assert action.type == :move_troops
      assert action.from == "front"
      assert action.to == "grain_tile"
      assert action.count > 0
    end

    test "does not move troops from capital below 1000" do
      tiles = three_tile_chain()

      snapshot = %{
        id: "nation_1",
        grain: 50,
        troops: 500,
        capital_tile_id: "A",
        troop_positions: %{"A" => 500},
        tiles: tiles
      }

      # Capital has 500 troops, min is 1000, so available = 0
      action = FSM.decide(snapshot)
      assert action == nil
    end

    test "moves from non-capital tile when capital is protected" do
      tiles = %{
        "capital" => tile("capital", adjacent: ["mid"], owner: "nation_1"),
        "mid" => tile("mid", adjacent: ["capital", "grain_tile"], owner: "nation_1"),
        "grain_tile" =>
          tile("grain_tile", adjacent: ["mid"], owner: "enemy", resource: grain_resource())
      }

      snapshot = %{
        id: "nation_1",
        grain: 50,
        troops: 300,
        capital_tile_id: "capital",
        troop_positions: %{"capital" => 200, "mid" => 100},
        tiles: tiles
      }

      action = FSM.decide(snapshot)
      assert action != nil
      assert action.type == :move_troops
      assert action.from == "mid"
      assert action.to == "grain_tile"
      assert action.count > 0
      assert action.count <= 100
    end
  end

  describe "expansion rule" do
    test "fires when stable and finds unclaimed tile" do
      tiles = %{
        "capital" => tile("capital", adjacent: ["A"], owner: "nation_1"),
        "A" => tile("A", adjacent: ["capital", "B"], owner: "nation_1"),
        "B" => tile("B", adjacent: ["A"])
      }

      snapshot = %{
        id: "nation_1",
        grain: 500,
        troops: 300,
        capital_tile_id: "capital",
        troop_positions: %{"capital" => 200, "A" => 100},
        tiles: tiles
      }

      action = FSM.decide(snapshot)
      assert action != nil
      assert action.type == :move_troops
      assert action.to == "B"
      assert action.from == "A"
    end

    test "does not fire when grain is low (survival takes priority)" do
      tiles = %{
        "capital" => tile("capital", adjacent: ["A"], owner: "nation_1"),
        "A" => tile("A", adjacent: ["capital", "B", "grain_t"], owner: "nation_1"),
        "B" => tile("B", adjacent: ["A"]),
        "grain_t" => tile("grain_t", adjacent: ["A"], owner: "enemy", resource: grain_resource())
      }

      snapshot = %{
        id: "nation_1",
        grain: 50,
        troops: 300,
        capital_tile_id: "capital",
        troop_positions: %{"capital" => 200, "A" => 100},
        tiles: tiles
      }

      action = FSM.decide(snapshot)
      assert action != nil
      # Should be survival (toward grain), not expansion (toward unclaimed B)
      assert action.to == "grain_t"
    end
  end

  describe "consolidation rule" do
    test "fires when troops spread across many tiles" do
      tiles = %{
        "capital" => tile("capital", adjacent: ["A", "B"], owner: "nation_1"),
        "A" => tile("A", adjacent: ["capital", "C"], owner: "nation_1"),
        "B" => tile("B", adjacent: ["capital"], owner: "nation_1"),
        "C" => tile("C", adjacent: ["A", "D"], owner: "nation_1"),
        "D" => tile("D", adjacent: ["C"], owner: "nation_1")
      }

      snapshot = %{
        id: "nation_1",
        grain: 500,
        troops: 250,
        capital_tile_id: "capital",
        troop_positions: %{"capital" => 50, "A" => 50, "B" => 50, "C" => 50, "D" => 50},
        tiles: tiles
      }

      action = FSM.decide(snapshot)
      assert action != nil
      assert action.type == :move_troops
      # Should move from a non-capital tile with fewest troops toward capital
      assert action.from != "capital"
    end

    test "does not fire with 3 or fewer tiles" do
      tiles = %{
        "capital" => tile("capital", adjacent: ["A", "B"], owner: "nation_1"),
        "A" => tile("A", adjacent: ["capital"], owner: "nation_1"),
        "B" => tile("B", adjacent: ["capital"], owner: "nation_1")
      }

      snapshot = %{
        id: "nation_1",
        grain: 500,
        troops: 150,
        capital_tile_id: "capital",
        troop_positions: %{"capital" => 50, "A" => 50, "B" => 50},
        tiles: tiles
      }

      assert FSM.decide(snapshot) == nil
    end
  end

  describe "bfs_find/3" do
    test "finds correct shortest path" do
      tiles = %{
        "A" => tile("A", adjacent: ["B", "C"]),
        "B" => tile("B", adjacent: ["A", "D"]),
        "C" => tile("C", adjacent: ["A", "D"]),
        "D" => tile("D", adjacent: ["B", "C", "E"]),
        "E" => tile("E", adjacent: ["D"])
      }

      {goal, path} = FSM.bfs_find(tiles, ["A"], fn id -> id == "E" end)
      assert goal == "E"
      assert hd(path) == "A"
      assert List.last(path) == "E"
      # Shortest path is A->B->D->E or A->C->D->E (length 4)
      assert length(path) == 4
    end

    test "returns nil when no traversable path exists" do
      tiles = %{
        "A" => tile("A", adjacent: ["ocean"]),
        "ocean" => tile("ocean", adjacent: ["A", "B"], traversable: false),
        "B" => tile("B", adjacent: ["ocean"])
      }

      result = FSM.bfs_find(tiles, ["A"], fn id -> id == "B" end)
      assert result == nil
    end

    test "returns goal when start is already the goal" do
      tiles = %{
        "A" => tile("A", adjacent: ["B"]),
        "B" => tile("B", adjacent: ["A"])
      }

      {goal, path} = FSM.bfs_find(tiles, ["A"], fn id -> id == "A" end)
      assert goal == "A"
      assert path == ["A"]
    end
  end
end
