defmodule Mentat.MapGen.Writer do
  @moduledoc """
  Validates and writes generated scenario files to disk.
  """

  @doc """
  Validates the generated data and writes map.json, nations.json, and structures.json.
  `base_path` defaults to `priv/scenarios/`.
  """
  def write(name, cells, nations, base_path \\ default_base_path()) do
    with :ok <- validate(cells, nations) do
      dir = Path.join(base_path, name)
      File.mkdir_p!(dir)

      map_json = to_map_json(name, cells)
      nations_json = to_nations_json(nations)
      structures_json = to_structures_json(nations)

      File.write!(Path.join(dir, "map.json"), Jason.encode!(map_json, pretty: true))
      File.write!(Path.join(dir, "nations.json"), Jason.encode!(nations_json, pretty: true))
      File.write!(Path.join(dir, "structures.json"), Jason.encode!(structures_json, pretty: true))

      :ok
    end
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

  defp to_structures_json(nations) do
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

  defp default_base_path do
    Path.join(:code.priv_dir(:mentat), "scenarios")
  end
end
