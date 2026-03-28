defmodule Mentat.SettlementTest do
  use ExUnit.Case, async: true

  alias Mentat.Settlement

  describe "settlement?/1" do
    test "returns true for all settlement types" do
      assert Settlement.settlement?(%{type: "capital"})
      assert Settlement.settlement?(%{type: "major_city"})
      assert Settlement.settlement?(%{type: "minor_city"})
      assert Settlement.settlement?(%{type: "village"})
    end

    test "returns false for non-settlement types" do
      refute Settlement.settlement?(%{type: "fortress"})
      refute Settlement.settlement?(%{type: "unknown"})
    end
  end

  describe "tier_config/1" do
    test "returns config for known types" do
      config = Settlement.tier_config("capital")
      assert config.tier == 1
      assert config.production_multiplier == 2.0
      assert config.recruitment_bonus == 0.5
      assert config.stability_penalty == 0.30
      assert config.fsm_score == 500
    end

    test "returns nil for unknown types" do
      assert Settlement.tier_config("fortress") == nil
      assert Settlement.tier_config("unknown") == nil
    end
  end

  describe "production_multiplier/1" do
    test "returns highest settlement multiplier on tile" do
      tile = %{
        structures: [%{type: "capital", condition: 1.0}, %{type: "fortress", condition: 1.0}]
      }

      assert Settlement.production_multiplier(tile) == 2.0
    end

    test "returns 1.0 for tile with no settlements" do
      tile = %{structures: [%{type: "fortress", condition: 1.0}]}
      assert Settlement.production_multiplier(tile) == 1.0
    end

    test "returns 1.0 for tile with empty structures" do
      assert Settlement.production_multiplier(%{structures: []}) == 1.0
    end

    test "returns 1.0 for tile without structures key" do
      assert Settlement.production_multiplier(%{}) == 1.0
    end

    test "returns correct multiplier per tier" do
      assert Settlement.production_multiplier(%{
               structures: [%{type: "major_city", condition: 1.0}]
             }) == 1.5

      assert Settlement.production_multiplier(%{
               structures: [%{type: "minor_city", condition: 1.0}]
             }) == 1.2

      assert Settlement.production_multiplier(%{structures: [%{type: "village", condition: 1.0}]}) ==
               1.1
    end
  end

  describe "capture_stability_penalty/1" do
    test "returns correct penalties per tier" do
      assert Settlement.capture_stability_penalty("capital") == 0.30
      assert Settlement.capture_stability_penalty("major_city") == 0.15
      assert Settlement.capture_stability_penalty("minor_city") == 0.05
      assert Settlement.capture_stability_penalty("village") == 0.02
    end

    test "returns 0.0 for non-settlement types" do
      assert Settlement.capture_stability_penalty("fortress") == 0.0
    end
  end

  describe "recruitment_bonus/1" do
    test "sums bonuses from settlements" do
      settlements = [
        %{type: "capital", condition: 1.0},
        %{type: "major_city", condition: 1.0},
        %{type: "village", condition: 1.0}
      ]

      expected = 0.5 + 0.3 + 0.05
      assert_in_delta Settlement.recruitment_bonus(settlements), expected, 0.001
    end

    test "ignores non-settlement structures" do
      structures = [
        %{type: "capital", condition: 1.0},
        %{type: "fortress", condition: 1.0}
      ]

      assert Settlement.recruitment_bonus(structures) == 0.5
    end

    test "returns 0 for empty list" do
      assert Settlement.recruitment_bonus([]) == 0.0
    end
  end

  describe "fsm_score/1" do
    test "returns correct scores per tier" do
      assert Settlement.fsm_score("capital") == 500
      assert Settlement.fsm_score("major_city") == 300
      assert Settlement.fsm_score("minor_city") == 100
      assert Settlement.fsm_score("village") == 30
    end

    test "returns 0 for non-settlement types" do
      assert Settlement.fsm_score("fortress") == 0
    end
  end

  describe "defensive_bonus/1" do
    test "returns condition * 0.1" do
      assert Settlement.defensive_bonus(%{condition: 1.0}) == 0.1
      assert Settlement.defensive_bonus(%{condition: 0.5}) == 0.05
    end
  end

  describe "infer_tier/1" do
    test "infers tier from type" do
      assert Settlement.infer_tier("capital") == 1
      assert Settlement.infer_tier("major_city") == 2
      assert Settlement.infer_tier("minor_city") == 3
      assert Settlement.infer_tier("village") == 4
    end

    test "returns nil for unknown types" do
      assert Settlement.infer_tier("fortress") == nil
    end
  end

  describe "stability_contribution/2" do
    test "returns penalty when settlements are lost" do
      # Lost half settlements: (1.0 - 0.5) * -0.003 = -0.0015
      result = Settlement.stability_contribution(3, 6)
      assert_in_delta result, -0.0015, 0.0001
    end

    test "returns bonus when settlements are gained" do
      result = Settlement.stability_contribution(8, 6)
      assert result == 0.001
    end

    test "returns 0 when at starting count" do
      assert Settlement.stability_contribution(6, 6) == 0.0
    end

    test "returns 0 when starting count is 0" do
      assert Settlement.stability_contribution(3, 0) == 0.0
    end

    test "total loss gives maximum penalty" do
      # 0 out of 5: (1.0 - 0.0) * -0.003 = -0.003
      result = Settlement.stability_contribution(0, 5)
      assert_in_delta result, -0.003, 0.0001
    end
  end

  describe "edge cases" do
    test "production_multiplier picks highest tier when multiple settlements" do
      tile = %{
        structures: [
          %{type: "village", condition: 1.0},
          %{type: "major_city", condition: 1.0}
        ]
      }

      # major_city (1.5) beats village (1.1)
      assert Settlement.production_multiplier(tile) == 1.5
    end

    test "recruitment_bonus with all tier types" do
      settlements = [
        %{type: "capital", condition: 1.0},
        %{type: "major_city", condition: 1.0},
        %{type: "minor_city", condition: 1.0},
        %{type: "minor_city", condition: 1.0},
        %{type: "village", condition: 1.0},
        %{type: "village", condition: 1.0},
        %{type: "village", condition: 1.0}
      ]

      # 0.5 + 0.3 + 0.1 + 0.1 + 0.05 + 0.05 + 0.05 = 1.15
      expected = 0.5 + 0.3 + 0.1 + 0.1 + 0.05 + 0.05 + 0.05
      assert_in_delta Settlement.recruitment_bonus(settlements), expected, 0.001
    end
  end
end
