defmodule Mentat.MapGen.Presets do
  @moduledoc """
  Named preset configurations for map generation.
  """

  @presets %{
    standard: %{
      width: 800,
      height: 600,
      min_distance: 28,
      river_count: 3,
      island_mask: %{mode: :single, radius: 1.5, power: 1.2}
    },
    archipelago: %{
      width: 900,
      height: 600,
      min_distance: 30,
      river_count: 2,
      island_mask: %{
        mode: :multi,
        peaks: [
          %{cx: 0.25, cy: 0.3, radius: 0.35, power: 2.5},
          %{cx: 0.65, cy: 0.25, radius: 0.3, power: 2.5},
          %{cx: 0.45, cy: 0.65, radius: 0.32, power: 2.5},
          %{cx: 0.8, cy: 0.7, radius: 0.28, power: 2.5}
        ]
      }
    },
    pangea: %{
      width: 900,
      height: 550,
      min_distance: 24,
      river_count: 4,
      island_mask: %{mode: :single, radius: 0.92, power: 1.2}
    },
    divided: %{
      width: 800,
      height: 600,
      min_distance: 28,
      river_count: 4,
      island_mask: %{
        mode: :divided,
        peaks: [
          %{cx: 0.25, cy: 0.5, radius: 0.45, power: 2.0},
          %{cx: 0.75, cy: 0.5, radius: 0.45, power: 2.0}
        ]
      }
    }
  }

  @descriptions %{
    standard: "Balanced single continent with varied terrain",
    archipelago: "Multiple island clusters separated by ocean",
    pangea: "Large single landmass with more plains",
    divided: "Two continents with a strait between them"
  }

  @doc "Returns the preset configuration for the given name."
  def get(name) when is_atom(name) do
    Map.get(@presets, name)
  end

  def get(name) when is_binary(name) do
    get(String.to_existing_atom(name))
  rescue
    ArgumentError -> nil
  end

  @doc "Returns the list of available preset names."
  def list, do: Map.keys(@presets)

  @doc "Returns a human-readable description for a preset."
  def describe(name) when is_atom(name) do
    Map.get(@descriptions, name, "Unknown preset")
  end

  def describe(name) when is_binary(name) do
    describe(String.to_existing_atom(name))
  rescue
    ArgumentError -> "Unknown preset"
  end
end
