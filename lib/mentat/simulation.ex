defmodule Mentat.Simulation do
  require Logger

  alias Mentat.{SimulationState, PersistenceWorker, World, Clock, Nation, Repo}

  def start(scenario, tick_rate_ms, label) do
    case SimulationState.get() do
      %{status: :running} ->
        {:error, :already_running}

      _ ->
        case World.reload(scenario) do
          :ok ->
            world_run_id = Ecto.UUID.generate()
            now = DateTime.utc_now() |> DateTime.truncate(:second)

            Repo.insert_all("world_runs", [
              %{
                id: Ecto.UUID.dump!(world_run_id),
                scenario_id: scenario,
                status: "running",
                tick_rate_ms: tick_rate_ms,
                label: label,
                inserted_at: now
              }
            ])

            PersistenceWorker.set_world_run_id(world_run_id)

            nations = World.get_all_nations()

            Enum.each(nations, fn nation ->
              {:ok, _pid} =
                DynamicSupervisor.start_child(
                  Mentat.NationSupervisor,
                  {Nation, {nation.id, world_run_id}}
                )
            end)

            {:ok, _pid} =
              DynamicSupervisor.start_child(
                Mentat.NationSupervisor,
                {Clock, tick_rate_ms}
              )

            SimulationState.set_running(world_run_id, scenario, now)
            Logger.info("Simulation started: #{world_run_id} (#{scenario})")
            {:ok, world_run_id}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  def stop(world_run_id) do
    # Pause clock first to stop new ticks
    try do
      Clock.pause()
    catch
      :exit, _ -> :ok
    end

    # Stop all children under NationSupervisor (Clock + Nations)
    DynamicSupervisor.which_children(Mentat.NationSupervisor)
    |> Enum.each(fn {_, pid, _, _} ->
      DynamicSupervisor.terminate_child(Mentat.NationSupervisor, pid)
    end)

    # Flush pending writes
    PersistenceWorker.flush_sync()

    # Mark run as stopped in database
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.query!(
      "UPDATE world_runs SET status = 'stopped' WHERE id = $1",
      [Ecto.UUID.dump!(world_run_id)]
    )

    _ = now

    # Reset state
    PersistenceWorker.set_world_run_id(nil)
    SimulationState.set_idle()

    Logger.info("Simulation stopped: #{world_run_id}")
    :ok
  end

  def status do
    case SimulationState.get() do
      %{status: :running, world_run_id: id} ->
        tick =
          try do
            Clock.current_tick()
          catch
            :exit, _ -> 0
          end

        {:running, id, tick}

      _ ->
        :idle
    end
  end
end
