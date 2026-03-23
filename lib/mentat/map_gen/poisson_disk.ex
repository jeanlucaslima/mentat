defmodule Mentat.MapGen.PoissonDisk do
  @moduledoc """
  Poisson disk sampling for placing points in a 2D bounded space.
  Guarantees minimum distance between all points.
  Deterministic: same seed produces the same point set.
  """

  @max_candidates 30

  @doc """
  Generates a list of `{x, y}` points within `[0, width] x [0, height]`
  with at least `min_distance` between any two points.
  """
  def sample(width, height, min_distance, seed) do
    rand_state = :rand.seed_s(:exsss, {seed, seed * 2 + 1, seed * 3 + 2})

    cell_size = min_distance / :math.sqrt(2)
    grid_w = ceil(width / cell_size)
    grid_h = ceil(height / cell_size)

    # Start with a point near the center
    {start_x, rand_state} = uniform(rand_state, width * 0.3, width * 0.7)
    {start_y, rand_state} = uniform(rand_state, height * 0.3, height * 0.7)
    start_point = {start_x, start_y}

    grid = %{grid_cell(start_point, cell_size) => 0}
    points = [start_point]
    active = [0]

    {final_points, _grid, _rand_state} =
      do_sample(
        points,
        active,
        grid,
        rand_state,
        width,
        height,
        min_distance,
        cell_size,
        grid_w,
        grid_h
      )

    Enum.reverse(final_points)
  end

  defp do_sample(points, [], grid, rand_state, _w, _h, _min_d, _cs, _gw, _gh) do
    {points, grid, rand_state}
  end

  defp do_sample(points, active, grid, rand_state, w, h, min_d, cs, gw, gh) do
    # Pick a random active point
    {active_idx_pos, rand_state} = uniform_int(rand_state, 0, length(active) - 1)
    point_idx = Enum.at(active, active_idx_pos)
    point = Enum.at(Enum.reverse(points), point_idx)

    {found, new_points, new_active, new_grid, rand_state} =
      try_candidates(
        point,
        points,
        active,
        grid,
        rand_state,
        w,
        h,
        min_d,
        cs,
        gw,
        gh,
        @max_candidates,
        false
      )

    if found do
      do_sample(new_points, new_active, new_grid, rand_state, w, h, min_d, cs, gw, gh)
    else
      # Remove this point from active list
      new_active = List.delete_at(active, active_idx_pos)
      do_sample(points, new_active, grid, rand_state, w, h, min_d, cs, gw, gh)
    end
  end

  defp try_candidates(
         _point,
         points,
         active,
         grid,
         rand_state,
         _w,
         _h,
         _min_d,
         _cs,
         _gw,
         _gh,
         0,
         _found
       ) do
    {false, points, active, grid, rand_state}
  end

  defp try_candidates(
         point,
         points,
         active,
         grid,
         rand_state,
         w,
         h,
         min_d,
         cs,
         gw,
         gh,
         remaining,
         _found
       ) do
    {px, py} = point

    # Generate random point in annulus [min_d, 2*min_d]
    {angle, rand_state} = uniform(rand_state, 0, 2 * :math.pi())
    {radius, rand_state} = uniform(rand_state, min_d, 2 * min_d)

    cx = px + radius * :math.cos(angle)
    cy = py + radius * :math.sin(angle)

    if cx >= 0 and cx < w and cy >= 0 and cy < h and
         not has_nearby?({cx, cy}, grid, points, min_d, cs, gw, gh) do
      new_idx = length(points)
      new_points = [{cx, cy} | points]
      new_grid = Map.put(grid, grid_cell({cx, cy}, cs), new_idx)
      new_active = [new_idx | active]
      {true, new_points, new_active, new_grid, rand_state}
    else
      try_candidates(
        point,
        points,
        active,
        grid,
        rand_state,
        w,
        h,
        min_d,
        cs,
        gw,
        gh,
        remaining - 1,
        false
      )
    end
  end

  defp has_nearby?({cx, cy}, grid, points, min_d, cs, gw, gh) do
    {gx, gy} = grid_cell({cx, cy}, cs)
    points_reversed = Enum.reverse(points)
    min_d_sq = min_d * min_d

    Enum.any?(-2..2, fn dx ->
      Enum.any?(-2..2, fn dy ->
        nx = gx + dx
        ny = gy + dy

        if nx >= 0 and nx < gw and ny >= 0 and ny < gh do
          case Map.get(grid, {nx, ny}) do
            nil ->
              false

            idx ->
              {px, py} = Enum.at(points_reversed, idx)
              dist_sq = (cx - px) * (cx - px) + (cy - py) * (cy - py)
              dist_sq < min_d_sq
          end
        else
          false
        end
      end)
    end)
  end

  defp grid_cell({x, y}, cell_size) do
    {floor(x / cell_size), floor(y / cell_size)}
  end

  defp uniform(rand_state, min_val, max_val) do
    {val, new_state} = :rand.uniform_s(rand_state)
    {min_val + val * (max_val - min_val), new_state}
  end

  defp uniform_int(rand_state, min_val, max_val) when min_val == max_val do
    {min_val, rand_state}
  end

  defp uniform_int(rand_state, min_val, max_val) do
    {val, new_state} = :rand.uniform_s(max_val - min_val + 1, rand_state)
    {min_val + val - 1, new_state}
  end
end
