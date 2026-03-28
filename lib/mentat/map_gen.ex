defmodule Mentat.MapGen do
  @moduledoc """
  Top-level map generator pipeline.
  Assembles all map_gen modules in the correct order.
  """

  alias Mentat.MapGen.{
    PoissonDisk,
    Delaunay,
    Voronoi,
    Terrain,
    Resources,
    Rivers,
    Nations,
    Writer,
    Presets
  }

  @doc """
  Generates a complete scenario.

  Options:
  - `:name` (required) — scenario directory name
  - `:preset` (required) — preset atom (:standard, :archipelago, :pangea, :divided)
  - `:seed` — integer seed (random if nil)
  - `:width`, `:height`, `:min_distance` — optional overrides

  Returns `{:ok, %{name: name, tile_count: n, seed: seed}}` or `{:error, reason}`.
  """
  def generate(opts) do
    generate_with_progress(opts, fn _step -> :ok end)
  end

  @doc """
  Same as `generate/1` but calls `callback.(step_name)` between pipeline steps.
  """
  def generate_with_progress(opts, callback) do
    name = Keyword.fetch!(opts, :name)
    preset_name = Keyword.fetch!(opts, :preset)
    seed = Keyword.get(opts, :seed) || :rand.uniform(999_999)

    preset = Presets.get(preset_name)

    if is_nil(preset) do
      {:error, "Unknown preset: #{preset_name}"}
    else
      config = apply_overrides(preset, opts)
      run_pipeline(name, seed, config, callback)
    end
  end

  defp apply_overrides(preset, opts) do
    preset
    |> maybe_override(:width, opts)
    |> maybe_override(:height, opts)
    |> maybe_override(:min_distance, opts)
  end

  defp maybe_override(config, key, opts) do
    case Keyword.get(opts, key) do
      nil -> config
      val -> Map.put(config, key, val)
    end
  end

  defp run_pipeline(name, seed, config, callback) do
    %{
      width: width,
      height: height,
      min_distance: min_distance,
      river_count: river_count,
      island_mask: island_mask
    } = config

    callback.(:placing_points)
    points = PoissonDisk.sample(width, height, min_distance, seed)

    callback.(:computing_adjacency)
    triangles = Delaunay.triangulate(points)

    callback.(:computing_polygons)
    cells = Voronoi.from_delaunay(points, triangles, width, height)

    callback.(:assigning_terrain)
    cells = Terrain.assign(cells, seed, width: width, height: height, island_mask: island_mask)

    callback.(:placing_resources)
    cells = Resources.assign(cells, seed)

    callback.(:tracing_rivers)
    cells = Rivers.generate(cells, river_count, seed)

    callback.(:placing_capitals)

    case Nations.place_capitals(cells, 5, seed) do
      {:ok, nations} ->
        callback.(:placing_settlements)
        {nations, structures} = Nations.place_settlements(cells, nations)

        callback.(:validating)

        case Writer.validate(cells, nations) do
          :ok ->
            callback.(:writing_files)

            case Writer.write(name, cells, nations, structures: structures) do
              :ok ->
                callback.(:verifying)

                # Smoke test: verify the engine can load what we wrote
                case Mentat.ScenarioLoader.load(name) do
                  {:ok, _} ->
                    callback.(:done)
                    {:ok, %{name: name, tile_count: length(cells), seed: seed}}

                  {:error, reason} ->
                    {:error,
                     "Smoke test failed: generated files not loadable: #{inspect(reason)}"}
                end

              {:error, reason} ->
                {:error, "Write failed: #{reason}"}
            end

          {:error, reason} ->
            {:error, "Validation failed: #{reason}"}
        end

      {:error, reason} ->
        {:error, "Nation placement failed: #{reason}"}
    end
  end
end
