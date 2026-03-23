defmodule Mentat.Nation do
  use GenServer
  require Logger

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

  def start_link(nation_id) do
    GenServer.start_link(__MODULE__, nation_id, name: via_tuple(nation_id))
  end

  defp via_tuple(nation_id) do
    {:via, Registry, {Mentat.NationRegistry, nation_id}}
  end

  # GenServer

  @impl true
  def init(nation_id) do
    nation = Mentat.World.get_nation(nation_id)
    world_run_id = Mentat.PersistenceWorker.get_world_run_id()
    Phoenix.PubSub.subscribe(Mentat.PubSub, "world:tick")

    res = nation.starting_resources

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
      world_run_id: world_run_id
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
    state =
      state
      |> step_resources(tick_info)
      |> step_stability()
      |> step_triggers(tick_info)
      |> step_persist(tick_info)

    {:noreply, state}
  end

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

    %{state | grain: state.grain - grain_consumption, treasury: state.treasury + treasury_change}
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

      %{state | government: new_gov}
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

  # Step 5 — Persist

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
