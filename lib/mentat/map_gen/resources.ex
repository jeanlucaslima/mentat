defmodule Mentat.MapGen.Resources do
  @moduledoc """
  Assigns resources to land tiles based on terrain type.
  Approximately 60% of land tiles receive a resource.
  """

  @resource_by_terrain %{
    "plains" => {:grain, 30, 60},
    "forest" => {:grain, 15, 30},
    "coast" => {:oil, 20, 50},
    "hills" => {:iron, 20, 40},
    "mountains" => {:iron_or_rare, 15, 35}
  }

  @doc """
  Assigns resources to cells based on their terrain type.
  Returns cells with `:resource` field populated.
  """
  def assign(cells, seed) do
    rand_state = :rand.seed_s(:exsss, {seed + 100, seed * 3 + 7, seed * 5 + 13})

    {assigned, _rand} =
      Enum.map_reduce(cells, rand_state, fn cell, rs ->
        if cell.type == "ocean" do
          {Map.put(cell, :resource, %{type: nil, base_amount: 0}), rs}
        else
          {roll, rs} = :rand.uniform_s(rs)

          if roll < 0.60 do
            {resource, rs} = assign_resource(cell.type, rs)
            {Map.put(cell, :resource, resource), rs}
          else
            {Map.put(cell, :resource, %{type: nil, base_amount: 0}), rs}
          end
        end
      end)

    assigned
  end

  defp assign_resource(terrain_type, rand_state) do
    case Map.get(@resource_by_terrain, terrain_type) do
      {:iron_or_rare, min_amt, max_amt} ->
        {roll, rand_state} = :rand.uniform_s(rand_state)
        type = if roll < 0.15, do: "rare_earth", else: "iron"
        {amount, rand_state} = random_amount(rand_state, min_amt, max_amt)
        {%{type: type, base_amount: amount}, rand_state}

      {type, min_amt, max_amt} ->
        {amount, rand_state} = random_amount(rand_state, min_amt, max_amt)
        {%{type: Atom.to_string(type), base_amount: amount}, rand_state}

      nil ->
        {%{type: nil, base_amount: 0}, rand_state}
    end
  end

  defp random_amount(rand_state, min_amt, max_amt) do
    {val, rand_state} = :rand.uniform_s(max_amt - min_amt + 1, rand_state)
    {min_amt + val - 1, rand_state}
  end
end
