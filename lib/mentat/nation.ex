defmodule Mentat.Nation do
  use GenServer
  require Logger

  alias Mentat.NationAgent.Combat
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
      starting_population: res["population"] || 10000,
      # War state: map of enemy_nation_id => %{started_tick, troops_at_declaration}
      wars: %{},
      # Pending war declaration awaiting political approval
      pending_war: nil
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
        |> step_war(tick_info)
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

  # War declaration received from another nation.
  # NOTE (v0 known lag): The declaring nation is at war one tick before the target
  # learns about it, because this message is processed asynchronously. Acceptable
  # for v0; fix in v0.1 with a synchronous call.
  @impl true
  def handle_info({:declare_war, from_nation_id, tick}, state) do
    Logger.warning("WAR DECLARED on #{state.id} by #{from_nation_id} at tick #{tick}")

    wars =
      Map.put(state.wars, from_nation_id, %{
        started_tick: tick,
        troops_at_declaration: state.troops
      })

    Mentat.PersistenceWorker.save_event(tick, :war_declared, state.id, %{
      declared_by: from_nation_id,
      target: state.id
    })

    {:noreply, %{state | wars: wars}}
  end

  # Peace declared by the other nation. May be a no-op if we already removed them
  # from our wars map (both sides can hit auto-peace in the same tick — harmless).
  @impl true
  def handle_info({:peace_declared, from_nation_id}, state) do
    {:noreply, %{state | wars: Map.delete(state.wars, from_nation_id)}}
  end

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

    # War penalty: -0.002 stability per active war
    war_penalty = map_size(state.wars) * 0.002

    stability =
      stability
      |> then(fn s -> if state.treasury < 0, do: s - 0.001, else: s end)
      |> then(fn s -> if state.grain < 50, do: s - 0.005, else: s end)
      |> then(fn s -> s - war_penalty end)
      |> max(0.0)
      |> min(1.0)

    # Approval drifts toward stability by 0.001 per tick
    approval =
      cond do
        approval < stability -> min(approval + 0.001, stability)
        approval > stability -> max(approval - 0.001, stability)
        true -> approval
      end

    # Conflict intensity decays toward 0
    conflict_intensity = max(0.0, state.conflict_intensity - 0.005)

    %{
      state
      | internal_stability: stability,
        public_approval: approval,
        conflict_intensity: conflict_intensity
    }
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

  # Step — War: process pending war declarations

  defp step_war(state, tick_info) do
    state = process_pending_war(state, tick_info)
    check_auto_peace(state, tick_info)
  end

  defp process_pending_war(state, tick_info) do
    case state.pending_war do
      nil ->
        state

      %{ticks_left: ticks_left} = pending when ticks_left <= 1 ->
        # War declaration resolves — add target to wars, notify target
        target_id = pending.target

        wars =
          Map.put(state.wars, target_id, %{
            started_tick: tick_info.tick,
            troops_at_declaration: pending.own_troops_at_declaration
          })

        Logger.warning("#{state.id} DECLARES WAR on #{target_id} at tick #{tick_info.tick}")

        Mentat.PersistenceWorker.save_event(tick_info.tick, :war_declared, state.id, %{
          declared_by: state.id,
          target: target_id
        })

        # Notify target asynchronously via Registry
        send_to_nation(target_id, {:declare_war, state.id, tick_info.tick})

        %{state | wars: wars, pending_war: nil}

      %{ticks_left: ticks_left} = pending ->
        %{state | pending_war: %{pending | ticks_left: ticks_left - 1}}
    end
  end

  # Auto-peace: end wars that have fizzled out or devastated troop levels.
  # If both nations hit auto-peace in the same tick, they each send {:peace_declared}
  # to the other. Map.delete on a key already removed is a no-op — intentional.
  defp check_auto_peace(state, tick_info) do
    {wars_to_end, wars_to_keep} =
      Enum.split_with(state.wars, fn {_enemy_id, detail} ->
        duration_elapsed = tick_info.tick - detail.started_tick >= 480
        low_intensity = state.conflict_intensity < 0.1
        troop_devastation = state.troops < detail.troops_at_declaration * 0.4

        (duration_elapsed and low_intensity) or troop_devastation
      end)

    if wars_to_end == [] do
      state
    else
      Enum.each(wars_to_end, fn {enemy_id, _detail} ->
        Logger.info("PEACE: #{state.id} ends war with #{enemy_id} at tick #{tick_info.tick}")

        Mentat.PersistenceWorker.save_event(tick_info.tick, :peace_treaty, state.id, %{
          nation_a: state.id,
          nation_b: enemy_id
        })

        send_to_nation(enemy_id, {:peace_declared, state.id})
      end)

      %{state | wars: Map.new(wars_to_keep)}
    end
  end

  defp initiate_war_declaration(state, target_id, _tick_info) do
    # Don't declare war if already at war or already pending
    if Map.has_key?(state.wars, target_id) || state.pending_war != nil do
      state
    else
      war_rule =
        Enum.find(state.ruleset.political_rules, fn r -> r.action == "declare_war" end)

      ticks = if war_rule, do: war_rule.resolves_in_ticks, else: 24

      %{
        state
        | pending_war: %{
            target: target_id,
            ticks_left: ticks,
            own_troops_at_declaration: state.troops
          }
      }
    end
  end

  defp send_to_nation(nation_id, message) do
    case Registry.lookup(Mentat.NationRegistry, nation_id) do
      [{pid, _}] -> send(pid, message)
      [] -> :ok
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
      oil: state.oil,
      iron: state.iron,
      rare_earth: state.rare_earth,
      troops: state.troops,
      capital_tile_id: state.capital_tile_id,
      troop_positions: state.troop_positions,
      tiles: tiles_map,
      wars: state.wars,
      pending_war: state.pending_war
    }

    case Mentat.NationAgent.FSM.decide(snapshot) do
      nil ->
        state

      %{type: :move_troops, from: from, to: to, count: count} ->
        execute_move(state, tick_info, from, to, count, tiles_map)

      %{type: :declare_war, target: target_id} ->
        initiate_war_declaration(state, target_id, tick_info)
    end
  end

  defp execute_move(state, tick_info, from, to, count, tiles_map) do
    from_troops = Map.get(state.troop_positions, from, 0)
    count = min(count, from_troops)

    if count <= 0 do
      state
    else
      # Update from-tile in ETS
      from_tile = Map.get(tiles_map, from)

      if from_tile do
        new_from_troops =
          from_tile.troops
          |> Map.update(state.id, 0, &(&1 - count))
          |> clean_zero_troops()

        Mentat.World.update_tile(from, %{troops: new_from_troops})
      end

      # Move troops to destination
      to_tile = Map.get(tiles_map, to)

      {state, new_positions} =
        if to_tile do
          execute_move_to_tile(state, tick_info, from, to, count, to_tile)
        else
          new_positions =
            state.troop_positions
            |> Map.update(from, 0, &(&1 - count))
            |> Map.update(to, count, &(&1 + count))

          {state, new_positions}
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

  defp execute_move_to_tile(state, tick_info, from, to, count, to_tile) do
    # Check for enemy troops on the destination tile
    enemy_troops_on_tile =
      state.wars
      |> Map.keys()
      |> Enum.map(fn enemy_id -> {enemy_id, Map.get(to_tile.troops, enemy_id, 0)} end)
      |> Enum.filter(fn {_id, troops} -> troops > 0 end)

    total_enemy = Enum.reduce(enemy_troops_on_tile, 0, fn {_id, t}, acc -> acc + t end)

    if total_enemy > 0 do
      # Battle! Resolve combat
      result = Combat.resolve_battle(count, total_enemy, to_tile)

      # Distribute defender losses proportionally across enemy nations
      enemy_updates =
        Enum.map(enemy_troops_on_tile, fn {enemy_id, enemy_count} ->
          proportion = enemy_count / total_enemy
          losses = round((total_enemy - result.defender_remaining) * proportion)
          {enemy_id, max(0, enemy_count - losses)}
        end)

      # Build updated troops map for the tile
      tile_troops =
        Enum.reduce(enemy_updates, to_tile.troops, fn {enemy_id, remaining}, acc ->
          if remaining > 0, do: Map.put(acc, enemy_id, remaining), else: Map.delete(acc, enemy_id)
        end)

      tile_troops =
        if result.attacker_remaining > 0 do
          Map.put(tile_troops, state.id, result.attacker_remaining)
        else
          Map.delete(tile_troops, state.id)
        end

      tile_troops = clean_zero_troops(tile_troops)

      tile_updates =
        if result.winner == :attacker do
          # Territory transfer: claim tile, damage structures
          previous_owner = to_tile.owner

          captured_structures =
            Enum.map(to_tile.structures, fn s ->
              new_condition = max(0.1, s.condition * 0.7)
              %{s | condition: new_condition, nation_id: state.id}
            end)

          Mentat.PersistenceWorker.save_event(tick_info.tick, :territory_conquered, state.id, %{
            tile_id: to,
            previous_owner: previous_owner,
            new_owner: state.id,
            structures_captured:
              Enum.map(captured_structures, fn s -> %{type: s.type, condition: s.condition} end)
          })

          %{troops: tile_troops, owner: state.id, structures: captured_structures}
        else
          %{troops: tile_troops}
        end

      Mentat.World.update_tile(to, tile_updates)

      # Emit battle event
      attacker_casualties = count - result.attacker_remaining
      defender_casualties = total_enemy - result.defender_remaining

      Mentat.PersistenceWorker.save_event(tick_info.tick, :battle, state.id, %{
        tile_id: to,
        attacker: state.id,
        defenders: Enum.map(enemy_troops_on_tile, fn {id, _} -> id end),
        attacker_casualties: attacker_casualties,
        defender_casualties: defender_casualties,
        winner: result.winner
      })

      # Update conflict intensity
      conflict_intensity = min(1.0, state.conflict_intensity + 0.1)
      state = %{state | conflict_intensity: conflict_intensity}

      new_positions =
        state.troop_positions
        |> Map.update(from, 0, &(&1 - count))
        |> then(fn pos ->
          if result.attacker_remaining > 0 do
            Map.put(pos, to, result.attacker_remaining)
          else
            Map.delete(pos, to)
          end
        end)

      {state, new_positions}
    else
      # No combat — normal move
      new_to_troops =
        to_tile.troops
        |> Map.update(state.id, count, &(&1 + count))

      updates = %{troops: new_to_troops}
      # Claim unowned tile
      updates = if to_tile.owner == nil, do: Map.put(updates, :owner, state.id), else: updates
      Mentat.World.update_tile(to, updates)

      new_positions =
        state.troop_positions
        |> Map.update(from, 0, &(&1 - count))
        |> Map.update(to, count, &(&1 + count))

      {state, new_positions}
    end
  end

  defp clean_zero_troops(troops_map) do
    Map.reject(troops_map, fn {_id, count} -> count <= 0 end)
  end

  # Step 6 — Persist

  defp step_persist(state, tick_info) do
    state = %{state | formal_status: if(map_size(state.wars) > 0, do: :at_war, else: :peace)}
    snapshot = Map.drop(state, [:world_run_id])
    Mentat.PersistenceWorker.save_snapshot(tick_info.tick, state.id, snapshot)

    if rem(tick_info.tick, 24) == 0 do
      tiles = Mentat.World.get_tiles_by_owner(state.id)
      Mentat.PersistenceWorker.save_tile_snapshots(tick_info.tick, tiles)
    end

    state
  end
end
