defmodule Mentat.MapGen.Nations do
  @moduledoc """
  Places nation capitals on land tiles using max-min distance algorithm.
  Each nation owns only its capital tile.
  """

  @nation_templates [
    %{
      id: "nation_1",
      name: "Arvenia",
      color: "#4A90D9",
      government_type: "democracy",
      political_rules: [
        %{action: "declare_war", requires: ["parliamentary_vote"], resolves_in_ticks: 168},
        %{action: "increase_army", requires: ["budget_approval"], resolves_in_ticks: 48},
        %{action: "move_troops", requires: ["command_order"], resolves_in_ticks: 6}
      ]
    },
    %{
      id: "nation_2",
      name: "Korrath",
      color: "#D94A4A",
      government_type: "autocracy",
      political_rules: [
        %{action: "declare_war", requires: ["supreme_decree"], resolves_in_ticks: 24},
        %{action: "increase_army", requires: ["military_order"], resolves_in_ticks: 12},
        %{action: "move_troops", requires: ["direct_command"], resolves_in_ticks: 2}
      ]
    },
    %{
      id: "nation_3",
      name: "Valdris",
      color: "#D9A84A",
      government_type: "constitutional_monarchy",
      political_rules: [
        %{
          action: "declare_war",
          requires: ["royal_assent", "council_vote"],
          resolves_in_ticks: 72
        },
        %{action: "increase_army", requires: ["royal_assent"], resolves_in_ticks: 24},
        %{action: "move_troops", requires: ["military_dispatch"], resolves_in_ticks: 4}
      ]
    },
    %{
      id: "nation_4",
      name: "Thenmark",
      color: "#6B4AD9",
      government_type: "oligarchy",
      political_rules: [
        %{action: "declare_war", requires: ["council_majority"], resolves_in_ticks: 48},
        %{action: "increase_army", requires: ["treasury_allocation"], resolves_in_ticks: 24},
        %{action: "move_troops", requires: ["council_directive"], resolves_in_ticks: 4}
      ]
    },
    %{
      id: "nation_5",
      name: "Ironholt",
      color: "#4AD97A",
      government_type: "military_junta",
      political_rules: [
        %{action: "declare_war", requires: ["general_order"], resolves_in_ticks: 12},
        %{action: "increase_army", requires: ["conscription_order"], resolves_in_ticks: 6},
        %{action: "move_troops", requires: ["field_command"], resolves_in_ticks: 1}
      ]
    }
  ]

  @doc """
  Places `count` capitals on land tiles using max-min distance algorithm.
  Returns a list of nation maps ready for nations.json.
  """
  def place_capitals(cells, count \\ 5, seed) do
    rand_state = :rand.seed_s(:exsss, {seed + 300, seed * 13 + 1, seed * 17 + 9})

    land_cells =
      cells
      |> Enum.filter(fn c -> c.traversable end)
      |> Enum.reject(fn c -> c.type == "coast" end)

    if length(land_cells) < count do
      {:error, "Not enough land tiles for #{count} capitals"}
    else
      {capitals, _rand} = select_capitals(land_cells, count, rand_state)
      templates = Enum.take(@nation_templates, count)

      nations =
        Enum.zip(templates, capitals)
        |> Enum.map(fn {template, cell} ->
          tile_id = "t_#{cell.index}"

          Map.merge(template, %{
            starting_tiles: [tile_id],
            capital_tile_id: tile_id,
            starting_resources: starting_resources(),
            troop_positions: %{tile_id => 150},
            internal_stability: 70,
            public_approval: 65
          })
        end)

      {:ok, nations}
    end
  end

  defp select_capitals(land_cells, count, rand_state) do
    # First capital: random land tile
    {idx, rand_state} = random_index(rand_state, length(land_cells))
    first = Enum.at(land_cells, idx)

    Enum.reduce(2..count, {[first], rand_state}, fn _i, {selected, rs} ->
      # Find land tile that maximizes minimum distance to all selected
      best =
        land_cells
        |> Enum.reject(fn c -> Enum.any?(selected, fn s -> s.index == c.index end) end)
        |> Enum.max_by(fn candidate ->
          Enum.map(selected, fn s ->
            dx = candidate.cx - s.cx
            dy = candidate.cy - s.cy
            dx * dx + dy * dy
          end)
          |> Enum.min()
        end)

      {[best | selected], rs}
    end)
  end

  defp starting_resources do
    %{
      "grain" => 300,
      "oil" => 100,
      "iron" => 50,
      "rare_earth" => 0,
      "treasury" => 500,
      "troops" => 150,
      "population" => 800,
      "base_birth_rate" => 0.011,
      "base_death_rate" => 0.007,
      "recruitment_rate" => 0.018,
      "max_troop_ratio" => 0.05,
      "migration_policy" => %{
        "open_borders" => true,
        "refugee_policy" => "accept",
        "skilled_priority" => false
      }
    }
  end

  defp random_index(rand_state, max) do
    {val, rs} = :rand.uniform_s(max, rand_state)
    {val - 1, rs}
  end
end
