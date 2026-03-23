defmodule Mentat.MapGen.Noise do
  @moduledoc """
  Pure Elixir value noise for terrain generation.
  Deterministic: same (x, y, seed) always produces the same output.
  """

  @doc """
  Returns a float between 0.0 and 1.0 for the given coordinates and seed.
  Uses hash-based value noise with smoothstep interpolation.
  """
  def value_noise(x, y, seed) do
    x0 = floor(x)
    y0 = floor(y)
    x1 = x0 + 1
    y1 = y0 + 1

    fx = x - x0
    fy = y - y0

    sx = smoothstep(fx)
    sy = smoothstep(fy)

    n00 = hash(x0, y0, seed)
    n10 = hash(x1, y0, seed)
    n01 = hash(x0, y1, seed)
    n11 = hash(x1, y1, seed)

    nx0 = lerp(n00, n10, sx)
    nx1 = lerp(n01, n11, sx)

    lerp(nx0, nx1, sy)
  end

  @doc """
  Layered octave noise for more natural-looking terrain.
  Higher octaves add finer detail with decreasing amplitude.
  """
  def octave_noise(x, y, seed, octaves \\ 4, persistence \\ 0.5) do
    {total, max_val, _freq, _amp} =
      Enum.reduce(0..(octaves - 1), {0.0, 0.0, 1.0, 1.0}, fn _i, {total, max_val, freq, amp} ->
        val = value_noise(x * freq, y * freq, seed) * amp
        {total + val, max_val + amp, freq * 2.0, amp * persistence}
      end)

    total / max_val
  end

  @doc """
  Smooths values by averaging each with its neighbors' values.
  Takes a map of `%{index => value}` and an adjacency map of `%{index => [neighbor_indices]}`.
  Returns a new map of `%{index => smoothed_value}`.
  """
  def smooth(values, adjacency) do
    Map.new(values, fn {idx, val} ->
      neighbors = Map.get(adjacency, idx, [])

      neighbor_vals =
        Enum.reduce(neighbors, [], fn n_idx, acc ->
          case Map.get(values, n_idx) do
            nil -> acc
            v -> [v | acc]
          end
        end)

      smoothed =
        case neighbor_vals do
          [] -> val
          vals -> (val + Enum.sum(vals)) / (1 + length(vals))
        end

      {idx, smoothed}
    end)
  end

  defp smoothstep(t), do: t * t * (3.0 - 2.0 * t)

  defp lerp(a, b, t), do: a + (b - a) * t

  defp hash(x, y, seed) do
    :erlang.phash2({x, y, seed}, 1_000_000) / 1_000_000
  end
end
