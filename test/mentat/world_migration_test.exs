defmodule Mentat.WorldMigrationTest do
  use ExUnit.Case, async: true

  alias Mentat.NationAgent.Population

  describe "attraction weight computation" do
    test "weights computed correctly for stable, grain-rich, open nation" do
      state = %{
        internal_stability: 0.8,
        grain: 400,
        migration_policy: %{"open_borders" => true, "refugee_policy" => "accept"}
      }

      weight = Population.compute_attraction_weight(state)
      # stability 0.8 * grain_factor min(400/500, 1.0)=0.8 * border_factor 1.0 = 0.64
      assert_in_delta weight, 0.64, 0.01
    end

    test "weights computed correctly for unstable, grain-poor, closed nation" do
      state = %{
        internal_stability: 0.2,
        grain: 50,
        migration_policy: %{"open_borders" => false, "refugee_policy" => "reject"}
      }

      weight = Population.compute_attraction_weight(state)
      # stability 0.2 * grain_factor min(50/500, 1.0)=0.1 * border_factor 0.5 = 0.01
      assert_in_delta weight, 0.01, 0.001
    end

    test "grain factor caps at 1.0" do
      state = %{
        internal_stability: 1.0,
        grain: 1000,
        migration_policy: %{"open_borders" => true}
      }

      weight = Population.compute_attraction_weight(state)
      # stability 1.0 * grain_factor 1.0 * border_factor 1.0 = 1.0
      assert_in_delta weight, 1.0, 0.001
    end
  end

  describe "policy acceptance rate" do
    test "reject policy still passes 20% through" do
      rate = Population.policy_acceptance_rate(%{"refugee_policy" => "reject"})
      assert rate == 0.2
    end

    test "restrict policy halves immigration" do
      rate = Population.policy_acceptance_rate(%{"refugee_policy" => "restrict"})
      assert rate == 0.5
    end

    test "accept policy allows full immigration" do
      rate = Population.policy_acceptance_rate(%{"refugee_policy" => "accept"})
      assert rate == 1.0
    end
  end

  describe "emigration multipliers" do
    test "famine multiplier applied correctly" do
      base = %{
        population: 10000,
        internal_stability: 0.2,
        famine_ticks: 0,
        conflict_intensity: 0.0,
        recent_coup: false
      }

      famine = %{base | famine_ticks: 10}

      base_emigration = Population.compute_emigration(base)
      famine_emigration = Population.compute_emigration(famine)

      assert famine_emigration == base_emigration * 5
    end

    test "conflict multiplier applied correctly" do
      base = %{
        population: 10000,
        internal_stability: 0.2,
        famine_ticks: 0,
        conflict_intensity: 0.0,
        recent_coup: false
      }

      conflict = %{base | conflict_intensity: 0.8}

      base_emigration = Population.compute_emigration(base)
      conflict_emigration = Population.compute_emigration(conflict)

      assert conflict_emigration == base_emigration * 3
    end

    test "combined multipliers stack" do
      base = %{
        population: 10000,
        internal_stability: 0.2,
        famine_ticks: 0,
        conflict_intensity: 0.0,
        recent_coup: false
      }

      combined = %{base | famine_ticks: 10, conflict_intensity: 0.8, recent_coup: true}

      base_emigration = Population.compute_emigration(base)
      combined_emigration = Population.compute_emigration(combined)

      assert combined_emigration == base_emigration * 5 * 3 * 5
    end
  end
end
