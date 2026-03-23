defmodule Mentat.MapGen.Voronoi do
  @moduledoc """
  Computes Voronoi polygons from Delaunay triangulation.
  Clips all polygons to the bounding box. Pure Elixir.
  """

  @doc """
  Computes Voronoi cells from points and their Delaunay triangulation.
  Returns a list of cell maps: `%{index: i, cx: x, cy: y, polygon: [{x,y},...], adjacent: [j,...]}`.
  All polygon vertices are strictly within [0, width] x [0, height].
  """
  def from_delaunay(points, triangles, width, height) do
    bounds = {0.0, 0.0, width * 1.0, height * 1.0}
    n = length(points)
    points_indexed = points |> Enum.with_index() |> Map.new(fn {p, i} -> {i, p} end)

    # Precompute circumcenters for all triangles
    circumcenters =
      triangles
      |> Enum.with_index()
      |> Map.new(fn {{a, b, c}, idx} ->
        pa = Map.fetch!(points_indexed, a)
        pb = Map.fetch!(points_indexed, b)
        pc = Map.fetch!(points_indexed, c)
        {idx, circumcenter(pa, pb, pc)}
      end)

    # Build point -> triangle index mapping
    point_triangles =
      triangles
      |> Enum.with_index()
      |> Enum.reduce(Map.new(0..(n - 1), fn i -> {i, []} end), fn {{a, b, c}, tri_idx}, acc ->
        acc
        |> Map.update!(a, &[tri_idx | &1])
        |> Map.update!(b, &[tri_idx | &1])
        |> Map.update!(c, &[tri_idx | &1])
      end)

    # Build adjacency from triangles
    adjacency = Mentat.MapGen.Delaunay.adjacency(triangles, n)

    Enum.map(0..(n - 1), fn i ->
      point = Map.fetch!(points_indexed, i)
      tri_indices = Map.get(point_triangles, i, [])

      # Collect circumcenters of triangles containing this point
      # Clamp individual vertices first to prevent wild values from breaking augmentation
      vertices =
        tri_indices
        |> Enum.map(fn ti -> Map.fetch!(circumcenters, ti) end)
        |> sort_vertices_ccw(point)

      # Clip to bounds (handles >= 3 vertices with Sutherland-Hodgman)
      polygon =
        if length(vertices) >= 3 do
          clip_polygon(vertices, bounds)
        else
          # For < 3 vertices, just clamp individual points
          {min_x, min_y, max_x, max_y} = bounds

          Enum.map(vertices, fn {x, y} ->
            {clamp(x, min_x, max_x), clamp(y, min_y, max_y)}
          end)
        end

      # For boundary cells, add relevant bounding box corners
      polygon = augment_boundary_polygon(polygon, point, bounds, points_indexed, n)

      # Re-clip after augmentation (corners/midpoints should be within bounds
      # but circumcenters that leaked through need clipping)
      polygon = clip_polygon(polygon, bounds)

      # Re-sort after augmentation and dedup very close vertices
      polygon =
        polygon
        |> dedup_close_vertices()
        |> sort_vertices_ccw(point)

      # Compute centroid
      {cx, cy} = centroid(polygon)

      adj = Map.get(adjacency, i, MapSet.new()) |> MapSet.to_list()

      %{
        index: i,
        cx: cx,
        cy: cy,
        polygon: polygon,
        adjacent: adj
      }
    end)
  end

  @doc """
  Computes the circumcenter of a triangle.
  """
  def circumcenter({ax, ay}, {bx, by}, {cx, cy}) do
    d = 2.0 * (ax * (by - cy) + bx * (cy - ay) + cx * (ay - by))

    if abs(d) < 1.0e-10 do
      {(ax + bx + cx) / 3.0, (ay + by + cy) / 3.0}
    else
      ux =
        ((ax * ax + ay * ay) * (by - cy) + (bx * bx + by * by) * (cy - ay) +
           (cx * cx + cy * cy) * (ay - by)) / d

      uy =
        ((ax * ax + ay * ay) * (cx - bx) + (bx * bx + by * by) * (ax - cx) +
           (cx * cx + cy * cy) * (bx - ax)) / d

      {ux, uy}
    end
  end

  @doc """
  Clips a polygon to a rectangular bounding box using Sutherland-Hodgman algorithm.
  Bounds are `{min_x, min_y, max_x, max_y}`.
  Ensures all output vertices are strictly within bounds (clamps floating point drift).
  """
  def clip_polygon(polygon, _bounds) when length(polygon) < 3, do: polygon

  def clip_polygon(polygon, {min_x, min_y, max_x, max_y}) do
    polygon
    |> clip_edge(fn {x, _y} -> x >= min_x end, fn p1, p2 -> intersect_x(p1, p2, min_x) end)
    |> clip_edge(fn {x, _y} -> x <= max_x end, fn p1, p2 -> intersect_x(p1, p2, max_x) end)
    |> clip_edge(fn {_x, y} -> y >= min_y end, fn p1, p2 -> intersect_y(p1, p2, min_y) end)
    |> clip_edge(fn {_x, y} -> y <= max_y end, fn p1, p2 -> intersect_y(p1, p2, max_y) end)
    |> Enum.map(fn {x, y} ->
      # Clamp to handle floating point drift
      {clamp(x, min_x, max_x), clamp(y, min_y, max_y)}
    end)
  end

  defp clip_edge(polygon, _inside?, _intersect) when length(polygon) < 1, do: polygon

  defp clip_edge(polygon, inside?, intersect) do
    pairs = Enum.zip(polygon, tl(polygon) ++ [hd(polygon)])

    Enum.flat_map(pairs, fn {p1, p2} ->
      p1_in = inside?.(p1)
      p2_in = inside?.(p2)

      cond do
        p1_in and p2_in -> [p2]
        p1_in and not p2_in -> [intersect.(p1, p2)]
        not p1_in and p2_in -> [intersect.(p1, p2), p2]
        true -> []
      end
    end)
  end

  defp intersect_x({x1, y1}, {x2, y2}, x) do
    t = (x - x1) / (x2 - x1 + 1.0e-20)
    {x, y1 + t * (y2 - y1)}
  end

  defp intersect_y({x1, y1}, {x2, y2}, y) do
    t = (y - y1) / (y2 - y1 + 1.0e-20)
    {x1 + t * (x2 - x1), y}
  end

  defp clamp(val, min_val, max_val) do
    val |> max(min_val) |> min(max_val)
  end

  # For boundary cells, add bounding box corners that are closest to this cell's point
  defp augment_boundary_polygon(polygon, {px, py}, {min_x, min_y, max_x, max_y}, all_points, n) do
    if length(polygon) >= 3,
      do: polygon,
      else: do_augment(polygon, px, py, min_x, min_y, max_x, max_y, all_points, n)
  end

  defp do_augment(polygon, px, py, min_x, min_y, max_x, max_y, all_points, n) do
    corners = [{min_x, min_y}, {max_x, min_y}, {max_x, max_y}, {min_x, max_y}]

    # Add corners that are closer to this point than to any other point
    extra =
      Enum.filter(corners, fn {cx, cy} ->
        my_dist = (cx - px) * (cx - px) + (cy - py) * (cy - py)

        not Enum.any?(0..(n - 1), fn j ->
          {jx, jy} = Map.fetch!(all_points, j)
          j_dist = (cx - jx) * (cx - jx) + (cy - jy) * (cy - jy)
          j_dist < my_dist - 1.0e-6
        end)
      end)

    # Also add midpoints of boundary edges if the cell touches the boundary
    boundary_mids =
      cond do
        px < (max_x - min_x) * 0.1 + min_x -> [{min_x, py}]
        px > max_x - (max_x - min_x) * 0.1 -> [{max_x, py}]
        true -> []
      end ++
        cond do
          py < (max_y - min_y) * 0.1 + min_y -> [{px, min_y}]
          py > max_y - (max_y - min_y) * 0.1 -> [{px, max_y}]
          true -> []
        end

    polygon ++ extra ++ boundary_mids
  end

  defp dedup_close_vertices(vertices) do
    Enum.reduce(vertices, [], fn v, acc ->
      if Enum.any?(acc, fn existing -> close?(v, existing) end) do
        acc
      else
        [v | acc]
      end
    end)
    |> Enum.reverse()
  end

  defp close?({x1, y1}, {x2, y2}) do
    (x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2) < 1.0
  end

  @doc """
  Sorts vertices counter-clockwise around a center point.
  """
  def sort_vertices_ccw(vertices, {cx, cy}) do
    Enum.sort_by(vertices, fn {vx, vy} ->
      :math.atan2(vy - cy, vx - cx)
    end)
  end

  @doc """
  Computes the centroid (average of all vertices) of a polygon.
  """
  def centroid([]), do: {0.0, 0.0}

  def centroid(polygon) do
    n = length(polygon)
    {sx, sy} = Enum.reduce(polygon, {0.0, 0.0}, fn {x, y}, {ax, ay} -> {ax + x, ay + y} end)
    {sx / n, sy / n}
  end
end
