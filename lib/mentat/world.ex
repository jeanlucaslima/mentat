defmodule Mentat.World do
  use GenServer
  require Logger

  @tiles_table :world_tiles
  @nations_table :world_nations

  # Public API — direct ETS reads, no GenServer bottleneck

  def get_tile(tile_id) do
    case :ets.lookup(@tiles_table, tile_id) do
      [{^tile_id, tile}] -> tile
      [] -> nil
    end
  end

  def get_all_tiles do
    :ets.tab2list(@tiles_table) |> Enum.map(fn {_id, tile} -> tile end)
  end

  def get_tiles_by_owner(nation_id) do
    :ets.tab2list(@tiles_table)
    |> Enum.map(fn {_id, tile} -> tile end)
    |> Enum.filter(fn tile -> tile.owner == nation_id end)
  end

  def update_tile(tile_id, updates) do
    GenServer.call(__MODULE__, {:update_tile, tile_id, updates})
  end

  def reload(scenario) do
    GenServer.call(__MODULE__, {:reload, scenario})
  end

  def get_nation(nation_id) do
    case :ets.lookup(@nations_table, nation_id) do
      [{^nation_id, nation}] -> nation
      [] -> nil
    end
  end

  def get_all_nations do
    :ets.tab2list(@nations_table) |> Enum.map(fn {_id, nation} -> nation end)
  end

  # GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    scenario = Application.get_env(:mentat, :scenario, "world_01")

    case Mentat.ScenarioLoader.load(scenario) do
      {:ok, %{tiles: tiles, nations: nations, structures: structures}} ->
        :ets.new(@tiles_table, [:named_table, :set, :public, read_concurrency: true])
        :ets.new(@nations_table, [:named_table, :set, :public, read_concurrency: true])

        owner_map = build_owner_map(nations)
        structures_map = build_structures_map(structures)
        troops_map = build_troops_map(nations)

        Enum.each(tiles, fn tile ->
          enriched =
            Map.merge(tile, %{
              owner: Map.get(owner_map, tile.id),
              structures: Map.get(structures_map, tile.id, []),
              troops: Map.get(troops_map, tile.id, %{})
            })

          :ets.insert(@tiles_table, {tile.id, enriched})
        end)

        Enum.each(nations, fn nation ->
          :ets.insert(@nations_table, {nation.id, nation})
        end)

        Logger.info("World initialized: #{length(tiles)} tiles loaded")
        {:ok, %{}}

      {:error, reason} ->
        {:stop, reason}
    end
  end

  @impl true
  def handle_call({:reload, scenario}, _from, _state) do
    case Mentat.ScenarioLoader.load(scenario) do
      {:ok, %{tiles: tiles, nations: nations, structures: structures}} ->
        :ets.delete_all_objects(@tiles_table)
        :ets.delete_all_objects(@nations_table)

        owner_map = build_owner_map(nations)
        structures_map = build_structures_map(structures)
        troops_map = build_troops_map(nations)

        Enum.each(tiles, fn tile ->
          enriched =
            Map.merge(tile, %{
              owner: Map.get(owner_map, tile.id),
              structures: Map.get(structures_map, tile.id, []),
              troops: Map.get(troops_map, tile.id, %{})
            })

          :ets.insert(@tiles_table, {tile.id, enriched})
        end)

        Enum.each(nations, fn nation ->
          :ets.insert(@nations_table, {nation.id, nation})
        end)

        Logger.info("World reloaded: #{length(tiles)} tiles for scenario #{scenario}")
        {:reply, :ok, %{}}

      {:error, reason} ->
        {:reply, {:error, reason}, %{}}
    end
  end

  @impl true
  def handle_call({:update_tile, tile_id, updates}, _from, state) do
    case :ets.lookup(@tiles_table, tile_id) do
      [{^tile_id, tile}] ->
        updated = Map.merge(tile, updates)
        :ets.insert(@tiles_table, {tile_id, updated})
        {:reply, :ok, state}

      [] ->
        {:reply, {:error, :not_found}, state}
    end
  end

  # Private helpers

  defp build_owner_map(nations) do
    Enum.reduce(nations, %{}, fn nation, acc ->
      Enum.reduce(nation.starting_tiles, acc, fn tile_id, inner_acc ->
        Map.put(inner_acc, tile_id, nation.id)
      end)
    end)
  end

  defp build_structures_map(structures) do
    Enum.group_by(structures, & &1.tile_id)
  end

  defp build_troops_map(nations) do
    Enum.reduce(nations, %{}, fn nation, acc ->
      Enum.reduce(nation.troop_positions, acc, fn {tile_id, count}, inner_acc ->
        existing = Map.get(inner_acc, tile_id, %{})
        Map.put(inner_acc, tile_id, Map.put(existing, nation.id, count))
      end)
    end)
  end
end
