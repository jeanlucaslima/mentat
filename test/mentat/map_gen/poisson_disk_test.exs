defmodule Mentat.MapGen.PoissonDiskTest do
  use ExUnit.Case, async: true

  alias Mentat.MapGen.PoissonDisk

  @width 800
  @height 600
  @min_distance 28
  @seed 42

  describe "sample/4" do
    setup do
      points = PoissonDisk.sample(@width, @height, @min_distance, @seed)
      %{points: points}
    end

    test "produces expected number of points", %{points: points} do
      count = length(points)
      assert count >= 300 and count <= 700, "Expected 300-700 points, got #{count}"
    end

    test "all points within bounds", %{points: points} do
      for {x, y} <- points do
        assert x >= 0 and x < @width, "x=#{x} out of bounds"
        assert y >= 0 and y < @height, "y=#{y} out of bounds"
      end
    end

    test "minimum distance respected between all pairs", %{points: points} do
      min_d_sq = @min_distance * @min_distance

      indexed = Enum.with_index(points)

      for {{x1, y1}, i} <- indexed, {{x2, y2}, j} <- indexed, i < j do
        dist_sq = (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)

        assert dist_sq >= min_d_sq * 0.99,
               "Points #{i} and #{j} too close: #{:math.sqrt(dist_sq)}"
      end
    end

    test "same seed produces same output" do
      a = PoissonDisk.sample(@width, @height, @min_distance, @seed)
      b = PoissonDisk.sample(@width, @height, @min_distance, @seed)
      assert a == b
    end

    test "different seeds produce different output" do
      a = PoissonDisk.sample(@width, @height, @min_distance, @seed)
      b = PoissonDisk.sample(@width, @height, @min_distance, 99)
      assert a != b
    end
  end
end
