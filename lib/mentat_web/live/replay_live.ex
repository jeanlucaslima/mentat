defmodule MentatWeb.ReplayLive do
  use MentatWeb, :live_view

  import MentatWeb.MapComponents,
    only: [
      grid_bounds: 1,
      tile_size: 0,
      padding: 0,
      voronoi?: 1,
      voronoi_viewbox: 1
    ]

  alias Mentat.Queries

  def mount(%{"id" => id}, _session, socket) do
    case Queries.get_run(id) do
      nil ->
        {:ok, push_navigate(socket, to: ~p"/runs")}

      run ->
        if connected?(socket) and run.status == "running" do
          Phoenix.PubSub.subscribe(Mentat.PubSub, "world:tick")
        end

        max_tick = Queries.get_run_max_tick(id)

        # Load scenario for tile geometry
        {:ok, scenario_data} = Mentat.ScenarioLoader.load(run.scenario_id)
        tile_coords = Map.new(scenario_data.tiles, &{&1.id, {&1.x, &1.y}})
        nation_map = Map.new(scenario_data.nations, &{&1.id, &1})
        capital_set = MapSet.new(scenario_data.nations, & &1.capital_tile_id)
        structure_map = MentatWeb.MapComponents.build_structure_map(scenario_data.structures)
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

        # Load state at tick 0
        {owner_map, troop_map, snapshots, events} = load_state_at_tick(id, 0, scenario_data)

        socket =
          socket
          |> assign(:page_title, "Mentat \u2014 #{run.scenario_id} Replay")
          |> assign(:run, run)
          |> assign(:max_tick, max_tick)
          |> assign(:current_tick, 0)
          |> assign(:tiles, scenario_data.tiles)
          |> assign(:tile_coords, tile_coords)
          |> assign(:nation_map, nation_map)
          |> assign(:capital_set, capital_set)
          |> assign(:structure_map, structure_map)
          |> assign(:owner_map, owner_map)
          |> assign(:troop_map, troop_map)
          |> assign(:snapshots, snapshots)
          |> assign(:events, events)
          |> assign(:scenario_data, scenario_data)
          |> assign(:viewbox_width, vw)
          |> assign(:viewbox_height, vh)
          |> assign(:is_voronoi, is_voronoi)
          |> assign(:playing, false)
          |> assign(:speed, 1)
          |> assign(:timer_ref, nil)

        {:ok, socket}
    end
  end

  def handle_event("seek", %{"tick" => tick_str}, socket) do
    if socket.assigns.timer_ref, do: Process.cancel_timer(socket.assigns.timer_ref)
    tick = String.to_integer(tick_str)

    {owner_map, troop_map, snapshots, events} =
      load_state_at_tick(socket.assigns.run.id, tick, socket.assigns.scenario_data)

    socket =
      socket
      |> assign(:current_tick, tick)
      |> assign(:owner_map, owner_map)
      |> assign(:troop_map, troop_map)
      |> assign(:snapshots, snapshots)
      |> assign(:events, events)
      |> assign(:playing, false)
      |> assign(:timer_ref, nil)

    {:noreply, socket}
  end

  def handle_event("play", _, socket) do
    ref = schedule_advance(socket.assigns.speed)
    {:noreply, assign(socket, playing: true, timer_ref: ref)}
  end

  def handle_event("pause", _, socket) do
    if socket.assigns.timer_ref, do: Process.cancel_timer(socket.assigns.timer_ref)
    {:noreply, assign(socket, playing: false, timer_ref: nil)}
  end

  def handle_event("step_forward", _, socket) do
    tick = min(socket.assigns.current_tick + 1, socket.assigns.max_tick)
    seek_to_tick(socket, tick)
  end

  def handle_event("step_back", _, socket) do
    tick = max(socket.assigns.current_tick - 1, 0)
    seek_to_tick(socket, tick)
  end

  def handle_event("set_speed", %{"speed" => speed_str}, socket) do
    speed = String.to_integer(speed_str)

    if socket.assigns.playing do
      if socket.assigns.timer_ref, do: Process.cancel_timer(socket.assigns.timer_ref)
      ref = schedule_advance(speed)
      {:noreply, assign(socket, speed: speed, timer_ref: ref)}
    else
      {:noreply, assign(socket, :speed, speed)}
    end
  end

  def handle_event("keydown", %{"key" => "ArrowRight"}, socket) do
    handle_event("step_forward", %{}, socket)
  end

  def handle_event("keydown", %{"key" => "ArrowLeft"}, socket) do
    handle_event("step_back", %{}, socket)
  end

  def handle_event("keydown", %{"key" => " "}, socket) do
    if socket.assigns.playing,
      do: handle_event("pause", %{}, socket),
      else: handle_event("play", %{}, socket)
  end

  def handle_event("keydown", _, socket), do: {:noreply, socket}

  def handle_info(:advance_tick, socket) do
    tick = socket.assigns.current_tick + 1

    if tick > socket.assigns.max_tick do
      {:noreply, assign(socket, playing: false, timer_ref: nil)}
    else
      {owner_map, troop_map, snapshots, events} =
        load_state_at_tick(socket.assigns.run.id, tick, socket.assigns.scenario_data)

      ref = schedule_advance(socket.assigns.speed)

      {:noreply,
       socket
       |> assign(:current_tick, tick)
       |> assign(:owner_map, owner_map)
       |> assign(:troop_map, troop_map)
       |> assign(:snapshots, snapshots)
       |> assign(:events, events)
       |> assign(:timer_ref, ref)}
    end
  end

  def handle_info({:tick, tick_info}, socket) do
    # Extend scrubber for live runs
    {:noreply, assign(socket, :max_tick, max(socket.assigns.max_tick, tick_info.tick))}
  end

  def handle_info({:nation_collapsed, _nation_id}, socket), do: {:noreply, socket}

  defp seek_to_tick(socket, tick) do
    {owner_map, troop_map, snapshots, events} =
      load_state_at_tick(socket.assigns.run.id, tick, socket.assigns.scenario_data)

    {:noreply,
     socket
     |> assign(:current_tick, tick)
     |> assign(:owner_map, owner_map)
     |> assign(:troop_map, troop_map)
     |> assign(:snapshots, snapshots)
     |> assign(:events, events)}
  end

  defp schedule_advance(speed) do
    Process.send_after(self(), :advance_tick, play_interval(speed))
  end

  defp play_interval(speed), do: max(div(200, speed), 50)

  defp load_state_at_tick(world_run_id, tick, scenario_data) do
    snapshots = Queries.get_nation_snapshots_at(world_run_id, tick)
    events = Queries.get_events_at(world_run_id, tick)
    tile_snapshots = Queries.get_tile_snapshots_at(world_run_id, tick)

    # Build owner_map from tile snapshots, or fall back to scenario data at tick 0
    {owner_map, troop_map} =
      if tile_snapshots == [] do
        # Use initial scenario data
        owner_map = MentatWeb.MapComponents.build_owner_map(scenario_data.nations)
        troop_map = MentatWeb.MapComponents.build_troop_map(scenario_data.nations)
        {owner_map, troop_map}
      else
        owner_map =
          Map.new(tile_snapshots, fn ts ->
            state = ts.state
            owner = Map.get(state, "owner") || Map.get(state, :owner)
            {ts.tile_id, owner}
          end)
          |> Enum.reject(fn {_k, v} -> is_nil(v) end)
          |> Map.new()

        troop_map =
          tile_snapshots
          |> Enum.reduce(%{}, fn ts, acc ->
            state = ts.state
            troops = Map.get(state, "troops") || Map.get(state, :troops, %{})

            if troops != %{} do
              entries =
                Enum.map(troops, fn {nation_id, count} -> {nation_id, count} end)

              Map.put(acc, ts.tile_id, entries)
            else
              acc
            end
          end)

        {owner_map, troop_map}
      end

    {owner_map, troop_map, snapshots, events}
  end

  defp format_tick(tick) do
    day = div(tick, 24)
    "Day #{day} \u00B7 Tick #{tick}"
  end

  defp stability_color(stability) when stability > 0.6, do: "#10b981"
  defp stability_color(stability) when stability >= 0.3, do: "#f59e0b"
  defp stability_color(_), do: "#ef4444"

  defp event_color("coup"), do: "text-[#ef4444]"
  defp event_color("famine"), do: "text-[#f59e0b]"
  defp event_color("default"), do: "text-[#ef4444]"
  defp event_color("nation_collapsed"), do: "text-[#ef4444]"
  defp event_color(_), do: "text-[#a8b8cc]"

  defp format_event_detail(%{event_type: "coup", payload: payload}) do
    old_gov = Map.get(payload, "old_government") || Map.get(payload, :old_government, "?")
    new_gov = Map.get(payload, "new_government") || Map.get(payload, :new_government, "?")
    "#{old_gov} \u2192 #{new_gov}"
  end

  defp format_event_detail(%{event_type: "famine"}), do: "grain depleted"
  defp format_event_detail(%{event_type: "default"}), do: "treasury below zero"

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
