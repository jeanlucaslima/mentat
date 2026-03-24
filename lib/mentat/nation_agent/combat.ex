defmodule Mentat.NationAgent.Combat do
  @moduledoc """
  Pure functions for combat resolution.
  No GenServer, no ETS, no side effects — counts in, result out.

  Uses a deterministic Lanchester-style linear attrition model.
  Same inputs always produce same outputs (no randomness).
  """

  @loss_factor 0.3

  @doc """
  Resolves a battle between an attacker and a defender on a tile.

  Returns `%{attacker_remaining: integer, defender_remaining: integer, winner: :attacker | :defender}`.

  The defender gets bonuses from terrain (`tile.defensive_bonus`) and fortress structures
  on the tile (`fortress.condition * 0.2`).
  """
  def resolve_battle(attacker_count, defender_count, tile)
      when is_integer(attacker_count) and is_integer(defender_count) and
             attacker_count > 0 and defender_count > 0 do
    fortress_bonus =
      tile.structures
      |> Enum.filter(fn s -> s.type == "fortress" end)
      |> Enum.map(fn s -> s.condition * 0.2 end)
      |> Enum.sum()

    total_defensive_bonus = (tile.defensive_bonus || 0.0) + fortress_bonus
    effective_defender = defender_count * (1.0 + total_defensive_bonus)

    total_strength = attacker_count + effective_defender

    attacker_losses =
      (defender_count * @loss_factor * (effective_defender / total_strength))
      |> round()
      |> max(1)

    defender_losses =
      (attacker_count * @loss_factor * (attacker_count / total_strength))
      |> round()
      |> max(1)

    attacker_remaining = max(0, attacker_count - attacker_losses)
    defender_remaining = max(0, defender_count - defender_losses)

    # Ties go to defender
    winner = if attacker_remaining > defender_remaining, do: :attacker, else: :defender

    %{
      attacker_remaining: attacker_remaining,
      defender_remaining: defender_remaining,
      winner: winner
    }
  end

  # No battle if either side has zero troops
  def resolve_battle(0, defender_count, _tile) when defender_count >= 0 do
    %{attacker_remaining: 0, defender_remaining: defender_count, winner: :defender}
  end

  def resolve_battle(attacker_count, 0, _tile) when attacker_count >= 0 do
    %{attacker_remaining: attacker_count, defender_remaining: 0, winner: :attacker}
  end
end
