defmodule Mentat.ScenarioLoader do
  @moduledoc """
  Loads and parses scenario JSON files for a given scenario name.

  Returns structured Elixir data from map.json, nations.json, and structures.json.
  Pure function — no processes, no ETS, no side effects.
  """

  @doc """
  Loads a scenario by name from priv/scenarios/:scenario_name/.

  Returns `{:ok, %{tiles: [...], nations: [...], structures: [...]}}` or `{:error, reason}`.
  """
  def load(scenario_name) do
    base_path = Path.join([:code.priv_dir(:mentat), "scenarios", scenario_name])

    with {:ok, map_data} <- read_json(Path.join(base_path, "map.json")),
         {:ok, nations_data} <- read_json(Path.join(base_path, "nations.json")),
         {:ok, structures_data} <- read_json(Path.join(base_path, "structures.json")) do
      {:ok,
       %{
         tiles: parse_tiles(map_data),
         nations: parse_nations(nations_data),
         structures: parse_structures(structures_data)
       }}
    end
  end

  defp read_json(path) do
    case File.read(path) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, data} -> {:ok, data}
          {:error, reason} -> {:error, {:json_decode, path, reason}}
        end

      {:error, reason} ->
        {:error, {:file_read, path, reason}}
    end
  end

  defp parse_tiles(%{"tiles" => tiles}) do
    Enum.map(tiles, &parse_tile/1)
  end

  defp parse_tile(tile) do
    %{
      id: tile["id"],
      type: tile["type"],
      x: tile["x"],
      y: tile["y"],
      adjacent: tile["adjacent"],
      river_edges: tile["river_edges"],
      resource: %{
        type: tile["resource"]["type"],
        base_amount: tile["resource"]["base_amount"]
      },
      traversable: tile["traversable"],
      movement_cost: tile["movement_cost"],
      defensive_bonus: tile["defensive_bonus"],
      cx: tile["cx"],
      cy: tile["cy"],
      polygon: tile["polygon"]
    }
  end

  defp parse_nations(%{"nations" => nations}) do
    Enum.map(nations, &parse_nation/1)
  end

  defp parse_nation(nation) do
    %{
      id: nation["id"],
      name: nation["name"],
      color: nation["color"],
      government_type: nation["government_type"],
      starting_tiles: nation["starting_tiles"],
      capital_tile_id: nation["capital_tile_id"],
      starting_resources: parse_string_key_map(nation["starting_resources"]),
      troop_positions: parse_string_key_map(nation["troop_positions"]),
      internal_stability: nation["internal_stability"],
      public_approval: nation["public_approval"],
      political_rules: Enum.map(nation["political_rules"], &parse_political_rule/1)
    }
  end

  defp parse_political_rule(rule) do
    %{
      action: rule["action"],
      requires: rule["requires"],
      resolves_in_ticks: rule["resolves_in_ticks"]
    }
  end

  defp parse_string_key_map(map) do
    Map.new(map, fn {k, v} -> {k, v} end)
  end

  defp parse_structures(%{"structures" => structures}) do
    Enum.map(structures, &parse_structure/1)
  end

  defp parse_structure(structure) do
    type = structure["type"]

    %{
      tile_id: structure["tile_id"],
      nation_id: structure["nation_id"],
      type: type,
      condition: structure["condition"],
      tier: structure["tier"] || Mentat.Settlement.infer_tier(type),
      population: structure["population"] || 0,
      flags: structure["flags"] || []
    }
  end
end
