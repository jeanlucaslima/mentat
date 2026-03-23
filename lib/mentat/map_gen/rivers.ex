defmodule Mentat.MapGen.Rivers do
  @moduledoc """
  Traces rivers from high-elevation land tiles downhill to the coast.
  River edges are bidirectional: if A has river_edge to B, B has river_edge to A.
  """

  @doc """
  Generates `count` rivers on the map. Returns cells with `:river_edges` populated.
  """
  def generate(cells, count, seed) do
    rand_state = :rand.seed_s(:exsss, {seed + 200, seed * 7 + 3, seed * 11 + 5})

    cells_map = Map.new(cells, fn c -> {c.index, c} end)

    # Find high-elevation land tiles as starting candidates
    land_cells =
      cells
      |> Enum.filter(fn c -> c.type not in ["ocean", "coast"] end)
      |> Enum.sort_by(fn c -> -c.elevation end)

    # Pick starting tiles from the top 15% of elevation
    top_count = max(1, round(length(land_cells) * 0.15))
    candidates = Enum.take(land_cells, top_count)

    {rivers, _rand} =
      Enum.reduce(1..count, {[], rand_state}, fn _i, {acc_rivers, rs} ->
        # Pick a random start from candidates, avoiding ones already used
        used_starts = Enum.flat_map(acc_rivers, fn r -> [hd(r)] end) |> MapSet.new()
        available = Enum.reject(candidates, fn c -> MapSet.member?(used_starts, c.index) end)

        if available == [] do
          {acc_rivers, rs}
        else
          {idx, rs} = random_index(rs, length(available))
          start_cell = Enum.at(available, idx)
          path = trace_river(start_cell.index, cells_map)
          {[path | acc_rivers], rs}
        end
      end)

    # Convert river paths to bidirectional river_edges on cells
    river_edges = build_river_edges(rivers)

    Enum.map(cells, fn cell ->
      Map.put(cell, :river_edges, Map.get(river_edges, cell.index, []))
    end)
  end

  @doc """
  Traces a river path downhill from start_index.
  Returns a list of cell indices forming the path.
  """
  def trace_river(start_index, cells_map) do
    do_trace(start_index, cells_map, MapSet.new(), [start_index])
  end

  defp do_trace(current, cells_map, visited, path) do
    cell = Map.fetch!(cells_map, current)
    visited = MapSet.put(visited, current)

    # Find unvisited adjacent cell with lowest elevation
    next =
      cell.adjacent
      |> Enum.reject(fn adj -> MapSet.member?(visited, adj) end)
      |> Enum.map(fn adj -> {adj, Map.get(cells_map, adj)} end)
      |> Enum.reject(fn {_adj, c} -> is_nil(c) end)
      |> Enum.sort_by(fn {_adj, c} -> c.elevation end)
      |> List.first()

    case next do
      nil ->
        # Dead end
        Enum.reverse(path)

      {next_idx, next_cell} ->
        new_path = [next_idx | path]

        if next_cell.type in ["ocean", "coast"] do
          # Reached the coast, river ends
          Enum.reverse(new_path)
        else
          do_trace(next_idx, cells_map, visited, new_path)
        end
    end
  end

  defp build_river_edges(rivers) do
    Enum.reduce(rivers, %{}, fn path, acc ->
      pairs = Enum.zip(path, tl(path))

      Enum.reduce(pairs, acc, fn {a, b}, edges ->
        edges
        |> Map.update(a, [b], fn existing ->
          if b in existing, do: existing, else: [b | existing]
        end)
        |> Map.update(b, [a], fn existing ->
          if a in existing, do: existing, else: [a | existing]
        end)
      end)
    end)
  end

  defp random_index(rand_state, max) do
    {val, rs} = :rand.uniform_s(max, rand_state)
    {val - 1, rs}
  end
end
