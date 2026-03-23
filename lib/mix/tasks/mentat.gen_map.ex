defmodule Mix.Tasks.Mentat.GenMap do
  @shortdoc "Generate a Voronoi map scenario"
  @moduledoc """
  Generates a new map scenario using Poisson disk sampling and Voronoi polygons.

  ## Usage

      mix mentat.gen_map --preset standard --seed 42 --name my_map

  ## Options

    * `--preset` - Preset name: standard, archipelago, pangea, divided (default: standard)
    * `--seed` - Integer seed for deterministic generation (default: random)
    * `--name` - Scenario name (default: auto-generated from preset and seed)
    * `--width` - Override map width
    * `--height` - Override map height
  """
  use Mix.Task

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          preset: :string,
          seed: :integer,
          name: :string,
          width: :integer,
          height: :integer
        ]
      )

    preset = String.to_atom(opts[:preset] || "standard")
    seed = opts[:seed]
    name = opts[:name] || auto_name(preset, seed)

    Mix.shell().info("Generating map: #{name} (preset: #{preset}, seed: #{seed || "random"})")
    Mix.shell().info("")

    start_time = System.monotonic_time(:millisecond)
    step_start = start_time

    callback = fn step ->
      now = System.monotonic_time(:millisecond)
      elapsed = now - step_start

      if step != :placing_points do
        Mix.shell().info("  #{format_step(step)} (#{elapsed}ms)")
      else
        Mix.shell().info("  #{format_step(step)}")
      end
    end

    gen_opts =
      [
        name: name,
        preset: preset,
        seed: seed,
        width: opts[:width],
        height: opts[:height]
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)

    case Mentat.MapGen.generate_with_progress(gen_opts, callback) do
      {:ok, result} ->
        total_ms = System.monotonic_time(:millisecond) - start_time

        Mix.shell().info("")

        Mix.shell().info(
          "Completed in #{total_ms / 1000}s — #{result.tile_count} tiles, seed #{result.seed}"
        )

        Mix.shell().info("Files written to priv/scenarios/#{result.name}/")

      {:error, reason} ->
        Mix.shell().error("Generation failed: #{reason}")
        System.halt(1)
    end
  end

  defp auto_name(preset, nil), do: "world_#{preset}_random"
  defp auto_name(preset, seed), do: "world_#{preset}_#{seed}"

  defp format_step(:placing_points), do: "Placing points..."
  defp format_step(:computing_adjacency), do: "Computing adjacency..."
  defp format_step(:computing_polygons), do: "Computing polygons..."
  defp format_step(:assigning_terrain), do: "Assigning terrain..."
  defp format_step(:placing_resources), do: "Placing resources..."
  defp format_step(:tracing_rivers), do: "Tracing rivers..."
  defp format_step(:placing_capitals), do: "Placing capitals..."
  defp format_step(:validating), do: "Validating..."
  defp format_step(:writing_files), do: "Writing files..."
  defp format_step(:verifying), do: "Verifying..."
  defp format_step(:done), do: "Done"
  defp format_step(step), do: "#{step}..."
end
