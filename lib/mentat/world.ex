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

  def submit_emigration(nation_id, amount) do
    GenServer.cast(__MODULE__, {:submit_emigration, nation_id, amount})
  end

  def collect_and_distribute_migration do
    GenServer.call(__MODULE__, :collect_and_distribute_migration, 10_000)
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
        {:ok, %{emigration_buffer: %{}}}

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
        {:reply, :ok, %{emigration_buffer: %{}}}

      {:error, reason} ->
        {:reply, {:error, reason}, %{emigration_buffer: %{}}}
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

  def handle_call(:collect_and_distribute_migration, _from, state) do
    distribute_migration(state.emigration_buffer)
    {:reply, :ok, %{state | emigration_buffer: %{}}}
  end

  @impl true
  def handle_cast({:submit_emigration, nation_id, amount}, state) do
    buffer = Map.update(state.emigration_buffer, nation_id, amount, &(&1 + amount))
    {:noreply, %{state | emigration_buffer: buffer}}
  end

  defp distribute_migration(buffer) when map_size(buffer) == 0, do: :ok

  defp distribute_migration(buffer) do
    alias Mentat.NationAgent.Population

    total_pool = buffer |> Map.values() |> Enum.sum()
    if total_pool <= 0, do: throw(:done)

    source_ids = Map.keys(buffer)
    nations = get_all_nations()

    weights =
      nations
      |> Enum.reject(fn n -> n.id in source_ids end)
      |> Enum.map(fn n ->
        nation_state = try_get_nation_state(n.id)

        if nation_state do
          weight = Population.compute_attraction_weight(nation_state)
          policy = Map.get(nation_state, :migration_policy, %{})
          cap = Population.policy_acceptance_rate(policy)
          {n.id, weight, cap}
        else
          nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.filter(fn {_id, w, _cap} -> w > 0 end)

    total_weight = Enum.reduce(weights, 0.0, fn {_, w, _}, acc -> acc + w end)

    if total_weight > 0 do
      Enum.each(weights, fn {nation_id, weight, cap} ->
        share = round(total_pool * (weight / total_weight) * cap)

        if share > 0 do
          send_immigration(nation_id, share)
        end
      end)
    end
  catch
    :done -> :ok
  end

  defp try_get_nation_state(nation_id) do
    Mentat.Nation.get_state(nation_id)
  catch
    :exit, _ -> nil
  end

  defp send_immigration(nation_id, amount) do
    case Registry.lookup(Mentat.NationRegistry, nation_id) do
      [{pid, _}] -> send(pid, {:immigration, amount})
      [] -> :ok
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
