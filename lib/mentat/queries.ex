defmodule Mentat.Queries do
  import Ecto.Query
  alias Mentat.Repo

  def list_runs do
    war_run_ids =
      from(e in "events",
        where: e.event_type == "war_declared",
        distinct: e.world_run_id,
        select: type(e.world_run_id, Ecto.UUID)
      )
      |> Repo.all()
      |> MapSet.new()

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
        max_tick: max(s.tick),
        nation_count: count(s.nation_id, :distinct)
      }
    )
    |> Repo.all()
    |> Enum.map(fn run -> Map.put(run, :has_wars, MapSet.member?(war_run_ids, run.id)) end)
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

  @critical_event_types ~w(coup nation_collapsed famine default)

  def get_recent_feed(world_run_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    nation_id = Keyword.get(opts, :nation_id)
    type_filter = Keyword.get(opts, :type_filter, :all)
    severity = Keyword.get(opts, :severity, :all)

    events =
      if type_filter != :actions do
        query =
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

        query = if nation_id, do: where(query, [e], e.nation_id == ^nation_id), else: query

        query =
          if severity == :critical,
            do: where(query, [e], e.event_type in ^@critical_event_types),
            else: query

        query
        |> Repo.all()
        |> Enum.map(fn e ->
          %{
            entry_type: "event",
            sub_type: e.event_type,
            nation_id: e.nation_id,
            payload: e.payload,
            tick: e.tick,
            status: nil,
            reason: nil
          }
        end)
      else
        []
      end

    actions =
      if type_filter != :events and severity != :critical do
        query =
          from(a in "actions",
            where: a.world_run_id == type(^world_run_id, Ecto.UUID),
            order_by: [desc: a.tick],
            limit: ^limit,
            select: %{
              action_type: a.action_type,
              nation_id: a.nation_id,
              payload: a.payload,
              tick: a.tick,
              status: a.status,
              reason: a.reason
            }
          )

        query = if nation_id, do: where(query, [a], a.nation_id == ^nation_id), else: query

        query
        |> Repo.all()
        |> Enum.map(fn a ->
          %{
            entry_type: "action",
            sub_type: a.action_type,
            nation_id: a.nation_id,
            payload: a.payload,
            tick: a.tick,
            status: a.status,
            reason: a.reason
          }
        end)
      else
        []
      end

    (events ++ actions)
    |> Enum.sort_by(& &1.tick, :desc)
    |> Enum.take(limit)
  end

  def get_feed_at(world_run_id, tick, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    nation_id = Keyword.get(opts, :nation_id)
    type_filter = Keyword.get(opts, :type_filter, :all)
    severity = Keyword.get(opts, :severity, :all)

    events =
      if type_filter != :actions do
        query =
          from(e in "events",
            where:
              e.world_run_id == type(^world_run_id, Ecto.UUID) and
                e.tick <= ^tick,
            order_by: [desc: e.tick],
            limit: ^limit,
            select: %{
              event_type: e.event_type,
              nation_id: e.nation_id,
              payload: e.payload,
              tick: e.tick
            }
          )

        query = if nation_id, do: where(query, [e], e.nation_id == ^nation_id), else: query

        query =
          if severity == :critical,
            do: where(query, [e], e.event_type in ^@critical_event_types),
            else: query

        query
        |> Repo.all()
        |> Enum.map(fn e ->
          %{
            entry_type: "event",
            sub_type: e.event_type,
            nation_id: e.nation_id,
            payload: e.payload,
            tick: e.tick,
            status: nil,
            reason: nil
          }
        end)
      else
        []
      end

    actions =
      if type_filter != :events and severity != :critical do
        query =
          from(a in "actions",
            where:
              a.world_run_id == type(^world_run_id, Ecto.UUID) and
                a.tick <= ^tick,
            order_by: [desc: a.tick],
            limit: ^limit,
            select: %{
              action_type: a.action_type,
              nation_id: a.nation_id,
              payload: a.payload,
              tick: a.tick,
              status: a.status,
              reason: a.reason
            }
          )

        query = if nation_id, do: where(query, [a], a.nation_id == ^nation_id), else: query

        query
        |> Repo.all()
        |> Enum.map(fn a ->
          %{
            entry_type: "action",
            sub_type: a.action_type,
            nation_id: a.nation_id,
            payload: a.payload,
            tick: a.tick,
            status: a.status,
            reason: a.reason
          }
        end)
      else
        []
      end

    (events ++ actions)
    |> Enum.sort_by(& &1.tick, :desc)
    |> Enum.take(limit)
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
