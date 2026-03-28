defmodule Mentat.MapGenTest do
  use ExUnit.Case

  alias Mentat.MapGen

  describe "generate/1" do
    test "full pipeline produces valid scenario" do
      # Override the writer base path by generating to tmp
      opts = [name: "test_gen", preset: :standard, seed: 42]
      assert {:ok, result} = MapGen.generate(opts)
      assert result.tile_count > 100
      assert result.seed == 42
      assert result.name == "test_gen"

      # Verify ScenarioLoader can load it
      assert {:ok, data} = Mentat.ScenarioLoader.load("test_gen")
      assert length(data.tiles) == result.tile_count
      assert length(data.nations) == 5

      # All capitals on land
      for nation <- data.nations do
        tile = Enum.find(data.tiles, fn t -> t.id == nation.capital_tile_id end)
        assert tile != nil, "Capital tile #{nation.capital_tile_id} not found"
        assert tile.traversable, "Capital #{nation.capital_tile_id} not traversable"
        assert tile.type != "ocean", "Capital #{nation.capital_tile_id} is ocean"
      end
    end

    test "same seed produces identical output" do
      opts = [name: "det_test_a", preset: :standard, seed: 123]
      {:ok, result_a} = MapGen.generate(opts)

      # Clean up and regenerate
      File.rm_rf!(Path.join([:code.priv_dir(:mentat), "scenarios", "det_test_a"]))
      {:ok, result_b} = MapGen.generate(opts)

      assert result_a.tile_count == result_b.tile_count
      assert result_a.seed == result_b.seed
    end

    test "generated scenario includes settlement structures" do
      opts = [name: "test_settlements_e2e", preset: :standard, seed: 99]
      assert {:ok, _result} = MapGen.generate(opts)

      assert {:ok, data} = Mentat.ScenarioLoader.load("test_settlements_e2e")

      types = Enum.map(data.structures, & &1.type) |> Enum.uniq() |> Enum.sort()

      # Should have more than just capitals
      assert "capital" in types
      assert length(types) > 1, "Expected multiple structure types, got: #{inspect(types)}"

      # At least some non-capital settlements
      non_capitals = Enum.reject(data.structures, fn s -> s.type == "capital" end)
      assert length(non_capitals) > 0, "No non-capital settlements generated"

      # Total structures should be reasonable (5 capitals + settlements)
      assert length(data.structures) > 10
    end
  end

  setup do
    on_exit(fn ->
      for name <- ["test_gen", "det_test_a", "test_settlements_e2e"] do
        File.rm_rf(Path.join([:code.priv_dir(:mentat), "scenarios", name]))
      end
    end)
  end
end
