defmodule Mentat.MapGen.NationsTest do
  use ExUnit.Case, async: true

  alias Mentat.MapGen.{PoissonDisk, Delaunay, Voronoi, Terrain, Resources, Rivers, Nations}

  @seed 42

  defp generate_cells do
    points = PoissonDisk.sample(800, 600, 28, @seed)
    triangles = Delaunay.triangulate(points)
    cells = Voronoi.from_delaunay(points, triangles, 800, 600)

    island_mask = %{
      type: :single,
      cx: 400.0,
      cy: 300.0,
      radius: 1.5
    }

    cells = Terrain.assign(cells, @seed, width: 800, height: 600, island_mask: island_mask)
    cells = Resources.assign(cells, @seed)
    Rivers.generate(cells, 3, @seed)
  end

  defp generate_nations(cells) do
    {:ok, nations} = Nations.place_capitals(cells, 5, @seed)
    nations
  end

  describe "place_settlements/2" do
    setup do
      cells = generate_cells()
      nations = generate_nations(cells)
      {updated_nations, structures} = Nations.place_settlements(cells, nations)
      %{cells: cells, nations: updated_nations, structures: structures}
    end

    test "places settlements for each nation", %{structures: structures, nations: nations} do
      nation_ids = Enum.map(nations, & &1.id)

      for nation_id <- nation_ids do
        nation_structures = Enum.filter(structures, fn s -> s.nation_id == nation_id end)
        # Every nation should have at least its capital
        assert length(nation_structures) >= 1,
               "#{nation_id} has no structures"
      end

      # Total structures should be more than just 5 capitals
      assert length(structures) > 5
    end

    test "all settlement tiles are traversable land", %{structures: structures, cells: cells} do
      cells_map = Map.new(cells, fn c -> {"t_#{c.index}", c} end)

      for structure <- structures do
        cell = Map.get(cells_map, structure.tile_id)
        assert cell != nil, "Structure tile #{structure.tile_id} not found"
        assert cell.traversable, "Settlement on non-traversable tile #{structure.tile_id}"
        assert cell.type not in ["ocean", "coast"], "Settlement on #{cell.type} tile"
      end
    end

    test "no two settlements on the same tile", %{structures: structures} do
      tile_ids = Enum.map(structures, & &1.tile_id)
      assert length(tile_ids) == length(Enum.uniq(tile_ids)), "Duplicate settlement tile IDs"
    end

    test "nation starting_tiles and troop_positions are updated", %{nations: nations} do
      for nation <- nations do
        # Should have more than just the capital tile
        assert length(nation.starting_tiles) >= 1

        # All starting tiles should have troop positions
        for tile_id <- nation.starting_tiles do
          assert Map.has_key?(nation.troop_positions, tile_id),
                 "#{nation.id} missing troop position for #{tile_id}"
        end
      end
    end

    test "structures have correct fields", %{structures: structures} do
      for s <- structures do
        assert is_binary(s.tile_id)
        assert is_binary(s.nation_id)
        assert s.type in ["capital", "major_city", "minor_city", "village"]
        assert is_float(s.condition) and s.condition > 0.0 and s.condition <= 1.0
        assert is_integer(s.tier) and s.tier in 1..4
        assert is_integer(s.population)
        assert is_list(s.flags)
      end
    end
  end
end
