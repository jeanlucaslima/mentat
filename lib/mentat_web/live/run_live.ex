defmodule MentatWeb.RunLive do
  use MentatWeb, :live_view

  import MentatWeb.MapComponents,
    only: [
      grid_bounds: 1,
      tile_size: 0,
      padding: 0,
      voronoi?: 1,
      voronoi_viewbox: 1
    ]

  alias Mentat.{Queries, Simulation}

  @map_refresh_interval 24

  def mount(%{"id" => id}, _session, socket) do
    case Queries.get_run(id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/runs")}

      %{status: "stopped"} ->
        {:ok, push_navigate(socket, to: ~p"/runs/#{id}/replay")}

      run ->
        if connected?(socket) do
          Phoenix.PubSub.subscribe(Mentat.PubSub, "world:tick")
        end

        snapshots = Queries.get_latest_nation_snapshots(id)
        events = Queries.get_recent_events(id, 20)
        max_tick = Queries.get_run_max_tick(id)

        {:ok, scenario_data} = Mentat.ScenarioLoader.load(run.scenario_id)
        tile_coords = Map.new(scenario_data.tiles, &{&1.id, {&1.x, &1.y}})
        nation_map = Map.new(scenario_data.nations, &{&1.id, &1})
        capital_set = MapSet.new(scenario_data.nations, & &1.capital_tile_id)
        structure_map = MentatWeb.MapComponents.build_structure_map(scenario_data.structures)
        tile_map = Map.new(scenario_data.tiles, &{&1.id, &1})
        is_voronoi = voronoi?(scenario_data.tiles)

        {vw, vh} =
          if is_voronoi do
            voronoi_viewbox(scenario_data.tiles)
          else
            {max_x, max_y} = grid_bounds(scenario_data.tiles)
            ts = tile_size()
            pad = padding()
            {(max_x + 1) * ts + pad * 2, (max_y + 1) * ts + pad * 2}
          end

        {owner_map, troop_map} = load_map_state_from_ets()

        socket =
          socket
          |> assign(:page_title, "Mentat — #{run.scenario_id} Live")
          |> assign(:run, run)
          |> assign(:snapshots, snapshots)
          |> assign(:events, events)
          |> assign(:tick, max_tick)
          |> assign(:tiles, scenario_data.tiles)
          |> assign(:tile_coords, tile_coords)
          |> assign(:nation_map, nation_map)
          |> assign(:capital_set, capital_set)
          |> assign(:structure_map, structure_map)
          |> assign(:tile_map, tile_map)
          |> assign(:is_voronoi, is_voronoi)
          |> assign(:viewbox_width, vw)
          |> assign(:viewbox_height, vh)
          |> assign(:owner_map, owner_map)
          |> assign(:troop_map, troop_map)
          |> assign(:map_tick, max_tick)
          |> assign(:show_political, true)
          |> assign(:show_structures, true)
          |> assign(:show_troops, true)

        {:ok, socket}
    end
  end

  def handle_event("stop_run", _params, socket) do
    Simulation.stop(socket.assigns.run.id)
    {:noreply, push_navigate(socket, to: ~p"/runs")}
  end

  def handle_event("toggle_layer", %{"layer" => layer}, socket) do
    key =
      case layer do
        "political" -> :show_political
        "structures" -> :show_structures
        "troops" -> :show_troops
      end

    {:noreply, assign(socket, key, !socket.assigns[key])}
  end

  def handle_info({:tick, tick_info}, socket) do
    run_id = socket.assigns.run.id
    snapshots = Queries.get_latest_nation_snapshots(run_id)
    events = Queries.get_recent_events(run_id, 20)

    socket =
      socket
      |> assign(:tick, tick_info.tick)
      |> assign(:snapshots, snapshots)
      |> assign(:events, events)

    socket =
      if rem(tick_info.tick, @map_refresh_interval) == 0 do
        {owner_map, troop_map} =
          load_map_state_from_ets()

        socket
        |> assign(:owner_map, owner_map)
        |> assign(:troop_map, troop_map)
        |> assign(:map_tick, tick_info.tick)
      else
        socket
      end

    {:noreply, socket}
  end

  def handle_info({:nation_collapsed, _nation_id}, socket) do
    snapshots = Queries.get_latest_nation_snapshots(socket.assigns.run.id)
    events = Queries.get_recent_events(socket.assigns.run.id, 20)

    socket =
      socket
      |> assign(:snapshots, snapshots)
      |> assign(:events, events)

    {:noreply, socket}
  end

  defp load_map_state_from_ets do
    tiles = Mentat.World.get_all_tiles()

    owner_map =
      tiles
      |> Enum.filter(& &1.owner)
      |> Map.new(&{&1.id, &1.owner})

    troop_map =
      tiles
      |> Enum.filter(fn t -> t.troops != %{} end)
      |> Map.new(fn t ->
        entries = Enum.map(t.troops, fn {nation_id, count} -> {nation_id, count} end)
        {t.id, entries}
      end)

    {owner_map, troop_map}
  end

  defp format_tick(tick) do
    day = div(tick, 24)
    "Day #{day} \u00B7 Tick #{tick}"
  end

  defp stability_class(stability) when stability > 0.6, do: "bg-success"
  defp stability_class(stability) when stability >= 0.3, do: "bg-warning"
  defp stability_class(_), do: "bg-error"

  defp stability_pct(stability) do
    "#{round(stability * 100)}%"
  end

  defp event_color("coup"), do: "text-error"
  defp event_color("famine"), do: "text-warning"
  defp event_color("default"), do: "text-error"
  defp event_color("nation_collapsed"), do: "text-error"
  defp event_color(_), do: "text-base-content/70"

  defp format_event_detail(%{event_type: "coup", payload: payload}) do
    old_gov = payload["old_government"] || Map.get(payload, :old_government, "?")
    new_gov = payload["new_government"] || Map.get(payload, :new_government, "?")
    "#{old_gov} \u2192 #{new_gov}"
  end

  defp format_event_detail(%{event_type: "famine"}) do
    "grain depleted"
  end

  defp format_event_detail(%{event_type: "default"}) do
    "treasury below zero"
  end

  defp format_event_detail(%{event_type: "nation_collapsed", payload: payload}) do
    pop = payload["population"] || Map.get(payload, :population, 0)
    "population: #{pop}"
  end

  defp format_event_detail(_), do: ""

  defp get_nation_value(state, key) do
    Map.get(state, key) || Map.get(state, to_string(key))
  end

  defp format_population(pop) when is_number(pop) and pop >= 1000 do
    "#{Float.round(pop / 1000.0, 1)}k"
  end

  defp format_population(pop) when is_number(pop), do: "#{pop}"
  defp format_population(_), do: "?"
end
