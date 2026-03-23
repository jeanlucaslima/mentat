defmodule MentatWeb.MapLive do
  use MentatWeb, :live_view

  @tile_size 64
  @padding 10

  @terrain_colors %{
    "plains" => "#7ab648",
    "mountain" => "#8c8c7a",
    "forest" => "#3d6b35",
    "coast" => "#c4a35a",
    "ocean" => "#2a6496",
    "strait" => "#1a8a8a"
  }

  @structure_icons %{
    "government" => "★",
    "capital" => "★",
    "city" => "■",
    "port" => "⚓",
    "farm" => "▬",
    "mine" => "▲",
    "fortress" => "⊞"
  }

  def mount(%{"scenario" => scenario}, _session, socket) do
    case Mentat.ScenarioLoader.load(scenario) do
      {:ok, data} ->
        tile_coords = Map.new(data.tiles, &{&1.id, {&1.x, &1.y}})
        owner_map = build_owner_map(data.nations)
        nation_map = Map.new(data.nations, &{&1.id, &1})
        capital_set = MapSet.new(data.nations, & &1.capital_tile_id)
        structure_map = build_structure_map(data.structures)
        troop_map = build_troop_map(data.nations)
        {max_x, max_y} = grid_bounds(data.tiles)

        socket =
          socket
          |> assign(:page_title, "Mentat — #{scenario}")
          |> assign(:scenario, scenario)
          |> assign(:tiles, data.tiles)
          |> assign(:nations, data.nations)
          |> assign(:owner_map, owner_map)
          |> assign(:nation_map, nation_map)
          |> assign(:capital_set, capital_set)
          |> assign(:structure_map, structure_map)
          |> assign(:troop_map, troop_map)
          |> assign(:tile_coords, tile_coords)
          |> assign(:tile_size, @tile_size)
          |> assign(:padding, @padding)
          |> assign(:terrain_colors, @terrain_colors)
          |> assign(:structure_icons, @structure_icons)
          |> assign(:viewbox_width, (max_x + 1) * @tile_size + @padding * 2)
          |> assign(:viewbox_height, (max_y + 1) * @tile_size + @padding * 2)
          |> assign(:error, nil)

        {:ok, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:page_title, "Mentat — Error")
          |> assign(:error, "Failed to load scenario: #{inspect(reason)}")
          |> assign_defaults()

        {:ok, socket}
    end
  end

  defp assign_defaults(socket) do
    socket
    |> assign(:scenario, nil)
    |> assign(:tiles, [])
    |> assign(:nations, [])
    |> assign(:owner_map, %{})
    |> assign(:nation_map, %{})
    |> assign(:capital_set, MapSet.new())
    |> assign(:structure_map, %{})
    |> assign(:troop_map, %{})
    |> assign(:tile_coords, %{})
    |> assign(:tile_size, @tile_size)
    |> assign(:padding, @padding)
    |> assign(:terrain_colors, @terrain_colors)
    |> assign(:structure_icons, @structure_icons)
    |> assign(:viewbox_width, 0)
    |> assign(:viewbox_height, 0)
  end

  defp build_owner_map(nations) do
    Enum.reduce(nations, %{}, fn nation, acc ->
      Enum.reduce(nation.starting_tiles, acc, fn tile_id, inner_acc ->
        Map.put(inner_acc, tile_id, nation.id)
      end)
    end)
  end

  defp build_structure_map(structures) do
    Enum.group_by(structures, & &1.tile_id)
  end

  defp build_troop_map(nations) do
    Enum.reduce(nations, %{}, fn nation, acc ->
      Enum.reduce(nation.troop_positions, acc, fn {tile_id, count}, inner_acc ->
        Map.update(inner_acc, tile_id, [{nation.id, count}], &[{nation.id, count} | &1])
      end)
    end)
  end

  defp grid_bounds(tiles) do
    max_x = Enum.max_by(tiles, & &1.x).x
    max_y = Enum.max_by(tiles, & &1.y).y
    {max_x, max_y}
  end

  @doc false
  def tile_px(coord, tile_size, padding), do: coord * tile_size + padding

  @doc false
  def river_lines(tile, tile_coords, tile_size, padding) do
    tile_x = tile.x
    tile_y = tile.y
    px = tile_x * tile_size + padding
    py = tile_y * tile_size + padding

    Enum.flat_map(tile.river_edges, fn adj_id ->
      case Map.get(tile_coords, adj_id) do
        {ax, ay} ->
          dx = ax - tile_x
          dy = ay - tile_y

          case {dx, dy} do
            {0, -1} -> [{px, py, px + tile_size, py}]
            {0, 1} -> [{px, py + tile_size, px + tile_size, py + tile_size}]
            {-1, 0} -> [{px, py, px, py + tile_size}]
            {1, 0} -> [{px + tile_size, py, px + tile_size, py + tile_size}]
            _ -> []
          end

        nil ->
          []
      end
    end)
  end

  @doc false
  def troop_label(tile_id, troop_map, nation_map) do
    case Map.get(troop_map, tile_id) do
      nil ->
        nil

      entries ->
        {nation_id, count} = Enum.max_by(entries, fn {_id, c} -> c end)
        nation = Map.get(nation_map, nation_id)
        color = if nation, do: nation.color, else: "#ffffff"
        {count, color}
    end
  end
end
