defmodule Mentat.MapGen.DelaunayTest do
  use ExUnit.Case, async: true

  alias Mentat.MapGen.Delaunay

  describe "triangulate/1" do
    test "3 points produce 1 triangle" do
      points = [{0.0, 0.0}, {1.0, 0.0}, {0.5, 1.0}]
      triangles = Delaunay.triangulate(points)
      assert length(triangles) == 1
    end

    test "4 points produce 2 triangles" do
      points = [{0.0, 0.0}, {1.0, 0.0}, {1.0, 1.0}, {0.0, 1.0}]
      triangles = Delaunay.triangulate(points)
      assert length(triangles) == 2
    end

    test "all triangle indices are within range" do
      points = Enum.map(0..19, fn i -> {:math.cos(i * 0.3) * 10, :math.sin(i * 0.3) * 10} end)
      n = length(points)
      triangles = Delaunay.triangulate(points)

      for {a, b, c} <- triangles do
        assert a >= 0 and a < n
        assert b >= 0 and b < n
        assert c >= 0 and c < n
      end
    end
  end

  describe "adjacency/2" do
    test "adjacency is symmetric" do
      points = [{0.0, 0.0}, {1.0, 0.0}, {0.5, 1.0}, {1.5, 1.0}, {1.0, 2.0}]
      triangles = Delaunay.triangulate(points)
      adj = Delaunay.adjacency(triangles, length(points))

      for {idx, neighbors} <- adj, neighbor <- neighbors do
        assert MapSet.member?(Map.fetch!(adj, neighbor), idx),
               "#{idx} -> #{neighbor} but not #{neighbor} -> #{idx}"
      end
    end

    test "every point has at least one neighbor" do
      points = Enum.map(0..9, fn i -> {i * 10.0, rem(i, 3) * 10.0} end)
      triangles = Delaunay.triangulate(points)
      adj = Delaunay.adjacency(triangles, length(points))

      for {idx, neighbors} <- adj do
        assert MapSet.size(neighbors) >= 1, "Point #{idx} has no neighbors"
      end
    end
  end
end
