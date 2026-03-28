defmodule Mentat.MapGen.Nations do
  @moduledoc """
  Places nation capitals on land tiles using max-min distance algorithm.
  Each nation owns only its capital tile.
  """

  @nation_templates [
    %{
      id: "nation_1",
      name: "Arvenia",
      color: "#4A90D9",
      government_type: "democracy",
      political_rules: [
        %{action: "declare_war", requires: ["parliamentary_vote"], resolves_in_ticks: 168},
        %{action: "increase_army", requires: ["budget_approval"], resolves_in_ticks: 48},
        %{action: "move_troops", requires: ["command_order"], resolves_in_ticks: 6}
      ]
    },
    %{
      id: "nation_2",
      name: "Korrath",
      color: "#D94A4A",
      government_type: "autocracy",
      political_rules: [
        %{action: "declare_war", requires: ["supreme_decree"], resolves_in_ticks: 24},
        %{action: "increase_army", requires: ["military_order"], resolves_in_ticks: 12},
        %{action: "move_troops", requires: ["direct_command"], resolves_in_ticks: 2}
      ]
    },
    %{
      id: "nation_3",
      name: "Valdris",
      color: "#D9A84A",
      government_type: "constitutional_monarchy",
      political_rules: [
        %{
          action: "declare_war",
          requires: ["royal_assent", "council_vote"],
          resolves_in_ticks: 72
        },
        %{action: "increase_army", requires: ["royal_assent"], resolves_in_ticks: 24},
        %{action: "move_troops", requires: ["military_dispatch"], resolves_in_ticks: 4}
      ]
    },
    %{
      id: "nation_4",
      name: "Thenmark",
      color: "#6B4AD9",
      government_type: "oligarchy",
      political_rules: [
        %{action: "declare_war", requires: ["council_majority"], resolves_in_ticks: 48},
        %{action: "increase_army", requires: ["treasury_allocation"], resolves_in_ticks: 24},
        %{action: "move_troops", requires: ["council_directive"], resolves_in_ticks: 4}
      ]
    },
    %{
      id: "nation_5",
      name: "Ironholt",
      color: "#4AD97A",
      government_type: "military_junta",
      political_rules: [
        %{action: "declare_war", requires: ["general_order"], resolves_in_ticks: 12},
        %{action: "increase_army", requires: ["conscription_order"], resolves_in_ticks: 6},
        %{action: "move_troops", requires: ["field_command"], resolves_in_ticks: 1}
      ]
    }
  ]

  @doc """
  Places `count` capitals on land tiles using max-min distance algorithm.
  Returns a list of nation maps ready for nations.json.
  """
  def place_capitals(cells, count \\ 5, seed) do
    rand_state = :rand.seed_s(:exsss, {seed + 300, seed * 13 + 1, seed * 17 + 9})

    land_cells =
      cells
      |> Enum.filter(fn c -> c.traversable end)
      |> Enum.reject(fn c -> c.type == "coast" end)

    if length(land_cells) < count do
      {:error, "Not enough land tiles for #{count} capitals"}
    else
      {capitals, _rand} = select_capitals(land_cells, count, rand_state)
      templates = Enum.take(@nation_templates, count)

      nations =
        Enum.zip(templates, capitals)
        |> Enum.map(fn {template, cell} ->
          tile_id = "t_#{cell.index}"

          Map.merge(template, %{
            starting_tiles: [tile_id],
            capital_tile_id: tile_id,
            starting_resources: starting_resources(),
            troop_positions: %{tile_id => 150},
            internal_stability: 70,
            public_approval: 65
          })
        end)

      {:ok, nations}
    end
  end

  defp select_capitals(land_cells, count, rand_state) do
    # First capital: random land tile
    {idx, rand_state} = random_index(rand_state, length(land_cells))
    first = Enum.at(land_cells, idx)

    Enum.reduce(2..count, {[first], rand_state}, fn _i, {selected, rs} ->
      # Find land tile that maximizes minimum distance to all selected
      best =
        land_cells
        |> Enum.reject(fn c -> Enum.any?(selected, fn s -> s.index == c.index end) end)
        |> Enum.max_by(fn candidate ->
          Enum.map(selected, fn s ->
            dx = candidate.cx - s.cx
            dy = candidate.cy - s.cy
            dx * dx + dy * dy
          end)
          |> Enum.min()
        end)

      {[best | selected], rs}
    end)
  end

  defp starting_resources do
    %{
      "grain" => 300,
      "oil" => 100,
      "iron" => 50,
      "rare_earth" => 0,
      "treasury" => 500,
      "troops" => 150,
      "population" => 800,
      "base_birth_rate" => 0.011,
      "base_death_rate" => 0.007,
      "recruitment_rate" => 0.018,
      "max_troop_ratio" => 0.05,
      "migration_policy" => %{
        "open_borders" => true,
        "refugee_policy" => "accept",
        "skilled_priority" => false
      }
    }
  end

  @doc """
  Places settlements around each nation's capital using BFS distance and tile scoring.

  Returns `{updated_nations, all_structures}` where structures includes both
  capitals and settlements. Each nation receives:
  - 1 major city (BFS distance 2-4)
  - 2 minor cities (BFS distance 3-6)
  - 3 villages (BFS distance 2-8)
  """
  def place_settlements(cells, nations) do
    cells_map = Map.new(cells, fn c -> {"t_#{c.index}", c} end)

    # Build adjacency map from cells (using tile IDs)
    adj_map =
      Map.new(cells, fn c ->
        {"t_#{c.index}", Enum.map(c.adjacent, fn a -> "t_#{a}" end)}
      end)

    # Track which tiles are already claimed by any nation
    claimed = MapSet.new(Enum.flat_map(nations, fn n -> n.starting_tiles end))

    # Track tiles that already have settlements (to enforce minimum distance)
    settlement_tiles = MapSet.new(Enum.map(nations, fn n -> n.capital_tile_id end))

    placement_specs = [
      {"major_city", 1, 2..4, 2},
      {"minor_city", 2, 3..6, 2},
      {"village", 3, 2..8, 1}
    ]

    {updated_nations, all_new_structures, _claimed, _settlement_tiles} =
      Enum.reduce(nations, {[], [], claimed, settlement_tiles}, fn nation,
                                                                   {nations_acc, structs_acc,
                                                                    claimed_acc, stiles_acc} ->
        # BFS outward from capital, collecting land tiles with distances
        tiles_by_distance = bfs_distances(adj_map, cells_map, nation.capital_tile_id)

        {nation_structs, new_starting_tiles, new_troop_positions, claimed_acc, stiles_acc} =
          Enum.reduce(
            placement_specs,
            {[], [], %{}, claimed_acc, stiles_acc},
            fn {type, count, distance_range, min_dist_to_settlement},
               {structs, tiles, troops, cl, st} ->
              {placed_structs, placed_tiles, placed_troops, cl, st} =
                place_n_of_type(
                  type,
                  count,
                  distance_range,
                  min_dist_to_settlement,
                  tiles_by_distance,
                  cells_map,
                  adj_map,
                  nation.id,
                  cl,
                  st
                )

              {structs ++ placed_structs, tiles ++ placed_tiles, Map.merge(troops, placed_troops),
               cl, st}
            end
          )

        updated_nation = %{
          nation
          | starting_tiles: nation.starting_tiles ++ new_starting_tiles,
            troop_positions: Map.merge(nation.troop_positions, new_troop_positions)
        }

        # Update starting troops count in resources
        total_new_troops = new_troop_positions |> Map.values() |> Enum.sum()

        updated_nation =
          Map.update!(updated_nation, :starting_resources, fn res ->
            Map.update!(res, "troops", &(&1 + total_new_troops))
          end)

        {nations_acc ++ [updated_nation], structs_acc ++ nation_structs, claimed_acc, stiles_acc}
      end)

    # Build capital structures
    capital_structures =
      Enum.map(updated_nations, fn n ->
        %{
          tile_id: n.capital_tile_id,
          nation_id: n.id,
          type: "capital",
          condition: 1.0,
          tier: 1,
          population: 0,
          flags: []
        }
      end)

    {updated_nations, capital_structures ++ all_new_structures}
  end

  defp place_n_of_type(
         type,
         count,
         distance_range,
         min_dist_to_settlement,
         tiles_by_distance,
         cells_map,
         adj_map,
         nation_id,
         claimed,
         settlement_tiles
       ) do
    troop_counts = %{"major_city" => 50, "minor_city" => 30, "village" => 10}
    troop_count = Map.get(troop_counts, type, 10)
    tier = Mentat.Settlement.infer_tier(type)

    # Filter candidates within distance range, not claimed, on traversable land
    candidates =
      tiles_by_distance
      |> Enum.filter(fn {_tile_id, dist} -> dist in distance_range end)
      |> Enum.reject(fn {tile_id, _dist} -> MapSet.member?(claimed, tile_id) end)
      |> Enum.filter(fn {tile_id, _dist} ->
        case Map.get(cells_map, tile_id) do
          nil -> false
          cell -> cell.traversable and cell.type not in ["ocean", "coast"]
        end
      end)
      |> Enum.filter(fn {tile_id, _dist} ->
        # Check minimum BFS distance to any existing settlement
        bfs_distance_to_nearest_settlement(adj_map, cells_map, tile_id, settlement_tiles) >=
          min_dist_to_settlement
      end)
      |> Enum.sort_by(
        fn {tile_id, _dist} ->
          cell = Map.get(cells_map, tile_id)
          score_tile(cell)
        end,
        :desc
      )

    # Take the top `count` candidates
    chosen = Enum.take(candidates, count)

    Enum.reduce(chosen, {[], [], %{}, claimed, settlement_tiles}, fn {tile_id, _dist},
                                                                     {structs, tiles, troops, cl,
                                                                      st} ->
      structure = %{
        tile_id: tile_id,
        nation_id: nation_id,
        type: type,
        condition: 1.0,
        tier: tier,
        population: 0,
        flags: []
      }

      {
        structs ++ [structure],
        tiles ++ [tile_id],
        Map.put(troops, tile_id, troop_count),
        MapSet.put(cl, tile_id),
        MapSet.put(st, tile_id)
      }
    end)
  end

  defp score_tile(cell) do
    resource_score =
      case cell do
        %{resource: %{base_amount: amount}} when is_number(amount) -> amount * 2
        _ -> 0
      end

    river_score = if length(Map.get(cell, :river_edges, [])) > 0, do: 15, else: 0
    terrain_score = if cell.type in ["plains", "coast"], do: 10, else: 0

    resource_score + river_score + terrain_score
  end

  defp bfs_distances(adj_map, cells_map, start_tile_id) do
    do_bfs_distances(
      :queue.from_list([{start_tile_id, 0}]),
      %{start_tile_id => 0},
      adj_map,
      cells_map
    )
  end

  defp do_bfs_distances(queue, distances, adj_map, cells_map) do
    case :queue.out(queue) do
      {:empty, _} ->
        distances

      {{:value, {current, dist}}, rest} ->
        neighbors = Map.get(adj_map, current, [])

        {new_queue, new_distances} =
          Enum.reduce(neighbors, {rest, distances}, fn neighbor, {q, d} ->
            if Map.has_key?(d, neighbor) do
              {q, d}
            else
              cell = Map.get(cells_map, neighbor)

              if cell && cell.traversable do
                {
                  :queue.in({neighbor, dist + 1}, q),
                  Map.put(d, neighbor, dist + 1)
                }
              else
                {q, d}
              end
            end
          end)

        do_bfs_distances(new_queue, new_distances, adj_map, cells_map)
    end
  end

  defp bfs_distance_to_nearest_settlement(adj_map, cells_map, start, settlement_tiles) do
    if MapSet.size(settlement_tiles) == 0 do
      999
    else
      do_bfs_nearest(
        :queue.from_list([{start, 0}]),
        MapSet.new([start]),
        adj_map,
        cells_map,
        settlement_tiles
      )
    end
  end

  defp do_bfs_nearest(queue, visited, adj_map, cells_map, settlement_tiles) do
    case :queue.out(queue) do
      {:empty, _} ->
        999

      {{:value, {current, dist}}, rest} ->
        neighbors = Map.get(adj_map, current, [])

        result =
          Enum.reduce_while(neighbors, {rest, visited}, fn neighbor, {q, v} ->
            if MapSet.member?(v, neighbor) do
              {:cont, {q, v}}
            else
              if MapSet.member?(settlement_tiles, neighbor) do
                {:halt, {:found, dist + 1}}
              else
                cell = Map.get(cells_map, neighbor)

                if cell && cell.traversable do
                  {:cont, {:queue.in({neighbor, dist + 1}, q), MapSet.put(v, neighbor)}}
                else
                  {:cont, {q, MapSet.put(v, neighbor)}}
                end
              end
            end
          end)

        case result do
          {:found, distance} ->
            distance

          {new_queue, new_visited} ->
            do_bfs_nearest(new_queue, new_visited, adj_map, cells_map, settlement_tiles)
        end
    end
  end

  defp random_index(rand_state, max) do
    {val, rs} = :rand.uniform_s(max, rand_state)
    {val - 1, rs}
  end
end
