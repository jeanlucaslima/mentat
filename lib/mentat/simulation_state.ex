defmodule Mentat.SimulationState do
  use GenServer

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  def get do
    GenServer.call(__MODULE__, :get)
  end

  def set_running(world_run_id, scenario, started_at) do
    GenServer.call(__MODULE__, {:set_running, world_run_id, scenario, started_at})
  end

  def set_idle do
    GenServer.call(__MODULE__, :set_idle)
  end

  @impl true
  def init([]) do
    {:ok, %{status: :idle, world_run_id: nil, scenario: nil, started_at: nil}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:set_running, world_run_id, scenario, started_at}, _from, _state) do
    new_state = %{
      status: :running,
      world_run_id: world_run_id,
      scenario: scenario,
      started_at: started_at
    }

    {:reply, :ok, new_state}
  end

  @impl true
  def handle_call(:set_idle, _from, _state) do
    {:reply, :ok, %{status: :idle, world_run_id: nil, scenario: nil, started_at: nil}}
  end
end
