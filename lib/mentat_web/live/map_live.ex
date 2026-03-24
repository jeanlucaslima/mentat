defmodule MentatWeb.MapLive do
  use MentatWeb, :live_view

  import MentatWeb.MapComponents,
    only: [
      grid_bounds: 1,
      build_owner_map: 1,
      build_structure_map: 1,
      build_troop_map: 1,
      tile_size: 0,
      padding: 0,
      voronoi?: 1,
      voronoi_viewbox: 1
    ]

  def mount(%{"scenario" => scenario}, _session, socket) do
    case Mentat.ScenarioLoader.load(scenario) do
      {:ok, data} ->
        tile_coords = Map.new(data.tiles, &{&1.id, {&1.x, &1.y}})
        owner_map = build_owner_map(data.nations)
        nation_map = Map.new(data.nations, &{&1.id, &1})
        capital_set = MapSet.new(data.nations, & &1.capital_tile_id)
        structure_map = build_structure_map(data.structures)
        troop_map = build_troop_map(data.nations)
        tile_map = Map.new(data.tiles, &{&1.id, &1})
        is_voronoi = voronoi?(data.tiles)

        {vw, vh} =
          if is_voronoi do
            {max_x, max_y} = voronoi_viewbox(data.tiles)
            {max_x, max_y}
          else
            {max_x, max_y} = grid_bounds(data.tiles)
            ts = tile_size()
            pad = padding()
            {(max_x + 1) * ts + pad * 2, (max_y + 1) * ts + pad * 2}
          end

        socket =
          socket
          |> assign(:page_title, "Mentat \u2014 #{scenario}")
          |> assign(:scenario, scenario)
          |> assign(:tiles, data.tiles)
          |> assign(:nations, data.nations)
          |> assign(:owner_map, owner_map)
          |> assign(:nation_map, nation_map)
          |> assign(:capital_set, capital_set)
          |> assign(:structure_map, structure_map)
          |> assign(:troop_map, troop_map)
          |> assign(:tile_map, tile_map)
          |> assign(:tile_coords, tile_coords)
          |> assign(:viewbox_width, vw)
          |> assign(:viewbox_height, vh)
          |> assign(:is_voronoi, is_voronoi)
          |> assign(:show_political, true)
          |> assign(:show_structures, true)
          |> assign(:show_troops, true)
          |> assign(:error, nil)

        {:ok, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:page_title, "Mentat \u2014 Error")
          |> assign(:error, "Failed to load scenario: #{inspect(reason)}")
          |> assign_defaults()

        {:ok, socket}
    end
  end

  def handle_event("toggle_layer", %{"layer" => layer}, socket) do
    key = String.to_existing_atom("show_#{layer}")
    {:noreply, assign(socket, key, !socket.assigns[key])}
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
    |> assign(:tile_map, %{})
    |> assign(:tile_coords, %{})
    |> assign(:viewbox_width, 0)
    |> assign(:viewbox_height, 0)
    |> assign(:is_voronoi, false)
    |> assign(:show_political, true)
    |> assign(:show_structures, true)
    |> assign(:show_troops, true)
  end
end
