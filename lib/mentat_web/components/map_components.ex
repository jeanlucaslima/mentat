defmodule MentatWeb.MapComponents do
  use Phoenix.Component

  @tile_size 64
  @padding 10

  @terrain_colors %{
    "plains" => "#4a8c3f",
    "mountain" => "#b8b8b0",
    "mountains" => "#b8b8b0",
    "forest" => "#1a3a14",
    "coast" => "#d4b483",
    "ocean" => "#0a0e14",
    "strait" => "#1a6b6b",
    "hills" => "#8b6b3e"
  }

  @structure_icons %{
    "government" => "\u2605",
    "capital" => "\u2605",
    "city" => "\u25A0",
    "port" => "\u2693",
    "farm" => "\u25AC",
    "mine" => "\u25B2",
    "fortress" => "\u229E"
  }

  attr :tiles, :list, required: true
  attr :owner_map, :map, required: true
  attr :nation_map, :map, required: true
  attr :capital_set, :any, required: true
  attr :structure_map, :map, required: true
  attr :troop_map, :map, required: true
  attr :tile_coords, :map, required: true
  attr :viewbox_width, :integer, required: true
  attr :viewbox_height, :integer, required: true

  def map_svg(assigns) do
    assigns =
      assigns
      |> assign(:tile_size, @tile_size)
      |> assign(:padding, @padding)
      |> assign(:terrain_colors, @terrain_colors)
      |> assign(:structure_icons, @structure_icons)

    ~H"""
    <svg
      viewBox={"0 0 #{@viewbox_width} #{@viewbox_height}"}
      xmlns="http://www.w3.org/2000/svg"
      class="w-full h-auto max-h-[calc(100vh-12rem)]"
      style="background: #0a0e14"
    >
      <g :for={tile <- @tiles}>
        <rect
          x={tile_px(tile.x, @tile_size, @padding)}
          y={tile_px(tile.y, @tile_size, @padding)}
          width={@tile_size}
          height={@tile_size}
          fill={Map.get(@terrain_colors, tile.type, "#333333")}
          stroke={if tile.type == "ocean", do: "none", else: "rgba(0,0,0,0.25)"}
          stroke-width={if tile.type == "ocean", do: "0", else: "0.5"}
        />

        <%= if tile.type not in ["ocean"] do %>
          <rect
            x={tile_px(tile.x, @tile_size, @padding) + 1}
            y={tile_px(tile.y, @tile_size, @padding) + 1}
            width={@tile_size - 2}
            height={@tile_size - 2}
            fill="none"
            stroke="rgba(0,0,0,0.12)"
            stroke-width="2"
          />
        <% end %>

        <%= if tile.type not in ["ocean"] do %>
          <%= if owner_id = Map.get(@owner_map, tile.id) do %>
            <% nation = Map.get(@nation_map, owner_id) %>
            <line
              :for={{x1, y1, x2, y2} <- border_lines(tile, @owner_map, @tile_size, @padding)}
              x1={x1}
              y1={y1}
              x2={x2}
              y2={y2}
              stroke={nation.color}
              stroke-width="3"
              opacity="0.85"
              stroke-linecap="square"
            />
          <% end %>
        <% end %>

        <%= if tile.type == "strait" do %>
          <rect
            x={tile_px(tile.x, @tile_size, @padding) + 1}
            y={tile_px(tile.y, @tile_size, @padding) + 1}
            width={@tile_size - 2}
            height={@tile_size - 2}
            fill="none"
            stroke="#00ffcc"
            stroke-width="2"
            stroke-dasharray="6,3"
            opacity="0.9"
          />
        <% end %>

        <line
          :for={{x1, y1, x2, y2} <- river_lines(tile, @tile_coords, @tile_size, @padding)}
          x1={x1}
          y1={y1}
          x2={x2}
          y2={y2}
          stroke="#4488cc"
          stroke-width="3"
          stroke-linecap="round"
        />

        <%= if tile.type not in ["ocean"] do %>
          <%= if structures = Map.get(@structure_map, tile.id) do %>
            <text
              :for={structure <- structures}
              x={tile_px(tile.x, @tile_size, @padding) + @tile_size / 2}
              y={tile_px(tile.y, @tile_size, @padding) + @tile_size / 2 + 5}
              text-anchor="middle"
              font-size="16"
              fill={if structure_type(structure) == "government", do: "#FFD700", else: "#e0e0e0"}
              opacity="0.9"
            >
              {Map.get(@structure_icons, structure_type(structure), "?")}
            </text>
          <% end %>
        <% end %>

        <%= if tile.type not in ["ocean"] and MapSet.member?(@capital_set, tile.id) do %>
          <circle
            cx={tile_px(tile.x, @tile_size, @padding) + @tile_size / 2}
            cy={tile_px(tile.y, @tile_size, @padding) + @tile_size / 2}
            r="22"
            fill="none"
            stroke="#FFD700"
            stroke-width="2"
            opacity="0.7"
          />
        <% end %>

        <%= if tile.type not in ["ocean"] do %>
          <%= if troop = troop_label(tile.id, @troop_map, @nation_map) do %>
            <% {count, color} = troop %>
            <text
              x={tile_px(tile.x, @tile_size, @padding) + @tile_size - 4}
              y={tile_px(tile.y, @tile_size, @padding) + @tile_size - 4}
              text-anchor="end"
              font-size="10"
              font-family="monospace"
              font-weight="bold"
              fill={color}
            >
              {count}
            </text>
          <% end %>
        <% end %>
      </g>
    </svg>
    """
  end

  attr :tiles, :list, required: true
  attr :owner_map, :map, required: true
  attr :nation_map, :map, required: true
  attr :capital_set, :any, required: true
  attr :structure_map, :map, required: true
  attr :troop_map, :map, required: true
  attr :viewbox_width, :float, required: true
  attr :viewbox_height, :float, required: true

  def voronoi_map_svg(assigns) do
    assigns =
      assigns
      |> assign(:terrain_colors, @terrain_colors)
      |> assign(:structure_icons, @structure_icons)

    ~H"""
    <svg
      viewBox={"0 0 #{@viewbox_width} #{@viewbox_height}"}
      xmlns="http://www.w3.org/2000/svg"
      class="w-full h-auto max-h-[calc(100vh-12rem)]"
      style="background: #0a0e14"
    >
      <g :for={tile <- @tiles}>
        <polygon
          points={polygon_points(tile.polygon)}
          fill={Map.get(@terrain_colors, tile.type, "#333333")}
          stroke={if tile.type == "ocean", do: "#0a0e14", else: "#000000"}
          stroke-width={if tile.type == "ocean", do: "0.5", else: "0.3"}
          stroke-opacity={if tile.type == "ocean", do: "1", else: "0.25"}
        />

        <%= if tile.type not in ["ocean"] do %>
          <polygon
            points={polygon_points(tile.polygon)}
            fill="none"
            stroke="rgba(0,0,0,0.12)"
            stroke-width="1.5"
          />
        <% end %>

        <%= if tile.type not in ["ocean"] do %>
          <%= if owner_id = Map.get(@owner_map, tile.id) do %>
            <% nation = Map.get(@nation_map, owner_id) %>
            <polygon
              points={polygon_points(tile.polygon)}
              fill="none"
              stroke={nation.color}
              stroke-width="2"
              opacity="0.7"
            />
          <% end %>
        <% end %>

        <%= if tile.type not in ["ocean"] and MapSet.member?(@capital_set, tile.id) do %>
          <circle
            cx={tile.cx}
            cy={tile.cy}
            r="12"
            fill="none"
            stroke="#FFD700"
            stroke-width="2"
            opacity="0.7"
          />
        <% end %>

        <%= if tile.type not in ["ocean"] do %>
          <%= if structures = Map.get(@structure_map, tile.id) do %>
            <text
              :for={structure <- structures}
              x={tile.cx}
              y={tile.cy + 4}
              text-anchor="middle"
              font-size="12"
              fill={
                if structure_type(structure) in ["government", "capital"],
                  do: "#FFD700",
                  else: "#e0e0e0"
              }
              opacity="0.9"
            >
              {Map.get(@structure_icons, structure_type(structure), "?")}
            </text>
          <% end %>
        <% end %>

        <%= if tile.type not in ["ocean"] do %>
          <%= if troop = troop_label(tile.id, @troop_map, @nation_map) do %>
            <% {count, color} = troop %>
            <text
              x={tile.cx + 8}
              y={tile.cy + 10}
              text-anchor="end"
              font-size="8"
              font-family="monospace"
              font-weight="bold"
              fill={color}
            >
              {count}
            </text>
          <% end %>
        <% end %>
      </g>

      <%!-- River edges rendered as blue lines between cell centers --%>
      <g :for={tile <- @tiles}>
        <%= if tile.type not in ["ocean"] do %>
          <line
            :for={adj_id <- tile.river_edges || []}
            :if={adj_tile = Enum.find(@tiles, fn t -> t.id == adj_id end)}
            x1={tile.cx}
            y1={tile.cy}
            x2={adj_tile.cx}
            y2={adj_tile.cy}
            stroke="#4488cc"
            stroke-width="2"
            stroke-linecap="round"
            opacity="0.8"
          />
        <% end %>
      </g>
    </svg>
    """
  end

  @doc "Check if tiles use Voronoi polygons (first tile has polygon data)"
  def voronoi?(tiles) do
    case tiles do
      [first | _] -> first.polygon != nil
      _ -> false
    end
  end

  @doc "Compute viewbox dimensions from Voronoi polygon vertices"
  def voronoi_viewbox(tiles) do
    all_vertices = Enum.flat_map(tiles, fn t -> t.polygon || [] end)

    case all_vertices do
      [] ->
        {0.0, 0.0}

      verts ->
        max_x =
          verts
          |> Enum.map(fn
            [x, _y] -> x
            {x, _y} -> x
          end)
          |> Enum.max()

        max_y =
          verts
          |> Enum.map(fn
            [_x, y] -> y
            {_x, y} -> y
          end)
          |> Enum.max()

        {max_x, max_y}
    end
  end

  defp polygon_points(nil), do: ""

  defp polygon_points(polygon) do
    Enum.map_join(polygon, " ", fn
      [x, y] -> "#{x},#{y}"
      {x, y} -> "#{x},#{y}"
    end)
  end

  # Helper to handle both map and struct access for structure type
  defp structure_type(%{type: type}), do: type
  defp structure_type(structure) when is_map(structure), do: Map.get(structure, "type")

  def tile_px(coord, tile_size, padding), do: coord * tile_size + padding

  def river_lines(tile, tile_coords, tile_size, padding) do
    tile_x = tile.x
    tile_y = tile.y
    px = tile_x * tile_size + padding
    py = tile_y * tile_size + padding

    river_edges = Map.get(tile, :river_edges) || Map.get(tile, "river_edges", [])

    Enum.flat_map(river_edges, fn adj_id ->
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

  def border_lines(tile, owner_map, tile_size, padding) do
    owner = Map.get(owner_map, tile.id)

    if owner == nil do
      []
    else
      px = tile.x * tile_size + padding
      py = tile.y * tile_size + padding
      ts = tile_size

      [
        {0, -1, px, py, px + ts, py},
        {0, 1, px, py + ts, px + ts, py + ts},
        {-1, 0, px, py, px, py + ts},
        {1, 0, px + ts, py, px + ts, py + ts}
      ]
      |> Enum.filter(fn {dx, dy, _, _, _, _} ->
        neighbor_id = "t_#{tile.x + dx}_#{tile.y + dy}"
        Map.get(owner_map, neighbor_id) != owner
      end)
      |> Enum.map(fn {_, _, x1, y1, x2, y2} -> {x1, y1, x2, y2} end)
    end
  end

  def troop_label(tile_id, troop_map, nation_map) do
    case Map.get(troop_map, tile_id) do
      nil ->
        nil

      entries ->
        {nation_id, count} = Enum.max_by(entries, fn {_id, c} -> c end)
        nation = Map.get(nation_map, nation_id)
        color = if nation, do: get_color(nation), else: "#ffffff"
        {count, color}
    end
  end

  defp get_color(%{color: color}), do: color
  defp get_color(nation) when is_map(nation), do: Map.get(nation, "color", "#ffffff")

  @doc "Calculate grid bounds for a list of tiles"
  def grid_bounds(tiles) do
    max_x = Enum.max_by(tiles, & &1.x).x
    max_y = Enum.max_by(tiles, & &1.y).y
    {max_x, max_y}
  end

  @doc "Build owner map from nations list"
  def build_owner_map(nations) do
    Enum.reduce(nations, %{}, fn nation, acc ->
      starting_tiles = Map.get(nation, :starting_tiles) || Map.get(nation, "starting_tiles", [])

      Enum.reduce(starting_tiles, acc, fn tile_id, inner_acc ->
        Map.put(inner_acc, tile_id, Map.get(nation, :id) || Map.get(nation, "id"))
      end)
    end)
  end

  @doc "Build structure map from structures list"
  def build_structure_map(structures) do
    Enum.group_by(structures, fn s -> Map.get(s, :tile_id) || Map.get(s, "tile_id") end)
  end

  @doc "Build troop map from nations list"
  def build_troop_map(nations) do
    Enum.reduce(nations, %{}, fn nation, acc ->
      troop_positions =
        Map.get(nation, :troop_positions) || Map.get(nation, "troop_positions", %{})

      Enum.reduce(troop_positions, acc, fn {tile_id, count}, inner_acc ->
        nation_id = Map.get(nation, :id) || Map.get(nation, "id")
        Map.update(inner_acc, tile_id, [{nation_id, count}], &[{nation_id, count} | &1])
      end)
    end)
  end

  def tile_size, do: @tile_size
  def padding, do: @padding
end
