defmodule MentatWeb.RunLive do
  use MentatWeb, :live_view

  alias Mentat.{Queries, Simulation}

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

        socket =
          socket
          |> assign(:page_title, "Mentat — #{run.scenario_id} Live")
          |> assign(:run, run)
          |> assign(:snapshots, snapshots)
          |> assign(:events, events)
          |> assign(:tick, max_tick)

        {:ok, socket}
    end
  end

  def handle_event("stop_run", _params, socket) do
    Simulation.stop(socket.assigns.run.id)
    {:noreply, push_navigate(socket, to: ~p"/runs")}
  end

  def handle_info({:tick, tick_info}, socket) do
    snapshots = Queries.get_latest_nation_snapshots(socket.assigns.run.id)
    events = Queries.get_recent_events(socket.assigns.run.id, 20)

    socket =
      socket
      |> assign(:tick, tick_info.tick)
      |> assign(:snapshots, snapshots)
      |> assign(:events, events)

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

  defp format_tick(tick) do
    day = div(tick, 24)
    "Day #{day} \u00B7 Tick #{tick}"
  end

  defp stability_color(stability) when stability > 0.6, do: "#10b981"
  defp stability_color(stability) when stability >= 0.3, do: "#f59e0b"
  defp stability_color(_), do: "#ef4444"

  defp stability_pct(stability) do
    "#{round(stability * 100)}%"
  end

  defp event_color("coup"), do: "text-[#ef4444]"
  defp event_color("famine"), do: "text-[#f59e0b]"
  defp event_color("default"), do: "text-[#ef4444]"
  defp event_color("nation_collapsed"), do: "text-[#ef4444]"
  defp event_color(_), do: "text-[#a8b8cc]"

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
