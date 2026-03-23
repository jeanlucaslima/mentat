defmodule Mentat.NationAgent.FSM do
  @moduledoc """
  Pure rule-based FSM agent for nation decision-making.

  Takes a snapshot of nation state and visible tiles.
  Returns one action map or nil. No GenServer, no ETS, no database.
  """

  @survival_grain_threshold 200
  @expansion_min_troops 200
  @capital_min_troops 1000

  @doc """
  Evaluates rules in priority order and returns the first matching action.

  Returns `%{type: :move_troops, from: tile_id, to: tile_id, count: count}` or `nil`.
  """
  def decide(%{troop_positions: positions}) when map_size(positions) == 0, do: nil

  def decide(snapshot) do
    rule_survival(snapshot) || rule_expansion(snapshot) || rule_consolidation(snapshot)
  end

  # Rule 1 — Survival: grain critically low, seek nearest grain tile not owned.
  # Prefer unclaimed grain tiles (claimable on arrival) over enemy-owned ones.
  defp rule_survival(%{grain: grain} = snapshot) when grain < @survival_grain_threshold do
    %{id: nation_id, tiles: tiles, troop_positions: positions, capital_tile_id: capital} =
      snapshot

    owned_tile_ids = Map.keys(positions)

    unclaimed_grain_fn = fn tile_id ->
      tile = Map.get(tiles, tile_id)

      tile && tile.resource.type == "grain" && tile.resource.base_amount > 0 &&
        tile.owner == nil
    end

    enemy_grain_fn = fn tile_id ->
      tile = Map.get(tiles, tile_id)

      tile && tile.resource.type == "grain" && tile.resource.base_amount > 0 &&
        tile.owner != nil && tile.owner != nation_id
    end

    with nil <- try_bfs_move(tiles, owned_tile_ids, unclaimed_grain_fn, positions, capital) do
      try_bfs_move(tiles, owned_tile_ids, enemy_grain_fn, positions, capital)
    end
  end

  defp rule_survival(_snapshot), do: nil

  # Rule 2 — Expansion: stable nation, claim nearest unclaimed tile
  defp rule_expansion(%{grain: grain, troops: troops} = snapshot)
       when grain >= @survival_grain_threshold and troops > @expansion_min_troops do
    %{tiles: tiles, troop_positions: positions, capital_tile_id: capital} = snapshot

    owned_tile_ids = Map.keys(positions)

    goal_fn = fn tile_id ->
      tile = Map.get(tiles, tile_id)
      tile && tile.owner == nil && tile.traversable
    end

    try_bfs_move(tiles, owned_tile_ids, goal_fn, positions, capital)
  end

  defp rule_expansion(_snapshot), do: nil

  # Rule 3 — Consolidation: troops spread thin, move excess toward capital
  defp rule_consolidation(snapshot) do
    %{troop_positions: positions, capital_tile_id: capital, tiles: tiles} = snapshot

    non_capital_tiles =
      positions
      |> Map.delete(capital)
      |> Enum.filter(fn {_tile_id, count} -> count > 0 end)

    if length(non_capital_tiles) > 3 do
      {source_tile_id, source_count} =
        Enum.min_by(non_capital_tiles, fn {_id, count} -> count end)

      case bfs_path(tiles, source_tile_id, capital) do
        nil ->
          nil

        path ->
          next_step = Enum.at(path, 1)

          if next_step do
            count = div(source_count, 2)
            count = max(count, 1)
            count = min(count, source_count)
            %{type: :move_troops, from: source_tile_id, to: next_step, count: count}
          else
            nil
          end
      end
    else
      nil
    end
  end

  defp try_bfs_move(tiles, start_ids, goal_fn, positions, capital) do
    case bfs_find(tiles, start_ids, goal_fn) do
      nil -> nil
      {_goal, path} -> build_move_action(path, positions, capital)
    end
  end

  # Build a move action from a BFS path. Picks the owned tile closest to the goal
  # with the most troops available.
  defp build_move_action(path, positions, capital) do
    # Path is [start, ..., goal]. Find the border: the last owned tile in the path.
    # The "from" tile is the last tile in the path that has troops.
    # The "to" tile is the next tile after it.
    {from, to_index} =
      path
      |> Enum.with_index()
      |> Enum.reverse()
      |> Enum.find(fn {tile_id, _idx} -> Map.has_key?(positions, tile_id) end)

    next_step = Enum.at(path, to_index + 1)

    if next_step do
      available = Map.get(positions, from, 0)

      available =
        if from == capital do
          max(0, available - @capital_min_troops)
        else
          available
        end

      count = div(available, 2)
      count = max(count, 1)
      count = min(count, available)

      if count > 0 do
        %{type: :move_troops, from: from, to: next_step, count: count}
      else
        nil
      end
    else
      nil
    end
  end

  @doc """
  BFS from multiple start tiles, returns `{goal_tile_id, path}` or `nil`.

  Only traverses tiles where `traversable` is `true`.
  """
  def bfs_find(tiles, start_tile_ids, goal_fn) do
    initial_queue = :queue.from_list(Enum.map(start_tile_ids, fn id -> {id, [id]} end))
    visited = MapSet.new(start_tile_ids)

    # Check if any start tile is already a goal
    case Enum.find(start_tile_ids, goal_fn) do
      nil -> do_bfs(tiles, initial_queue, visited, goal_fn)
      goal_id -> {goal_id, [goal_id]}
    end
  end

  defp do_bfs(tiles, queue, visited, goal_fn) do
    case :queue.out(queue) do
      {:empty, _} ->
        nil

      {{:value, {current, path}}, rest_queue} ->
        tile = Map.get(tiles, current)
        neighbors = if tile, do: tile.adjacent, else: []

        Enum.reduce_while(neighbors, {rest_queue, visited}, fn neighbor_id, {q, v} ->
          if MapSet.member?(v, neighbor_id) do
            {:cont, {q, v}}
          else
            neighbor_tile = Map.get(tiles, neighbor_id)

            if neighbor_tile && neighbor_tile.traversable do
              new_path = path ++ [neighbor_id]

              if goal_fn.(neighbor_id) do
                {:halt, {:found, neighbor_id, new_path}}
              else
                new_q = :queue.in({neighbor_id, new_path}, q)
                new_v = MapSet.put(v, neighbor_id)
                {:cont, {new_q, new_v}}
              end
            else
              v = MapSet.put(v, neighbor_id)
              {:cont, {q, v}}
            end
          end
        end)
        |> case do
          {:found, goal_id, goal_path} -> {goal_id, goal_path}
          {new_queue, new_visited} -> do_bfs(tiles, new_queue, new_visited, goal_fn)
        end
    end
  end

  @doc """
  BFS shortest path from source to target tile. Returns path list or nil.
  """
  def bfs_path(tiles, source, target) do
    case bfs_find(tiles, [source], fn id -> id == target end) do
      nil -> nil
      {_target, path} -> path
    end
  end
end
