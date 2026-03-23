defmodule Mentat.PersistenceWorker do
  use GenServer
  require Logger

  @flush_interval_ms 500
  @flush_threshold 50

  # Public API — all casts, never blocking

  def save_snapshot(tick, nation_id, state) do
    GenServer.cast(__MODULE__, {:snapshot, tick, nation_id, state})
  end

  def save_tile_snapshots(tick, tiles) do
    GenServer.cast(__MODULE__, {:tile_snapshots, tick, tiles})
  end

  def save_event(tick, type, nation_id, payload) do
    GenServer.cast(__MODULE__, {:event, tick, type, nation_id, payload})
  end

  def save_action(tick, nation_id, action_type, payload, status, reason \\ nil) do
    GenServer.cast(__MODULE__, {:action, tick, nation_id, action_type, payload, status, reason})
  end

  def get_world_run_id do
    GenServer.call(__MODULE__, :get_world_run_id)
  end

  # GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @impl true
  def init([]) do
    world_run_id = Ecto.UUID.generate()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Mentat.Repo.insert_all("world_runs", [
      %{
        id: Ecto.UUID.dump!(world_run_id),
        scenario_id: Application.get_env(:mentat, :scenario, "world_01"),
        status: "running",
        tick_rate_ms: Application.get_env(:mentat, :tick_rate_ms, 1000),
        inserted_at: now
      }
    ])

    schedule_flush()
    Logger.info("PersistenceWorker started, world_run_id: #{world_run_id}")

    {:ok,
     %{
       world_run_id: world_run_id,
       world_run_id_bin: Ecto.UUID.dump!(world_run_id),
       queue: %{nation_snapshots: [], tile_snapshots: [], events: [], actions: []},
       queue_size: 0
     }}
  end

  @impl true
  def handle_call(:get_world_run_id, _from, state) do
    {:reply, state.world_run_id, state}
  end

  @impl true
  def handle_cast({:snapshot, tick, nation_id, nation_state}, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    row = %{
      world_run_id: state.world_run_id_bin,
      tick: tick,
      nation_id: nation_id,
      state: nation_state,
      inserted_at: now
    }

    state = enqueue(state, :nation_snapshots, [row])
    {:noreply, maybe_flush(state)}
  end

  @impl true
  def handle_cast({:tile_snapshots, tick, tiles}, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    rows =
      Enum.map(tiles, fn tile ->
        %{
          world_run_id: state.world_run_id_bin,
          tick: tick,
          tile_id: tile.id,
          state: tile,
          inserted_at: now
        }
      end)

    state = enqueue(state, :tile_snapshots, rows)
    {:noreply, maybe_flush(state)}
  end

  @impl true
  def handle_cast({:event, tick, type, nation_id, payload}, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    row = %{
      world_run_id: state.world_run_id_bin,
      tick: tick,
      event_type: to_string(type),
      nation_id: nation_id,
      tile_id: nil,
      payload: payload,
      inserted_at: now
    }

    state = enqueue(state, :events, [row])
    {:noreply, maybe_flush(state)}
  end

  @impl true
  def handle_cast({:action, tick, nation_id, action_type, payload, status, reason}, state) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    row = %{
      world_run_id: state.world_run_id_bin,
      tick: tick,
      nation_id: nation_id,
      action_type: to_string(action_type),
      payload: payload,
      status: to_string(status),
      reason: reason,
      inserted_at: now
    }

    state = enqueue(state, :actions, [row])
    {:noreply, maybe_flush(state)}
  end

  @impl true
  def handle_info(:flush, state) do
    state = flush(state)
    schedule_flush()
    {:noreply, state}
  end

  # Private helpers

  defp enqueue(state, table_key, rows) do
    queue = Map.update!(state.queue, table_key, &(&1 ++ rows))
    %{state | queue: queue, queue_size: state.queue_size + length(rows)}
  end

  defp maybe_flush(state) do
    if state.queue_size >= @flush_threshold, do: flush(state), else: state
  end

  defp flush(state) do
    queue = state.queue

    if queue.nation_snapshots != [],
      do: Mentat.Repo.insert_all("nation_snapshots", queue.nation_snapshots)

    if queue.tile_snapshots != [],
      do: Mentat.Repo.insert_all("tile_snapshots", queue.tile_snapshots)

    if queue.events != [], do: Mentat.Repo.insert_all("events", queue.events)
    if queue.actions != [], do: Mentat.Repo.insert_all("actions", queue.actions)

    %{
      state
      | queue: %{nation_snapshots: [], tile_snapshots: [], events: [], actions: []},
        queue_size: 0
    }
  end

  defp schedule_flush do
    Process.send_after(self(), :flush, @flush_interval_ms)
  end
end
