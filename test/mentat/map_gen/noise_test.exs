defmodule Mentat.MapGen.NoiseTest do
  use ExUnit.Case, async: true

  alias Mentat.MapGen.Noise

  describe "value_noise/3" do
    test "returns values between 0.0 and 1.0" do
      for x <- 0..10, y <- 0..10 do
        val = Noise.value_noise(x * 0.5, y * 0.5, 42)
        assert val >= 0.0 and val <= 1.0, "value_noise(#{x}, #{y}, 42) = #{val} out of range"
      end
    end

    test "same seed produces same output" do
      a = Noise.value_noise(3.5, 7.2, 42)
      b = Noise.value_noise(3.5, 7.2, 42)
      assert a == b
    end

    test "different seeds produce different output" do
      a = Noise.value_noise(3.5, 7.2, 42)
      b = Noise.value_noise(3.5, 7.2, 99)
      assert a != b
    end
  end

  describe "octave_noise/5" do
    test "returns values between 0.0 and 1.0" do
      for x <- 0..5, y <- 0..5 do
        val = Noise.octave_noise(x * 0.3, y * 0.3, 42)
        assert val >= 0.0 and val <= 1.0
      end
    end

    test "is deterministic" do
      a = Noise.octave_noise(1.5, 2.5, 42)
      b = Noise.octave_noise(1.5, 2.5, 42)
      assert a == b
    end
  end

  describe "smooth/2" do
    test "smoothing reduces variance" do
      values = %{0 => 0.0, 1 => 1.0, 2 => 0.0, 3 => 1.0, 4 => 0.0}
      adjacency = %{0 => [1], 1 => [0, 2], 2 => [1, 3], 3 => [2, 4], 4 => [3]}

      smoothed = Noise.smooth(values, adjacency)

      original_var = variance(Map.values(values))
      smoothed_var = variance(Map.values(smoothed))
      assert smoothed_var < original_var
    end
  end

  defp variance(vals) do
    mean = Enum.sum(vals) / length(vals)
    Enum.map(vals, fn v -> (v - mean) * (v - mean) end) |> Enum.sum() |> Kernel./(length(vals))
  end
end
