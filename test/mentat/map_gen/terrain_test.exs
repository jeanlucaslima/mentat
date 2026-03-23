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
  end
end
