defmodule Mentat.Settlement do
  @moduledoc """
  Pure functions for settlement tier mechanics.

  Settlement tiers give geography strategic meaning by providing production
  multipliers, stability effects, recruitment bonuses, and FSM target scores.

  No GenServer, no ETS, no side effects — constants and functions only.
  """

  @tiers %{
    "capital" => %{
      tier: 1,
      production_multiplier: 2.0,
      recruitment_bonus: 0.5,
      stability_penalty: 0.30,
      pop_share: 0.35,
      fsm_score: 500
    },
    "major_city" => %{
      tier: 2,
      production_multiplier: 1.5,
      recruitment_bonus: 0.3,
      stability_penalty: 0.15,
      pop_share: 0.20,
      fsm_score: 300
    },
    "minor_city" => %{
      tier: 3,
      production_multiplier: 1.2,
      recruitment_bonus: 0.1,
      stability_penalty: 0.05,
      pop_share: 0.10,
      fsm_score: 100
    },
    "village" => %{
      tier: 4,
      production_multiplier: 1.1,
      recruitment_bonus: 0.05,
      stability_penalty: 0.02,
      pop_share: 0.05,
      fsm_score: 30
    }
  }

  @doc """
  Returns true if the structure is a settlement (has a known tier).
  Fortresses and other non-settlement structures return false.
  """
  def settlement?(%{type: type}), do: Map.has_key?(@tiers, type)

  @doc """
  Returns the tier configuration for a settlement type, or nil for non-settlements.
  """
  def tier_config(type), do: Map.get(@tiers, type)

  @doc """
  Returns the production multiplier for a tile based on its best settlement.
  If no settlement exists on the tile, returns 1.0.
  """
  def production_multiplier(%{structures: structures}) do
    structures
    |> Enum.filter(&settlement?/1)
    |> Enum.map(fn s ->
      Map.get(@tiers, s.type, %{production_multiplier: 1.0}).production_multiplier
    end)
    |> Enum.max(fn -> 1.0 end)
  end

  def production_multiplier(_tile), do: 1.0

  @doc """
  Returns the one-time stability penalty when a settlement of the given type is captured.
  """
  def capture_stability_penalty(type) do
    case Map.get(@tiers, type) do
      nil -> 0.0
      config -> config.stability_penalty
    end
  end

  @doc """
  Returns the sum of recruitment bonuses from a list of settlement structures.
  """
  def recruitment_bonus(settlements) when is_list(settlements) do
    settlements
    |> Enum.filter(&settlement?/1)
    |> Enum.map(fn s -> Map.get(@tiers, s.type, %{recruitment_bonus: 0.0}).recruitment_bonus end)
    |> Enum.sum()
  end

  @doc """
  Returns the FSM target score bonus for a settlement type.
  """
  def fsm_score(type) do
    case Map.get(@tiers, type) do
      nil -> 0
      config -> config.fsm_score
    end
  end

  @doc """
  Returns the defensive bonus a settlement provides (condition * 0.1).
  Half the bonus of a fortress.
  """
  def defensive_bonus(%{condition: condition}), do: condition * 0.1

  @doc """
  Returns the tier number for a settlement type, or nil for non-settlements.
  Used during scenario loading to infer tier from type.
  """
  def infer_tier("capital"), do: 1
  def infer_tier("major_city"), do: 2
  def infer_tier("minor_city"), do: 3
  def infer_tier("village"), do: 4
  def infer_tier(_), do: nil

  @doc """
  Computes a per-tick stability adjustment based on how many settlements a nation
  controls relative to its starting count.

  Returns a float to add to stability (negative = penalty, positive = bonus).
  """
  def stability_contribution(current_count, starting_count) when starting_count > 0 do
    ratio = current_count / starting_count

    cond do
      ratio < 1.0 -> (1.0 - ratio) * -0.003
      ratio > 1.0 -> 0.001
      true -> 0.0
    end
  end

  def stability_contribution(_current, _starting), do: 0.0

  @doc """
  Returns a list of all known settlement types.
  """
  def types, do: Map.keys(@tiers)

  @doc """
  Returns the full tiers configuration map.
  """
  def tiers, do: @tiers
end
