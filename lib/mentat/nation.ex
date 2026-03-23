defmodule Mentat.Nation do
  use GenServer
  require Logger

  alias Mentat.NationAgent.Population

  @government_flip %{
    "democracy" => "military_junta",
    "autocracy" => "democracy",
    "constitutional_monarchy" => "oligarchy",
    "oligarchy" => "military_junta",
    "military_junta" => "autocracy"
  }

  # Public API

  def get_state(nation_id) do
    GenServer.call(via_tuple(nation_id), :get_state)
  end

  def start_link({nation_id, world_run_id}) do
    GenServer.start_link(__MODULE__, {nation_id, world_run_id}, name: via_tuple(nation_id))
  end

  defp via_tuple(nation_id) do
    {:via, Registry, {Mentat.NationRegistry, nation_id}}
  end

  # GenServer

  @impl true
  def init({nation_id, world_run_id}) do
    nation = Mentat.World.get_nation(nation_id)
    Phoenix.PubSub.subscribe(Mentat.PubSub, "world:tick")

    res = nation.starting_resources

    default_policy = %{
      "open_borders" => true,
      "refugee_policy" => "accept",
      "skilled_priority" => false
    }

    state = %{
      id: nation_id,
      grain: res["grain"] || 0,
      oil: res["oil"] || 0,
      iron: res["iron"] || 0,
      rare_earth: res["rare_earth"] || 0,
      treasury: res["treasury"] || 0,
      troops: res["troops"] || 0,
      internal_stability: nation.internal_stability / 100.0,
      public_approval: nation.public_approval / 100.0,
      government: nation.government_type,
      formal_status: :peace,
      conflict_intensity: 0.0,
      ruleset: %{political_rules: nation.political_rules},
      famine_ticks: 0,
      capital_tile_id: nation.capital_tile_id,
      troop_positions: nation.troop_positions,
      world_run_id: world_run_id,
      population: res["population"] || 10000,
      base_birth_rate: res["base_birth_rate"] || 0.01,
      base_death_rate: res["base_death_rate"] || 0.008,
      recruitment_rate: res["recruitment_rate"] || 0.02,
      max_troop_ratio: res["max_troop_ratio"] || 0.05,
      migration_policy: res["migration_policy"] || default_policy,
      recent_coup: false,
      starting_population: res["population"] || 10000
    }

    Logger.info("Nation #{nation_id} started")
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info({:tick, tick_info}, state) do
    try do
      state =
        state
        |> step_resources(tick_info)
        |> step_stability()
        |> step_triggers(tick_info)
        |> step_population(tick_info)
        |> step_agent(tick_info)
        |> step_persist(tick_info)

      {:noreply, state}
    catch
      {:collapse, final_state} -> {:stop, :normal, final_state}
    end
  end

  @impl true
  def handle_info({:immigration, amount}, state) when is_number(amount) and amount > 0 do
    stability_cost = if amount > state.population * 0.01, do: 0.01, else: 0.0
    new_stability = max(0.0, state.internal_stability - stability_cost)

    {:noreply,
     %{state | population: state.population + amount, internal_stability: new_stability}}
  end

  def handle_info({:immigration, _amount}, state), do: {:noreply, state}

  @impl true
  def handle_info({:nation_collapsed, _nation_id}, state), do: {:noreply, state}

  # Step 1 & 2 — Read tiles, update resources

  defp step_resources(state, _tick_info) do
    tiles = Mentat.World.get_tiles_by_owner(state.id)

    # Add production from each tile's resource
    state =
      Enum.reduce(tiles, state, fn tile, acc ->
        case tile.resource do
          %{type: type, base_amount: amount} when not is_nil(type) and amount > 0 ->
            key = String.to_existing_atom(type)
            Map.update!(acc, key, &(&1 + amount))

          _ ->
            acc
        end
      end)

    # Grain consumption and treasury
    grain_consumption = state.troops * 0.001

    grain_production =
      tiles
      |> Enum.filter(fn t -> t.resource.type == "grain" end)
      |> Enum.map(fn t -> t.resource.base_amount end)
      |> Enum.sum()

    treasury_change = (grain_production - grain_consumption) * 0.1

    %{
      state
      | grain: max(0, state.grain - grain_consumption),
        oil: max(0, state.oil),
        iron: max(0, state.iron),
        rare_earth: max(0, state.rare_earth),
        treasury: state.treasury + treasury_change
    }
  end

  # Step 3 — Update stability

  defp step_stability(state) do
    stability = state.internal_stability
    approval = state.public_approval

    stability =
      stability
      |> then(fn s -> if state.treasury < 0, do: s - 0.001, else: s end)
      |> then(fn s -> if state.grain < 50, do: s - 0.005, else: s end)
      |> max(0.0)
      |> min(1.0)

    # Approval drifts toward stability by 0.001 per tick
    approval =
      cond do
        approval < stability -> min(approval + 0.001, stability)
        approval > stability -> max(approval - 0.001, stability)
        true -> approval
      end

    %{state | internal_stability: stability, public_approval: approval}
  end

  # Step 4 — Check passive event triggers

  defp step_triggers(state, tick_info) do
    state
    |> check_famine(tick_info)
    |> check_coup(tick_info)
    |> check_default(tick_info)
  end

  defp check_famine(state, tick_info) do
    if state.grain < 50 do
      famine_ticks = state.famine_ticks + 1

      if famine_ticks >= 120 do
        Logger.warning("FAMINE in #{state.id} at tick #{tick_info.tick}")

        Mentat.PersistenceWorker.save_event(
          tick_info.tick,
          :famine,
          state.id,
          %{}
        )

        %{
          state
          | grain: max(0, state.grain),
            public_approval: max(0.0, state.public_approval - 0.15),
            famine_ticks: 0
        }
      else
        %{state | famine_ticks: famine_ticks}
      end
    else
      %{state | famine_ticks: 0}
    end
  end

  defp check_coup(state, tick_info) do
    if state.internal_stability < 0.20 do
      old_gov = state.government
      new_gov = Map.get(@government_flip, old_gov, old_gov)

      Logger.warning("COUP in #{state.id}: #{old_gov} → #{new_gov} at tick #{tick_info.tick}")

      Mentat.PersistenceWorker.save_event(
        tick_info.tick,
        :coup,
        state.id,
        %{old_government: old_gov, new_government: new_gov}
      )

      %{
        state
        | government: new_gov,
          internal_stability: 0.20,
          recent_coup: true,
          migration_policy: Population.default_migration_policy(new_gov)
      }
    else
      state
    end
  end

  defp check_default(state, tick_info) do
    if state.treasury < 0 do
      Mentat.PersistenceWorker.save_event(
        tick_info.tick,
        :default,
        state.id,
        %{}
      )

      %{state | internal_stability: max(0.0, state.internal_stability - 0.05)}
    else
      state
    end
  end

  # Step 5 — Population lifecycle

  defp step_population(state, tick_info) do
    state = Population.apply_population_change(state)

    emigration = Population.compute_emigration(state)
    state = Population.apply_emigration(state, emigration)

    if emigration > 0 do
      Mentat.World.submit_emigration(state.id, emigration)
    end

    state = Population.refill_troops(state)

    if Population.collapsed?(state) do
      handle_collapse(state, tick_info)
    else
      %{state | recent_coup: false}
    end
  end

  defp handle_collapse(state, tick_info) do
    Logger.warning(
      "COLLAPSE: #{state.id} at tick #{tick_info.tick}, population #{state.population}"
    )

    # Unsubscribe immediately to prevent processing further ticks
    Phoenix.PubSub.unsubscribe(Mentat.PubSub, "world:tick")

    Mentat.PersistenceWorker.save_event(
      tick_info.tick,
      :nation_collapsed,
      state.id,
      %{population: state.population}
    )

    tiles = Mentat.World.get_tiles_by_owner(state.id)

    Enum.each(tiles, fn tile ->
      Mentat.World.update_tile(tile.id, %{owner: nil, troops: Map.delete(tile.troops, state.id)})
    end)

    Phoenix.PubSub.broadcast(Mentat.PubSub, "world:tick", {:nation_collapsed, state.id})

    snapshot = Map.drop(state, [:world_run_id])
    Mentat.PersistenceWorker.save_snapshot(tick_info.tick, state.id, snapshot)

    throw({:collapse, state})
  end

  # Step 6 — Agent decision

  defp step_agent(state, tick_info) do
    all_tiles = Mentat.World.get_all_tiles()
    tiles_map = Map.new(all_tiles, fn tile -> {tile.id, tile} end)

    snapshot = %{
      id: state.id,
      grain: state.grain,
      troops: state.troops,
      capital_tile_id: state.capital_tile_id,
      troop_positions: state.troop_positions,
      tiles: tiles_map
    }

    case Mentat.NationAgent.FSM.decide(snapshot) do
      nil ->
        state

      %{type: :move_troops, from: from, to: to, count: count} ->
        execute_move(state, tick_info, from, to, count, tiles_map)
    end
  end

  defp execute_move(state, tick_info, from, to, count, tiles_map) do
    from_troops = Map.get(state.troop_positions, from, 0)
    count = min(count, from_troops)

    if count <= 0 do
      state
    else
      # Update troop_positions in state
      new_positions =
        state.troop_positions
        |> Map.update(from, 0, &(&1 - count))
        |> Map.update(to, count, &(&1 + count))

      # Update ETS tiles — troops map on each tile
      from_tile = Map.get(tiles_map, from)
      to_tile = Map.get(tiles_map, to)

      if from_tile do
        new_from_troops = Map.update(from_tile.troops, state.id, 0, &(&1 - count))
        Mentat.World.update_tile(from, %{troops: new_from_troops})
      end

      if to_tile do
        new_to_troops = Map.update(to_tile.troops, state.id, count, &(&1 + count))
        updates = %{troops: new_to_troops}
        # Claim unowned tile
        updates = if to_tile.owner == nil, do: Map.put(updates, :owner, state.id), else: updates
        Mentat.World.update_tile(to, updates)
      end

      Mentat.PersistenceWorker.save_action(
        tick_info.tick,
        state.id,
        :move_troops,
        %{from: from, to: to, count: count},
        :executed
      )

      %{state | troop_positions: new_positions}
    end
  end

  # Step 6 — Persist

  defp step_persist(state, tick_info) do
    snapshot = Map.drop(state, [:world_run_id])
    Mentat.PersistenceWorker.save_snapshot(tick_info.tick, state.id, snapshot)

    if rem(tick_info.tick, 24) == 0 do
      tiles = Mentat.World.get_tiles_by_owner(state.id)
      Mentat.PersistenceWorker.save_tile_snapshots(tick_info.tick, tiles)
    end

    state
  end
end
