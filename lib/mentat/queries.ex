defmodule Mentat.Queries do
  import Ecto.Query
  alias Mentat.Repo

  def list_runs do
    from(r in "world_runs",
      left_join: s in "nation_snapshots",
      on: r.id == s.world_run_id,
      group_by: [r.id, r.scenario_id, r.status, r.tick_rate_ms, r.label, r.inserted_at],
      order_by: [desc: r.inserted_at],
      select: %{
        id: type(r.id, Ecto.UUID),
        scenario_id: r.scenario_id,
        status: r.status,
        tick_rate_ms: r.tick_rate_ms,
        label: r.label,
        inserted_at: r.inserted_at,
        max_tick: max(s.tick)
      }
    )
    |> Repo.all()
  end

  def get_run(id) do
    from(r in "world_runs",
      where: r.id == type(^id, Ecto.UUID),
      select: %{
        id: type(r.id, Ecto.UUID),
        scenario_id: r.scenario_id,
        status: r.status,
        tick_rate_ms: r.tick_rate_ms,
        label: r.label,
        inserted_at: r.inserted_at
      }
    )
    |> Repo.one()
  end

  def get_run_max_tick(world_run_id) do
    from(s in "nation_snapshots",
      where: s.world_run_id == type(^world_run_id, Ecto.UUID),
      select: max(s.tick)
    )
    |> Repo.one() || 0
  end

  def get_nation_snapshots_at(world_run_id, tick) do
    from(s in "nation_snapshots",
      where:
        s.world_run_id == type(^world_run_id, Ecto.UUID) and
          s.tick == ^tick,
      select: %{
        nation_id: s.nation_id,
        state: s.state
      }
    )
    |> Repo.all()
  end

  def get_tile_snapshots_at(world_run_id, tick) do
    nearest_tile_tick = div(tick, 24) * 24

    from(s in "tile_snapshots",
      where:
        s.world_run_id == type(^world_run_id, Ecto.UUID) and
          s.tick == ^nearest_tile_tick,
      select: %{
        tile_id: s.tile_id,
        state: s.state
      }
    )
    |> Repo.all()
  end

  def get_events_at(world_run_id, tick) do
    from(e in "events",
      where:
        e.world_run_id == type(^world_run_id, Ecto.UUID) and
          e.tick == ^tick,
      select: %{
        event_type: e.event_type,
        nation_id: e.nation_id,
        payload: e.payload,
        tick: e.tick
      }
    )
    |> Repo.all()
  end

  def get_recent_events(world_run_id, limit \\ 20) do
    from(e in "events",
      where: e.world_run_id == type(^world_run_id, Ecto.UUID),
      order_by: [desc: e.tick],
      limit: ^limit,
      select: %{
        event_type: e.event_type,
        nation_id: e.nation_id,
        payload: e.payload,
        tick: e.tick
      }
    )
    |> Repo.all()
  end

  def get_latest_nation_snapshots(world_run_id) do
    max_tick_subquery =
      from(s in "nation_snapshots",
        where: s.world_run_id == type(^world_run_id, Ecto.UUID),
        select: max(s.tick)
      )

    from(s in "nation_snapshots",
      where:
        s.world_run_id == type(^world_run_id, Ecto.UUID) and
          s.tick == subquery(max_tick_subquery),
      select: %{
        nation_id: s.nation_id,
        state: s.state,
        tick: s.tick
      }
    )
    |> Repo.all()
  end
end
