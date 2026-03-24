defmodule Mentat.MapGen.TerrainTest do
  use ExUnit.Case, async: true

  alias Mentat.MapGen.Terrain

  describe "type_from_elevation/1" do
    test "ocean below 0.28" do
      {type, traversable, _, _} = Terrain.type_from_elevation(0.1)
      assert type == "ocean"
      assert traversable == false
    end

    test "coast at 0.30" do
      {type, traversable, _, _} = Terrain.type_from_elevation(0.30)
      assert type == "coast"
      assert traversable == true
    end

    test "plains at 0.40" do
      {type, _, _, _} = Terrain.type_from_elevation(0.40)
      assert type == "plains"
    end

    test "forest at 0.55" do
      {type, _, _, _} = Terrain.type_from_elevation(0.55)
      assert type == "forest"
    end

    test "hills at 0.65" do
      {type, _, _, _} = Terrain.type_from_elevation(0.65)
      assert type == "hills"
    end

    test "mountains at 0.80" do
      {type, _, _, _} = Terrain.type_from_elevation(0.80)
      assert type == "mountains"
    end
  end

  describe "island_mask/5" do
    test "center has maximum value" do
      val = Terrain.island_mask(400, 300, 800, 600, %{mode: :single, radius: 1.5, power: 1.2})
      assert val > 0.9
    end

    test "edge has low value" do
      val = Terrain.island_mask(10, 10, 800, 600, %{mode: :single, radius: 1.5, power: 1.2})
      assert val < 0.5
    end

    test "noisy mask with seed returns values in 0.0-1.0 range" do
      params = %{mode: :single, radius: 1.5, power: 1.2, seed: 42}

      for x <- [10, 100, 200, 400, 700, 790], y <- [10, 100, 300, 500, 590] do
        val = Terrain.island_mask(x, y, 800, 600, params)
        assert val >= 0.0 and val <= 1.0, "Expected 0.0-1.0 but got #{val} at (#{x}, #{y})"
      end
    end

    test "noisy mask center still higher than edge" do
      params = %{mode: :single, radius: 1.5, power: 1.2, seed: 42}
      center = Terrain.island_mask(400, 300, 800, 600, params)
      edge = Terrain.island_mask(10, 10, 800, 600, params)
      assert center > edge
    end
  end
end
