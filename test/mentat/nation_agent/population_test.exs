defmodule Mentat.NationAgent.PopulationTest do
  use ExUnit.Case, async: true

  alias Mentat.NationAgent.Population

  defp base_state(overrides \\ %{}) do
    Map.merge(
      %{
        population: 10000,
        base_birth_rate: 0.01,
        base_death_rate: 0.008,
        recruitment_rate: 0.02,
        max_troop_ratio: 0.05,
        migration_policy: %{
          "open_borders" => true,
          "refugee_policy" => "accept",
          "skilled_priority" => false
        },
        grain: 500,
        internal_stability: 0.7,
        troops: 300,
        treasury: 1000,
        famine_ticks: 0,
        conflict_intensity: 0.0,
        recent_coup: false
      },
      Map.new(overrides)
    )
  end

  describe "compute_effective_birth_rate/1" do
    test "returns boosted rate when grain sufficient and stability high" do
      state = base_state(grain: 500, internal_stability: 0.8)
      rate = Population.compute_effective_birth_rate(state)
      # base 0.01 + grain boost 0.002 + stability boost 0.001 = 0.013
      assert_in_delta rate, 0.013, 0.0001
    end

    test "returns reduced rate when grain low" do
      state = base_state(grain: 50, internal_stability: 0.5)
      rate = Population.compute_effective_birth_rate(state)
      # base 0.01 + grain penalty -0.003 = 0.007
      assert_in_delta rate, 0.007, 0.0001
    end

    test "returns reduced rate when stability low" do
      state = base_state(grain: 150, internal_stability: 0.3)
      rate = Population.compute_effective_birth_rate(state)
      # base 0.01 + stability penalty -0.002 = 0.008
      assert_in_delta rate, 0.008, 0.0001
    end

    test "returns reduced rate when troop ratio exceeds max" do
      state = base_state(troops: 600, max_troop_ratio: 0.05)
      # 600 / 10000 = 0.06 > 0.05
      rate = Population.compute_effective_birth_rate(state)

      # base 0.01 + grain boost 0.002 + stability 0.7 (not > 0.7, no boost) + troop penalty -0.001 = 0.011
      assert_in_delta rate, 0.011, 0.0001
    end

    test "never returns negative" do
      state = base_state(grain: 10, internal_stability: 0.1, troops: 600, max_troop_ratio: 0.05)
      rate = Population.compute_effective_birth_rate(state)
      assert rate >= 0.0
    end
  end

  describe "apply_population_change/1" do
    test "population grows under normal conditions" do
      state = base_state()
      result = Population.apply_population_change(state)
      assert result.population > state.population
    end

    test "population can decline under harsh conditions" do
      # Very low birth rate modifiers, normal death rate
      state =
        base_state(
          grain: 10,
          internal_stability: 0.1,
          base_birth_rate: 0.002,
          base_death_rate: 0.008
        )

      result = Population.apply_population_change(state)
      assert result.population < state.population
    end

    test "population cannot go below zero" do
      state = base_state(population: 1, base_birth_rate: 0.0, base_death_rate: 0.5)
      result = Population.apply_population_change(state)
      assert result.population >= 0
    end
  end

  describe "compute_emigration/1" do
    test "returns zero when stability above 0.5" do
      state = base_state(internal_stability: 0.6)
      assert Population.compute_emigration(state) == 0
    end

    test "returns zero when stability equals 0.5" do
      state = base_state(internal_stability: 0.5)
      assert Population.compute_emigration(state) == 0
    end

    test "returns positive when stability below 0.5" do
      state = base_state(internal_stability: 0.3)
      emigration = Population.compute_emigration(state)
      assert emigration > 0
    end

    test "spikes during famine" do
      state_no_famine = base_state(internal_stability: 0.3, famine_ticks: 0)
      state_famine = base_state(internal_stability: 0.3, famine_ticks: 10)

      emigration_normal = Population.compute_emigration(state_no_famine)
      emigration_famine = Population.compute_emigration(state_famine)

      assert emigration_famine == emigration_normal * 5
    end

    test "spikes when conflict intensity high" do
      state_no_conflict = base_state(internal_stability: 0.3, conflict_intensity: 0.0)
      state_conflict = base_state(internal_stability: 0.3, conflict_intensity: 0.6)

      emigration_normal = Population.compute_emigration(state_no_conflict)
      emigration_conflict = Population.compute_emigration(state_conflict)

      assert emigration_conflict == emigration_normal * 3
    end

    test "spikes during coup" do
      state_no_coup = base_state(internal_stability: 0.3, recent_coup: false)
      state_coup = base_state(internal_stability: 0.3, recent_coup: true)

      emigration_normal = Population.compute_emigration(state_no_coup)
      emigration_coup = Population.compute_emigration(state_coup)

      assert emigration_coup == emigration_normal * 5
    end

    test "cannot exceed population" do
      state =
        base_state(
          population: 10,
          internal_stability: 0.01,
          famine_ticks: 100,
          conflict_intensity: 1.0,
          recent_coup: true
        )

      emigration = Population.compute_emigration(state)
      assert emigration <= state.population
    end
  end

  describe "apply_emigration/2" do
    test "subtracts emigration from population" do
      state = base_state(population: 10000)
      result = Population.apply_emigration(state, 500)
      assert result.population == 9500
    end

    test "population cannot go below zero" do
      state = base_state(population: 100)
      result = Population.apply_emigration(state, 200)
      assert result.population == 0
    end
  end

  describe "refill_troops/1" do
    test "recruits when below cap and treasury positive" do
      state = base_state(population: 10000, troops: 100, max_troop_ratio: 0.05, treasury: 1000)
      # max troops = 500, recruits = 10000 * 0.02 = 200
      result = Population.refill_troops(state)
      assert result.troops == 300
    end

    test "respects troop cap" do
      state = base_state(population: 10000, troops: 490, max_troop_ratio: 0.05, treasury: 1000)
      # max troops = 500, room = 10, recruits would be 200 but capped at 10
      result = Population.refill_troops(state)
      assert result.troops == 500
    end

    test "does not recruit when treasury not positive" do
      state = base_state(population: 10000, troops: 100, max_troop_ratio: 0.05, treasury: -100)
      result = Population.refill_troops(state)
      assert result.troops == 100
    end

    test "demobilizes when over cap" do
      state = base_state(population: 5000, troops: 500, max_troop_ratio: 0.05)
      # max troops = 250, excess = 250, demob = 25
      result = Population.refill_troops(state)
      assert result.troops == 475
    end

    test "gradually reduces troops when population drops below cap" do
      state = base_state(population: 1000, troops: 200, max_troop_ratio: 0.05)
      # max troops = 50, excess = 150, demob = 15
      result = Population.refill_troops(state)
      assert result.troops < 200
      assert result.troops > 50
    end
  end

  describe "collapsed?/1" do
    test "returns true when population below 100" do
      assert Population.collapsed?(base_state(population: 99))
    end

    test "returns false when population at 100" do
      refute Population.collapsed?(base_state(population: 100))
    end

    test "returns false when population above 100" do
      refute Population.collapsed?(base_state(population: 5000))
    end
  end

  describe "default_migration_policy/1" do
    test "democracy is open and accepting" do
      policy = Population.default_migration_policy("democracy")
      assert policy["open_borders"] == true
      assert policy["refugee_policy"] == "accept"
    end

    test "military_junta is closed and rejecting" do
      policy = Population.default_migration_policy("military_junta")
      assert policy["open_borders"] == false
      assert policy["refugee_policy"] == "reject"
    end
  end

  describe "policy_acceptance_rate/1" do
    test "accept policy returns 1.0" do
      assert Population.policy_acceptance_rate(%{"refugee_policy" => "accept"}) == 1.0
    end

    test "restrict policy returns 0.5" do
      assert Population.policy_acceptance_rate(%{"refugee_policy" => "restrict"}) == 0.5
    end

    test "reject policy returns 0.2" do
      assert Population.policy_acceptance_rate(%{"refugee_policy" => "reject"}) == 0.2
    end
  end

  describe "compute_attraction_weight/1" do
    test "higher stability and grain produce higher weight" do
      high =
        Population.compute_attraction_weight(%{
          internal_stability: 0.9,
          grain: 500,
          migration_policy: %{"open_borders" => true, "refugee_policy" => "accept"}
        })

      low =
        Population.compute_attraction_weight(%{
          internal_stability: 0.3,
          grain: 100,
          migration_policy: %{"open_borders" => false, "refugee_policy" => "reject"}
        })

      assert high > low
    end

    test "open borders doubles the border factor" do
      open =
        Population.compute_attraction_weight(%{
          internal_stability: 0.5,
          grain: 250,
          migration_policy: %{"open_borders" => true}
        })

      closed =
        Population.compute_attraction_weight(%{
          internal_stability: 0.5,
          grain: 250,
          migration_policy: %{"open_borders" => false}
        })

      assert_in_delta open, closed * 2, 0.001
    end
  end
end
