defmodule Mentat.MapGen.Terrain do
  @moduledoc """
  Assigns terrain types to tiles based on elevation and island mask.
  """

  alias Mentat.MapGen.Noise

  @terrain_thresholds [
    {0.28, "ocean", false, 99, 0},
    {0.35, "coast", true, 1, 1},
    {0.48, "plains", true, 1, 0},
    {0.58, "forest", true, 2, 2},
    {0.68, "hills", true, 3, 4},
    {1.01, "mountains", true, 5, 6}
  ]

  @doc """
  Assigns elevation, terrain type, and movement properties to each cell.
  `opts` must include `:width`, `:height`, and `:island_mask` params.
  """
  def assign(cells, seed, opts) do
    width = opts[:width]
    height = opts[:height]
    island_mask_params = opts[:island_mask] || %{}

    # Noise scale controls frequency: lower = broader terrain features
    noise_scale = Map.get(island_mask_params, :noise_scale, 3.0)

    # First pass: compute raw elevations
    raw_elevations =
      Map.new(cells, fn cell ->
        {cell.index,
         Noise.octave_noise(cell.cx / width * noise_scale, cell.cy / height * noise_scale, seed)}
      end)

    # Normalize noise to use full 0.0-1.0 range
    raw_vals = Map.values(raw_elevations)
    min_raw = Enum.min(raw_vals)
    max_raw = Enum.max(raw_vals)
    range = max(max_raw - min_raw, 0.001)

    cells_by_index = Map.new(cells, fn c -> {c.index, c} end)

    mask_params = Map.put(island_mask_params, :seed, seed)

    elevations =
      Map.new(raw_elevations, fn {idx, val} ->
        normalized = (val - min_raw) / range
        cell = Map.fetch!(cells_by_index, idx)
        mask = island_mask(cell.cx, cell.cy, width, height, mask_params)
        {idx, normalized * mask}
      end)

    # Build adjacency map for smoothing
    adjacency = Map.new(cells, fn cell -> {cell.index, cell.adjacent} end)

    # Smooth elevations
    smoothed = Noise.smooth(elevations, adjacency)

    Enum.map(cells, fn cell ->
      elev = Map.get(smoothed, cell.index, 0.0)
      {type, traversable, movement_cost, defensive_bonus} = type_from_elevation(elev)

      Map.merge(cell, %{
        elevation: elev,
        type: type,
        traversable: traversable,
        movement_cost: movement_cost,
        defensive_bonus: defensive_bonus
      })
    end)
  end

  @doc """
  Computes island mask value for a point. Returns 0.0-1.0.
  Reduces elevation near edges to ensure ocean borders.
  """
  def island_mask(x, y, width, height, params) do
    mode = Map.get(params, :mode, :single)

    case mode do
      :single ->
        single_peak_mask(x, y, width, height, params)

      :multi ->
        # Archipelago: multiple smaller peaks
        peaks = Map.get(params, :peaks, default_multi_peaks())
        multi_peak_mask(x, y, width, height, peaks, params)

      :divided ->
        # Two continents
        peaks = Map.get(params, :peaks, default_divided_peaks())
        multi_peak_mask(x, y, width, height, peaks, params)
    end
  end

  defp single_peak_mask(x, y, width, height, params) do
    radius = Map.get(params, :radius, 0.78)
    power = Map.get(params, :power, 2.0)

    # Normalize to [-1, 1]
    nx = x / width * 2.0 - 1.0
    ny = y / height * 2.0 - 1.0

    dist = :math.sqrt(nx * nx + ny * ny) / radius
    val = 1.0 - :math.pow(min(dist, 1.0), power)
    smooth = max(0.0, min(1.0, val))
    apply_noise_roughness(smooth, x, y, width, height, params)
  end

  defp multi_peak_mask(x, y, width, height, peaks, params) do
    # Take the maximum of all peak contributions
    smooth =
      peaks
      |> Enum.map(fn %{cx: pcx, cy: pcy, radius: r, power: p} ->
        nx = (x / width - pcx) * 2.0
        ny = (y / height - pcy) * 2.0
        dist = :math.sqrt(nx * nx + ny * ny) / r
        1.0 - :math.pow(min(dist, 1.0), p)
      end)
      |> Enum.max()
      |> max(0.0)
      |> min(1.0)

    apply_noise_roughness(smooth, x, y, width, height, params)
  end

  defp apply_noise_roughness(smooth_val, x, y, width, height, params) do
    case Map.get(params, :seed) do
      nil ->
        smooth_val

      seed ->
        nx = x / width * 2.0
        ny = y / height * 2.0
        noise = Noise.octave_noise(nx * 2.0, ny * 2.0, seed + 9999)
        val = smooth_val * 0.7 + noise * 0.3
        max(0.0, min(1.0, val))
    end
  end

  defp default_multi_peaks do
    [
      %{cx: 0.3, cy: 0.3, radius: 0.4, power: 2.5},
      %{cx: 0.7, cy: 0.5, radius: 0.35, power: 2.5},
      %{cx: 0.4, cy: 0.7, radius: 0.3, power: 2.5},
      %{cx: 0.8, cy: 0.8, radius: 0.25, power: 2.5}
    ]
  end

  defp default_divided_peaks do
    [
      %{cx: 0.25, cy: 0.5, radius: 0.5, power: 2.0},
      %{cx: 0.75, cy: 0.5, radius: 0.5, power: 2.0}
    ]
  end

  @doc """
  Returns `{type, traversable, movement_cost, defensive_bonus}` for an elevation value.
  """
  def type_from_elevation(elevation) do
    Enum.find_value(@terrain_thresholds, fn {threshold, type, traversable, mc, db} ->
      if elevation < threshold do
        {type, traversable, mc, db}
      end
    end)
  end
end
