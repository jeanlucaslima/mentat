defmodule Mentat.NationAgent.CombatTest do
  use ExUnit.Case, async: true

  alias Mentat.NationAgent.Combat

  defp tile(opts \\ []) do
    %{
      defensive_bonus: Keyword.get(opts, :defensive_bonus, 0.0),
      structures: Keyword.get(opts, :structures, [])
    }
  end

  defp fortress(condition \\ 1.0) do
    %{type: "fortress", condition: condition, nation_id: "defender"}
  end

  defp settlement(type, condition \\ 1.0) do
    %{type: type, condition: condition, nation_id: "defender"}
  end

  describe "resolve_battle/3" do
    test "equal forces, no bonus — defender wins ties" do
      result = Combat.resolve_battle(100, 100, tile())

      assert result.winner == :defender
      assert result.attacker_remaining < 100
      assert result.defender_remaining < 100
      assert result.attacker_remaining >= 0
      assert result.defender_remaining >= 0
    end

    test "10:1 ratio — attacker wins decisively" do
      result = Combat.resolve_battle(1000, 100, tile())

      assert result.winner == :attacker
      assert result.attacker_remaining > 900
      assert result.defender_remaining == 0
    end

    test "fortress bonus gives defender advantage" do
      no_fort = Combat.resolve_battle(200, 200, tile())
      with_fort = Combat.resolve_battle(200, 200, tile(structures: [fortress()]))

      # Defender should retain more troops with fortress
      assert with_fort.defender_remaining > no_fort.defender_remaining
    end

    test "terrain defensive bonus helps defender" do
      flat = Combat.resolve_battle(200, 200, tile())
      hilly = Combat.resolve_battle(200, 200, tile(defensive_bonus: 0.3))

      assert hilly.defender_remaining > flat.defender_remaining
    end

    test "minimum 1 casualty per side when both have troops" do
      result = Combat.resolve_battle(1, 1, tile())

      total_casualties =
        1 - result.attacker_remaining + (1 - result.defender_remaining)

      assert total_casualties >= 2
    end

    test "zero attacker troops — defender wins without fight" do
      result = Combat.resolve_battle(0, 100, tile())

      assert result.winner == :defender
      assert result.attacker_remaining == 0
      assert result.defender_remaining == 100
    end

    test "zero defender troops — attacker wins without fight" do
      result = Combat.resolve_battle(100, 0, tile())

      assert result.winner == :attacker
      assert result.attacker_remaining == 100
      assert result.defender_remaining == 0
    end

    test "deterministic — same inputs always produce same outputs" do
      tile = tile(defensive_bonus: 0.1, structures: [fortress(0.8)])

      results = for _ <- 1..10, do: Combat.resolve_battle(500, 300, tile)

      assert Enum.uniq(results) |> length() == 1
    end

    test "settlement gives defender a small defensive bonus" do
      bare = Combat.resolve_battle(200, 200, tile())
      with_village = Combat.resolve_battle(200, 200, tile(structures: [settlement("village")]))

      assert with_village.defender_remaining > bare.defender_remaining
    end

    test "settlement bonus stacks with fortress bonus" do
      fort_only = Combat.resolve_battle(200, 200, tile(structures: [fortress()]))

      fort_and_city =
        Combat.resolve_battle(
          200,
          200,
          tile(structures: [fortress(), settlement("major_city")])
        )

      assert fort_and_city.defender_remaining >= fort_only.defender_remaining
    end

    test "fortress condition affects bonus" do
      damaged_fort = Combat.resolve_battle(200, 200, tile(structures: [fortress(0.5)]))
      pristine_fort = Combat.resolve_battle(200, 200, tile(structures: [fortress(1.0)]))

      # Pristine fortress should help defender more
      assert pristine_fort.defender_remaining >= damaged_fort.defender_remaining
    end
  end
end
