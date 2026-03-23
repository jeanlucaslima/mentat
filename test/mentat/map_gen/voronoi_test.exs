defmodule Mentat.MapGen.VoronoiTest do
  use ExUnit.Case, async: true

  alias Mentat.MapGen.{PoissonDisk, Delaunay, Voronoi}

  @width 200.0
  @height 150.0

  setup do
    points = PoissonDisk.sample(@width, @height, 20, 42)
    triangles = Delaunay.triangulate(points)
    cells = Voronoi.from_delaunay(points, triangles, @width, @height)
    %{cells: cells, points: points}
  end

  describe "from_delaunay/4" do
    test "every point has a polygon", %{cells: cells, points: points} do
      assert length(cells) == length(points)

      for cell <- cells do
        assert length(cell.polygon) >= 3,
               "Cell #{cell.index} has #{length(cell.polygon)} vertices"
      end
    end

    test "every vertex of every polygon is within bounds", %{cells: cells} do
      for cell <- cells, {x, y} <- cell.polygon do
        assert x >= 0.0 and x <= @width,
               "Cell #{cell.index} vertex x=#{x} out of bounds [0, #{@width}]"

        assert y >= 0.0 and y <= @height,
               "Cell #{cell.index} vertex y=#{y} out of bounds [0, #{@height}]"
      end
    end

    test "centroids are inside bounding box", %{cells: cells} do
      for cell <- cells do
        assert cell.cx >= 0.0 and cell.cx <= @width
        assert cell.cy >= 0.0 and cell.cy <= @height
      end
    end

    test "adjacency is present", %{cells: cells} do
      for cell <- cells do
        assert is_list(cell.adjacent)
      end
    end
  end

  describe "clip_polygon/2" do
    test "clips polygon to bounds" do
      polygon = [{-10.0, 50.0}, {50.0, -10.0}, {110.0, 50.0}, {50.0, 110.0}]
      clipped = Voronoi.clip_polygon(polygon, {0.0, 0.0, 100.0, 100.0})

      for {x, y} <- clipped do
        assert x >= 0.0 and x <= 100.0
        assert y >= 0.0 and y <= 100.0
      end

      assert length(clipped) >= 3
    end
  end
end
