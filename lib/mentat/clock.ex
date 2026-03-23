defmodule Mentat.Clock do
  use GenServer
  require Logger

  # Public API

  def current_tick do
    GenServer.call(__MODULE__, :current_tick)
  end

  def pause do
    GenServer.call(__MODULE__, :pause)
  end

  def resume do
    GenServer.call(__MODULE__, :resume)
  end

  # GenServer

  def start_link(tick_rate_ms) do
    GenServer.start_link(__MODULE__, tick_rate_ms, name: __MODULE__)
  end

  @impl true
  def init(tick_rate_ms) do
    schedule_tick(tick_rate_ms)
    {:ok, %{tick: 0, running: true, tick_rate_ms: tick_rate_ms}}
  end

  @impl true
  def handle_call(:current_tick, _from, state) do
    {:reply, state.tick, state}
  end

  @impl true
  def handle_call(:pause, _from, state) do
    {:reply, :ok, %{state | running: false}}
  end

  @impl true
  def handle_call(:resume, _from, state) do
    if not state.running, do: schedule_tick(state.tick_rate_ms)
    {:reply, :ok, %{state | running: true}}
  end

  @impl true
  def handle_info(:tick, %{running: false} = state) do
    {:noreply, state}
  end

  @migration_delay_ms 50

  @impl true
  def handle_info(:tick, state) do
    tick = state.tick
    simulated_hour = rem(tick, 24)
    simulated_day = div(tick, 24)

    Phoenix.PubSub.broadcast(
      Mentat.PubSub,
      "world:tick",
      {:tick, %{tick: tick, hour: simulated_hour, day: simulated_day}}
    )

    if rem(tick, 24) == 0 do
      Logger.info("[Day #{simulated_day}] tick #{tick}")
    end

    Process.send_after(self(), :distribute_migration, @migration_delay_ms)
    schedule_tick(state.tick_rate_ms)
    {:noreply, %{state | tick: tick + 1}}
  end

  @impl true
  def handle_info(:distribute_migration, state) do
    Mentat.World.collect_and_distribute_migration()
    {:noreply, state}
  end

  defp schedule_tick(tick_rate_ms) do
    Process.send_after(self(), :tick, tick_rate_ms)
  end
end
