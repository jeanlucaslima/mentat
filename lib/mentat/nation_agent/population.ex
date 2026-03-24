defmodule Mentat.NationAgent.Population do
  @moduledoc """
  Pure functions for population lifecycle calculations.
  No GenServer, no ETS, no side effects — snapshot in, result out.
  """

  @min_viable_population 100

  @government_migration_defaults %{
    "democracy" => %{
      "open_borders" => true,
      "refugee_policy" => "accept",
      "skilled_priority" => false
    },
    "autocracy" => %{
      "open_borders" => false,
      "refugee_policy" => "restrict",
      "skilled_priority" => true
    },
    "constitutional_monarchy" => %{
      "open_borders" => true,
      "refugee_policy" => "accept",
      "skilled_priority" => true
    },
    "oligarchy" => %{
      "open_borders" => false,
      "refugee_policy" => "restrict",
      "skilled_priority" => true
    },
    "military_junta" => %{
      "open_borders" => false,
      "refugee_policy" => "reject",
      "skilled_priority" => false
    }
  }

  def compute_effective_birth_rate(state) do
    grain_mod =
      cond do
        state.grain > 200 -> 0.002
        state.grain < 100 -> -0.003
        true -> 0.0
      end

    stability_mod =
      cond do
        state.internal_stability > 0.7 -> 0.001
        state.internal_stability < 0.4 -> -0.002
        true -> 0.0
      end

    troop_ratio = state.troops / max(state.population, 1)
    effective_ratio = effective_troop_ratio(state)
    troop_mod = if troop_ratio > effective_ratio, do: -0.001, else: 0.0

    max(0.0, state.base_birth_rate + grain_mod + stability_mod + troop_mod)
  end

  def apply_population_change(state) do
    effective_birth_rate = compute_effective_birth_rate(state)
    births = round(state.population * effective_birth_rate)
    deaths = round(state.population * state.base_death_rate)
    new_population = max(0, state.population + births - deaths)
    %{state | population: new_population}
  end

  def compute_emigration(state) do
    if state.internal_stability >= 0.5 do
      0
    else
      base = state.population * (0.5 - state.internal_stability) * 0.01
      famine_mult = if state.famine_ticks > 0, do: 5.0, else: 1.0
      conflict_mult = if state.conflict_intensity > 0.5, do: 3.0, else: 1.0
      coup_mult = if Map.get(state, :recent_coup, false), do: 5.0, else: 1.0
      emigration = round(base * famine_mult * conflict_mult * coup_mult)
      min(emigration, state.population)
    end
  end

  def apply_emigration(state, emigration_amount) do
    %{state | population: max(0, state.population - emigration_amount)}
  end

  def refill_troops(state) do
    max_troops = troop_cap(state)

    cond do
      state.troops > max_troops ->
        excess = state.troops - max_troops
        demob = max(1, div(excess, 10))
        %{state | troops: state.troops - demob}

      state.troops < max_troops and state.treasury > 0 ->
        recruits = round(state.population * state.recruitment_rate)
        recruits = min(recruits, max_troops - state.troops)
        %{state | troops: state.troops + recruits}

      true ->
        state
    end
  end

  def troop_cap(state) do
    round(effective_troop_ratio(state) * state.population)
  end

  def effective_troop_ratio(state) do
    tier_ratio =
      cond do
        state.population < 2_000 -> 0.25
        state.population < 10_000 -> 0.15
        state.population < 50_000 -> 0.08
        true -> 0.05
      end

    max(tier_ratio, state.max_troop_ratio)
  end

  def collapsed?(state) do
    state.population < @min_viable_population
  end

  def default_migration_policy(government_type) do
    Map.get(
      @government_migration_defaults,
      government_type,
      %{"open_borders" => false, "refugee_policy" => "restrict", "skilled_priority" => false}
    )
  end

  def policy_acceptance_rate(migration_policy) do
    refugee_policy =
      Map.get(migration_policy, "refugee_policy") ||
        Map.get(migration_policy, :refugee_policy, "restrict")

    case refugee_policy do
      "accept" -> 1.0
      "restrict" -> 0.5
      "reject" -> 0.2
      _ -> 0.5
    end
  end

  def open_borders?(migration_policy) do
    Map.get(migration_policy, "open_borders") ||
      Map.get(migration_policy, :open_borders, false)
  end

  def compute_attraction_weight(nation_state) do
    stability = Map.get(nation_state, :internal_stability, 0.5)
    grain = Map.get(nation_state, :grain, 200)
    policy = Map.get(nation_state, :migration_policy, %{})

    grain_factor = min(grain / 500.0, 1.0)
    border_factor = if open_borders?(policy), do: 1.0, else: 0.5

    stability * grain_factor * border_factor
  end
end
