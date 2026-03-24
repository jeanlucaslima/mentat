defmodule MentatWeb.RunsLive do
  use MentatWeb, :live_view

  alias Mentat.{Queries, Simulation}

  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mentat.PubSub, "world:tick")
    end

    runs = Queries.list_runs() |> sort_runs()
    scenarios = list_scenarios()

    socket =
      socket
      |> assign(:page_title, "Mentat — Simulation Runs")
      |> assign(:runs, runs)
      |> assign(:scenarios, scenarios)
      |> assign(:show_form, false)
      |> assign(:form_error, nil)
      |> assign(
        :form,
        to_form(%{
          "scenario" => List.first(scenarios, ""),
          "label" => "",
          "tick_rate_ms" => "1000"
        })
      )

    {:ok, socket}
  end

  def handle_event("show_form", _params, socket) do
    {:noreply, assign(socket, :show_form, true)}
  end

  def handle_event("hide_form", _params, socket) do
    {:noreply, socket |> assign(:show_form, false) |> assign(:form_error, nil)}
  end

  def handle_event(
        "start_run",
        %{"scenario" => scenario, "label" => label, "tick_rate_ms" => tick_rate_ms},
        socket
      ) do
    tick_rate = String.to_integer(tick_rate_ms)

    case Simulation.start(scenario, tick_rate, label) do
      {:ok, world_run_id} ->
        {:noreply, push_navigate(socket, to: ~p"/runs/#{world_run_id}/live")}

      {:error, :already_running} ->
        {:noreply,
         assign(
           socket,
           :form_error,
           "A simulation is already running. Stop it before starting a new one."
         )}

      {:error, reason} ->
        {:noreply, assign(socket, :form_error, "Failed to start: #{inspect(reason)}")}
    end
  end

  def handle_event("stop_run", %{"id" => world_run_id}, socket) do
    Simulation.stop(world_run_id)
    runs = Queries.list_runs() |> sort_runs()
    {:noreply, assign(socket, :runs, runs)}
  end

  def handle_event("navigate_to_run", %{"id" => id, "status" => status}, socket) do
    path = if status == "running", do: ~p"/runs/#{id}/live", else: ~p"/runs/#{id}/replay"
    {:noreply, push_navigate(socket, to: path)}
  end

  def handle_info({:tick, tick_info}, socket) do
    runs =
      Enum.map(socket.assigns.runs, fn run ->
        if run.status == "running" do
          %{run | max_tick: tick_info.tick}
        else
          run
        end
      end)

    {:noreply, assign(socket, :runs, runs)}
  end

  defp sort_runs(runs) do
    Enum.sort_by(
      runs,
      fn run ->
        {if(run.status == "running", do: 0, else: 1), run.inserted_at}
      end,
      fn {status1, date1}, {status2, date2} ->
        if status1 == status2,
          do: DateTime.after?(date1, date2),
          else: status1 <= status2
      end
    )
  end

  defp list_scenarios do
    scenarios_path = Path.join(:code.priv_dir(:mentat), "scenarios")

    case File.ls(scenarios_path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn entry ->
          File.dir?(Path.join(scenarios_path, entry))
        end)
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  defp format_tick(nil), do: "No data"

  defp format_tick(tick) do
    day = div(tick, 24)
    "Day #{day} \u00B7 Tick #{tick}"
  end

  defp time_ago(nil), do: ""

  defp time_ago(datetime) do
    now = NaiveDateTime.utc_now()
    diff = NaiveDateTime.diff(now, datetime, :second)

    cond do
      diff < 60 -> "#{diff}s ago"
      diff < 3600 -> "#{div(diff, 60)} min ago"
      diff < 86400 -> "#{div(diff, 3600)} hrs ago"
      true -> "#{div(diff, 86400)} days ago"
    end
  end
end
