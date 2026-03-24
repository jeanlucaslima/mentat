defmodule MentatWeb.SettingsLive do
  use MentatWeb, :live_view

  import MentatWeb.MapComponents,
    only: [
      build_owner_map: 1,
      build_structure_map: 1,
      build_troop_map: 1,
      voronoi?: 1,
      voronoi_viewbox: 1,
      grid_bounds: 1,
      tile_size: 0,
      padding: 0
    ]

  alias Mentat.Settings

  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Mentat \u2014 Settings")
      |> assign(:scenarios, Settings.list_scenarios())
      |> assign(:default_scenario, Settings.default_scenario())
      |> assign(:selected_preset, nil)
      |> assign(:seed, "")
      |> assign(:name, "")
      |> assign(:name_edited, false)
      |> assign(:show_advanced, false)
      |> assign(:min_distance, "")
      |> assign(:generation_state, :idle)
      |> assign(:generation_step, nil)
      |> assign(:generation_error, nil)
      |> assign(:generation_result, nil)
      |> assign(:preview_scenario, nil)
      |> assign(:preview_data, nil)
      |> assign(:delete_confirm, nil)
      |> assign(:task_ref, nil)

    {:ok, socket}
  end

  def handle_event("select_preset", %{"preset" => preset}, socket) do
    preset_atom = String.to_existing_atom(preset)

    socket =
      socket
      |> assign(:selected_preset, preset_atom)
      |> maybe_auto_name()

    {:noreply, socket}
  end

  def handle_event("update_seed", %{"value" => seed}, socket) do
    socket =
      socket
      |> assign(:seed, seed)
      |> assign(:name_edited, false)
      |> maybe_auto_name()

    {:noreply, socket}
  end

  def handle_event("update_name", %{"value" => name}, socket) do
    socket =
      socket
      |> assign(:name, name)
      |> assign(:name_edited, true)

    {:noreply, socket}
  end

  def handle_event("toggle_advanced", _params, socket) do
    {:noreply, assign(socket, :show_advanced, !socket.assigns.show_advanced)}
  end

  def handle_event("update_min_distance", %{"value" => val}, socket) do
    {:noreply, assign(socket, :min_distance, val)}
  end

  def handle_event("generate", _params, socket) do
    preset = socket.assigns.selected_preset
    seed_str = socket.assigns.seed
    name = socket.assigns.name

    if is_nil(preset) or name == "" do
      {:noreply, assign(socket, :generation_error, "Select a preset and provide a name")}
    else
      seed = if seed_str == "", do: nil, else: String.to_integer(seed_str)

      opts =
        [name: name, preset: preset, seed: seed]
        |> maybe_add_min_distance(socket.assigns.min_distance)

      lv_pid = self()

      task =
        Task.async(fn ->
          Mentat.MapGen.generate_with_progress(opts, fn step ->
            send(lv_pid, {:generation_progress, step})
          end)
        end)

      socket =
        socket
        |> assign(:generation_state, :generating)
        |> assign(:generation_step, "Starting...")
        |> assign(:generation_error, nil)
        |> assign(:generation_result, nil)
        |> assign(:task_ref, task.ref)

      {:noreply, socket}
    end
  end

  def handle_event("preview", %{"scenario" => scenario_name}, socket) do
    case Mentat.ScenarioLoader.load(scenario_name) do
      {:ok, data} ->
        is_voronoi = voronoi?(data.tiles)
        owner_map = build_owner_map(data.nations)
        nation_map = Map.new(data.nations, &{&1.id, &1})
        capital_set = MapSet.new(data.nations, & &1.capital_tile_id)
        structure_map = build_structure_map(data.structures)
        troop_map = build_troop_map(data.nations)
        tile_map = Map.new(data.tiles, &{&1.id, &1})

        {vw, vh} =
          if is_voronoi do
            voronoi_viewbox(data.tiles)
          else
            {max_x, max_y} = grid_bounds(data.tiles)
            ts = tile_size()
            pad = padding()
            {(max_x + 1) * ts + pad * 2, (max_y + 1) * ts + pad * 2}
          end

        preview_data = %{
          tiles: data.tiles,
          owner_map: owner_map,
          nation_map: nation_map,
          capital_set: capital_set,
          structure_map: structure_map,
          troop_map: troop_map,
          tile_map: tile_map,
          tile_coords: Map.new(data.tiles, &{&1.id, {&1.x, &1.y}}),
          viewbox_width: vw,
          viewbox_height: vh,
          is_voronoi: is_voronoi
        }

        socket =
          socket
          |> assign(:preview_scenario, scenario_name)
          |> assign(:preview_data, preview_data)

        {:noreply, socket}

      {:error, _reason} ->
        {:noreply, assign(socket, :generation_error, "Failed to load scenario for preview")}
    end
  end

  def handle_event("close_preview", _params, socket) do
    {:noreply, assign(socket, preview_scenario: nil, preview_data: nil)}
  end

  def handle_event("set_default", %{"scenario" => name}, socket) do
    Settings.set_default_scenario(name)

    {:noreply, assign(socket, :default_scenario, name)}
  end

  def handle_event("request_delete", %{"scenario" => name}, socket) do
    {:noreply, assign(socket, :delete_confirm, name)}
  end

  def handle_event("cancel_delete", _params, socket) do
    {:noreply, assign(socket, :delete_confirm, nil)}
  end

  def handle_event("confirm_delete", %{"scenario" => name}, socket) do
    if name == "world_01" or name == socket.assigns.default_scenario do
      {:noreply, assign(socket, :delete_confirm, nil)}
    else
      path = Path.join([:code.priv_dir(:mentat), "scenarios", name])
      File.rm_rf!(path)

      socket =
        socket
        |> assign(:delete_confirm, nil)
        |> assign(:scenarios, Settings.list_scenarios())
        |> assign(:preview_scenario, nil)
        |> assign(:preview_data, nil)

      {:noreply, socket}
    end
  end

  def handle_info({:generation_progress, step}, socket) do
    {:noreply, assign(socket, :generation_step, format_step(step))}
  end

  def handle_info({ref, result}, socket) when ref == socket.assigns.task_ref do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, gen_result} ->
        socket =
          socket
          |> assign(:generation_state, :done)
          |> assign(:generation_result, gen_result)
          |> assign(:generation_step, nil)
          |> assign(:scenarios, Settings.list_scenarios())
          |> assign(:task_ref, nil)

        {:noreply, socket}

      {:error, reason} ->
        socket =
          socket
          |> assign(:generation_state, :error)
          |> assign(:generation_error, reason)
          |> assign(:generation_step, nil)
          |> assign(:task_ref, nil)

        {:noreply, socket}
    end
  end

  def handle_info({:DOWN, ref, :process, _pid, _reason}, socket)
      when ref == socket.assigns.task_ref do
    socket =
      socket
      |> assign(:generation_state, :error)
      |> assign(:generation_error, "Generation process crashed")
      |> assign(:task_ref, nil)

    {:noreply, socket}
  end

  def handle_info(_msg, socket), do: {:noreply, socket}

  defp maybe_auto_name(socket) do
    if socket.assigns.name_edited do
      socket
    else
      preset = socket.assigns.selected_preset
      seed = socket.assigns.seed

      name =
        cond do
          is_nil(preset) -> ""
          seed == "" -> "world_#{preset}_random"
          true -> "world_#{preset}_#{seed}"
        end

      assign(socket, :name, name)
    end
  end

  defp maybe_add_min_distance(opts, "") do
    opts
  end

  defp maybe_add_min_distance(opts, val) do
    case Integer.parse(val) do
      {n, _} -> Keyword.put(opts, :min_distance, n)
      :error -> opts
    end
  end

  defp format_step(:placing_points), do: "Placing points..."
  defp format_step(:computing_adjacency), do: "Computing adjacency..."
  defp format_step(:computing_polygons), do: "Computing polygons..."
  defp format_step(:assigning_terrain), do: "Assigning terrain..."
  defp format_step(:placing_resources), do: "Placing resources..."
  defp format_step(:tracing_rivers), do: "Tracing rivers..."
  defp format_step(:placing_capitals), do: "Placing capitals..."
  defp format_step(:validating), do: "Validating..."
  defp format_step(:writing_files), do: "Writing files..."
  defp format_step(:verifying), do: "Verifying..."
  defp format_step(:done), do: "Complete!"
  defp format_step(step), do: "#{step}..."
end
