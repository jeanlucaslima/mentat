defmodule Mentat.MapGen.Delaunay do
  @moduledoc """
  Bowyer-Watson algorithm for Delaunay triangulation.
  Pure Elixir, no external dependencies.
  """

  @doc """
  Triangulates a list of `{x, y}` points using the Bowyer-Watson algorithm.
  Returns a list of `{i, j, k}` index triples representing triangles.
  Only returns triangles whose vertices are all original points (not super-triangle).
  """
  def triangulate(points) when length(points) < 3, do: []

  def triangulate(points) do
    indexed = points |> Enum.with_index() |> Enum.map(fn {p, i} -> {i, p} end) |> Map.new()
    n = length(points)

    # Create super-triangle that contains all points
    {st0, st1, st2} = super_triangle(points)
    super_points = %{n => st0, (n + 1) => st1, (n + 2) => st2}
    all_points = Map.merge(indexed, super_points)

    # Start with the super-triangle
    initial_triangles = [{n, n + 1, n + 2}]

    # Insert each point
    triangles =
      Enum.reduce(0..(n - 1), initial_triangles, fn i, tris ->
        point = Map.fetch!(all_points, i)
        insert_point(tris, i, point, all_points)
      end)

    # Remove triangles that share vertices with super-triangle
    triangles
    |> Enum.reject(fn {a, b, c} ->
      a >= n or b >= n or c >= n
    end)
  end

  @doc """
  Builds an adjacency map from triangles.
  Returns `%{point_index => MapSet.new([neighbor_indices])}`.
  """
  def adjacency(triangles, point_count) do
    base = Map.new(0..(point_count - 1), fn i -> {i, MapSet.new()} end)

    Enum.reduce(triangles, base, fn {a, b, c}, acc ->
      acc
      |> Map.update!(a, &MapSet.put(MapSet.put(&1, b), c))
      |> Map.update!(b, &MapSet.put(MapSet.put(&1, a), c))
      |> Map.update!(c, &MapSet.put(MapSet.put(&1, a), b))
    end)
  end

  @doc """
  Computes circumcircle of a triangle defined by three points.
  Returns `{cx, cy, radius_squared}`.
  """
  def circumcircle({ax, ay}, {bx, by}, {cx, cy}) do
    d = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))

    if abs(d) < 1.0e-10 do
      # Degenerate triangle (collinear points)
      mid_x = (ax + bx + cx) / 3.0
      mid_y = (ay + by + cy) / 3.0

      r_sq =
        max(
          dist_sq(ax, ay, mid_x, mid_y),
          max(dist_sq(bx, by, mid_x, mid_y), dist_sq(cx, cy, mid_x, mid_y))
        )

      {mid_x, mid_y, r_sq * 4.0}
    else
      ux =
        ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) +
           (cx * cx + cy * cy) * (ay - by)) / d

      uy =
        ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) +
           (cx * cx + cy * cy) * (bx - ax)) / d

      r_sq = dist_sq(ax, ay, ux, uy)
      {ux, uy, r_sq}
    end
  end

  # Private helpers

  defp super_triangle(points) do
    {min_x, max_x} = points |> Enum.map(&elem(&1, 0)) |> Enum.min_max()
    {min_y, max_y} = points |> Enum.map(&elem(&1, 1)) |> Enum.min_max()

    dx = max_x - min_x
    dy = max_y - min_y
    d_max = max(dx, dy) * 2.0
    mid_x = (min_x + max_x) / 2.0
    mid_y = (min_y + max_y) / 2.0

    {
      {mid_x - d_max * 2, mid_y - d_max},
      {mid_x + d_max * 2, mid_y - d_max},
      {mid_x, mid_y + d_max * 2}
    }
  end

  defp insert_point(triangles, point_idx, point, all_points) do
    # Find all triangles whose circumcircle contains the new point
    {bad, good} =
      Enum.split_with(triangles, fn {a, b, c} ->
        pa = Map.fetch!(all_points, a)
        pb = Map.fetch!(all_points, b)
        pc = Map.fetch!(all_points, c)
        {ccx, ccy, r_sq} = circumcircle(pa, pb, pc)
        dist_sq(elem(point, 0), elem(point, 1), ccx, ccy) < r_sq
      end)

    # Find the boundary edges of the polygonal hole
    boundary = find_boundary(bad)

    # Create new triangles by connecting boundary edges to the new point
    new_triangles = Enum.map(boundary, fn {e0, e1} -> {point_idx, e0, e1} end)

    good ++ new_triangles
  end

  defp find_boundary(bad_triangles) do
    edges =
      Enum.flat_map(bad_triangles, fn {a, b, c} ->
        [{a, b}, {b, c}, {a, c}]
      end)

    # An edge is on the boundary if it appears in exactly one bad triangle
    edge_counts =
      Enum.reduce(edges, %{}, fn edge, acc ->
        normalized = normalize_edge(edge)
        Map.update(acc, normalized, 1, &(&1 + 1))
      end)

    edges
    |> Enum.filter(fn edge ->
      Map.get(edge_counts, normalize_edge(edge)) == 1
    end)
    |> Enum.uniq_by(&normalize_edge/1)
  end

  defp normalize_edge({a, b}) when a <= b, do: {a, b}
  defp normalize_edge({a, b}), do: {b, a}

  defp dist_sq(x1, y1, x2, y2) do
    (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2)
  end
end
