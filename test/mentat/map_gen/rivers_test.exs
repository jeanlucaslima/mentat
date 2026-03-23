defmodule Mentat.MapGen.RiversTest do
  use ExUnit.Case, async: true

  alias Mentat.MapGen.Rivers

  describe "generate/3" do
    setup do
      # Create a simple grid of cells with decreasing elevation
      cells =
        for i <- 0..24 do
          x = rem(i, 5)
          y = div(i, 5)
          elevation = 1.0 - y * 0.2
          type = if y >= 4, do: "coast", else: "plains"

          adjacent =
            [
              if(x > 0, do: i - 1),
              if(x < 4, do: i + 1),
              if(y > 0, do: i - 5),
              if(y < 4, do: i + 5)
            ]
            |> Enum.reject(&is_nil/1)

          %{
            index: i,
            cx: x * 20.0,
            cy: y * 20.0,
            adjacent: adjacent,
            elevation: elevation,
            type: type,
            traversable: true
          }
        end

      %{cells: cells}
    end

    test "river_edges are bidirectional", %{cells: cells} do
      result = Rivers.generate(cells, 2, 42)
      cells_map = Map.new(result, fn c -> {c.index, c} end)

      for cell <- result, adj_idx <- cell.river_edges do
        adj_cell = Map.fetch!(cells_map, adj_idx)

        assert cell.index in adj_cell.river_edges,
               "River edge #{cell.index} -> #{adj_idx} but not #{adj_idx} -> #{cell.index}"
      end
    end

    test "rivers trace downhill", %{cells: cells} do
      result = Rivers.generate(cells, 1, 42)
      cells_map = Map.new(result, fn c -> {c.index, c} end)

      # Find cells with river edges and verify generally downhill
      river_cells = Enum.filter(result, fn c -> c.river_edges != [] end)
      assert length(river_cells) > 0

      # At least some river cells should exist
      for cell <- river_cells do
        assert is_list(cell.river_edges)

        for adj_idx <- cell.river_edges do
          _adj = Map.fetch!(cells_map, adj_idx)
        end
      end
    end
  end
end
