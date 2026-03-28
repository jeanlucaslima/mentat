defmodule Mentat.MapGen.Writer do
  @moduledoc """
  Validates and writes generated scenario files to disk.
  """

  @doc """
  Validates the generated data and writes map.json, nations.json, and structures.json.
  `base_path` defaults to `priv/scenarios/`.
  """
  def write(name, cells, nations, opts \\ [])

  def write(name, cells, nations, opts) when is_list(opts) do
    base_path = Keyword.get(opts, :base_path, default_base_path())
    structures = Keyword.get(opts, :structures)

    with :ok <- validate(cells, nations) do
      dir = Path.join(base_path, name)
      File.mkdir_p!(dir)

      map_json = to_map_json(name, cells)
      nations_json = to_nations_json(nations)

      structures_json =
        if structures do
          to_structures_json_from_list(structures)
        else
          to_structures_json_from_nations(nations)
        end

      File.write!(Path.join(dir, "map.json"), Jason.encode!(map_json, pretty: true))
      File.write!(Path.join(dir, "nations.json"), Jason.encode!(nations_json, pretty: true))
      File.write!(Path.join(dir, "structures.json"), Jason.encode!(structures_json, pretty: true))

      :ok
    end
  end

  # Backward-compatible: 4th arg is a string base_path
  def write(name, cells, nations, base_path) when is_binary(base_path) do
    write(name, cells, nations, base_path: base_path)
  end

  @doc """
  Validates generated data. Returns `:ok` or `{:error, reason}`.
  """
  def validate(cells, nations) do
    with :ok <- validate_bidirectional_adjacency(cells),
         :ok <- validate_capitals_on_land(cells, nations),
         :ok <- validate_unique_capitals(nations),
         :ok <- validate_no_isolated_land(cells),
         :ok <- validate_polygon_vertices(cells) do
      :ok
    end
  end

  defp validate_bidirectional_adjacency(cells) do
    cells_map = Map.new(cells, fn c -> {c.index, c} end)

    bad =
      Enum.find(cells, fn cell ->
        Enum.any?(cell.adjacent, fn adj ->
          case Map.get(cells_map, adj) do
            nil -> true
            adj_cell -> cell.index not in adj_cell.adjacent
          end
        end)
      end)

    if bad do
      {:error, "Non-bidirectional adjacency found at tile index #{bad.index}"}
    else
      :ok
    end
  end

  defp validate_capitals_on_land(cells, nations) do
    cells_map = Map.new(cells, fn c -> {"t_#{c.index}", c} end)

    bad =
      Enum.find(nations, fn nation ->
        case Map.get(cells_map, nation.capital_tile_id) do
          nil -> true
          cell -> not cell.traversable or cell.type == "ocean"
        end
      end)

    if bad do
      {:error, "Capital #{bad.capital_tile_id} for #{bad.name} is on a non-land tile"}
    else
      :ok
    end
  end

  defp validate_unique_capitals(nations) do
    capitals = Enum.map(nations, & &1.capital_tile_id)

    if length(capitals) == length(Enum.uniq(capitals)) do
      :ok
    else
      {:error, "Duplicate capital tile IDs found"}
    end
  end

  defp validate_no_isolated_land(cells) do
    cells_map = Map.new(cells, fn c -> {c.index, c} end)

    isolated =
      Enum.find(cells, fn cell ->
        if cell.traversable and cell.type != "ocean" do
          land_neighbors =
            Enum.filter(cell.adjacent, fn adj ->
              case Map.get(cells_map, adj) do
                nil -> false
                adj_cell -> adj_cell.traversable
              end
            end)

          land_neighbors == []
        else
          false
        end
      end)

    if isolated do
      {:error, "Isolated land tile found at index #{isolated.index}"}
    else
      :ok
    end
  end

  defp validate_polygon_vertices(cells) do
    bad =
      Enum.find(cells, fn cell ->
        n = length(cell.polygon)
        n < 3 or n > 12
      end)

    if bad do
      {:error, "Tile #{bad.index} has #{length(bad.polygon)} polygon vertices (expected 3-12)"}
    else
      :ok
    end
  end

  defp to_map_json(name, cells) do
    %{
      "id" => name,
      "name" => name,
      "description" => "Generated map: #{name}",
      "tiles" =>
        Enum.map(cells, fn cell ->
          tile_id = "t_#{cell.index}"

          %{
            "id" => tile_id,
            "type" => cell.type,
            "x" => round(cell.cx),
            "y" => round(cell.cy),
            "cx" => Float.round(cell.cx * 1.0, 2),
            "cy" => Float.round(cell.cy * 1.0, 2),
            "polygon" =>
              Enum.map(cell.polygon, fn {px, py} ->
                [Float.round(px * 1.0, 2), Float.round(py * 1.0, 2)]
              end),
            "adjacent" => Enum.map(cell.adjacent, fn adj -> "t_#{adj}" end),
            "river_edges" => Enum.map(Map.get(cell, :river_edges, []), fn adj -> "t_#{adj}" end),
            "resource" => %{
              "type" => get_in(cell, [:resource, :type]),
              "base_amount" => get_in(cell, [:resource, :base_amount]) || 0
            },
            "traversable" => cell.traversable,
            "movement_cost" => cell.movement_cost,
            "defensive_bonus" => cell.defensive_bonus
          }
        end)
    }
  end

  defp to_nations_json(nations) do
    %{
      "nations" =>
        Enum.map(nations, fn nation ->
          %{
            "id" => nation.id,
            "name" => nation.name,
            "color" => nation.color,
            "government_type" => nation.government_type,
            "starting_tiles" => nation.starting_tiles,
            "capital_tile_id" => nation.capital_tile_id,
            "starting_resources" => nation.starting_resources,
            "troop_positions" => nation.troop_positions,
            "internal_stability" => nation.internal_stability,
            "public_approval" => nation.public_approval,
            "political_rules" =>
              Enum.map(nation.political_rules, fn rule ->
                %{
                  "action" => rule.action,
                  "requires" => rule.requires,
                  "resolves_in_ticks" => rule.resolves_in_ticks
                }
              end)
          }
        end)
    }
  end

  defp to_structures_json_from_list(structures) do
    %{
      "structures" =>
        Enum.map(structures, fn s ->
          base = %{
            "tile_id" => s.tile_id,
            "nation_id" => s.nation_id,
            "type" => s.type,
            "condition" => s.condition
          }

          base
          |> maybe_put("tier", Map.get(s, :tier))
          |> maybe_put("population", Map.get(s, :population))
          |> maybe_put("flags", Map.get(s, :flags))
        end)
    }
  end

  defp to_structures_json_from_nations(nations) do
    %{
      "structures" =>
        Enum.map(nations, fn nation ->
          %{
            "tile_id" => nation.capital_tile_id,
            "nation_id" => nation.id,
            "type" => "capital",
            "condition" => 1.0
          }
        end)
    }
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, _key, 0), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp default_base_path do
    Path.join(:code.priv_dir(:mentat), "scenarios")
  end
end
