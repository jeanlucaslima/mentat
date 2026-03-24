defmodule Mentat.Settings do
  @moduledoc """
  Manages application settings stored in priv/settings/config.json.
  """

  @doc "Returns the default scenario name."
  def default_scenario do
    case read() do
      %{"default_scenario" => name} when is_binary(name) -> name
      _ -> Application.get_env(:mentat, :scenario, "world_standard_42")
    end
  end

  @doc "Sets the default scenario. Validates the scenario directory exists."
  def set_default_scenario(name) do
    scenario_path = Path.join(scenarios_dir(), name)

    if File.dir?(scenario_path) do
      write(%{"default_scenario" => name})
    else
      {:error, "Scenario #{name} not found"}
    end
  end

  @doc "Reads the config file. Returns a map or empty map on failure."
  def read do
    case File.read(config_path()) do
      {:ok, contents} ->
        case Jason.decode(contents) do
          {:ok, data} -> data
          _ -> %{}
        end

      _ ->
        %{}
    end
  end

  @doc "Writes the config map to disk."
  def write(config) do
    dir = Path.dirname(config_path())
    File.mkdir_p!(dir)
    File.write!(config_path(), Jason.encode!(config, pretty: true))
    :ok
  end

  @doc "Lists all scenario directories in priv/scenarios/."
  def list_scenarios do
    case File.ls(scenarios_dir()) do
      {:ok, entries} ->
        entries
        |> Enum.filter(fn name ->
          File.dir?(Path.join(scenarios_dir(), name))
        end)
        |> Enum.map(fn name ->
          map_path = Path.join([scenarios_dir(), name, "map.json"])

          tile_count =
            case File.read(map_path) do
              {:ok, contents} ->
                case Jason.decode(contents) do
                  {:ok, %{"tiles" => tiles}} -> length(tiles)
                  _ -> 0
                end

              _ ->
                0
            end

          %{
            name: name,
            tile_count: tile_count,
            source: detect_source(name),
            modified: file_modified(map_path)
          }
        end)
        |> Enum.sort_by(& &1.name)

      _ ->
        []
    end
  end

  defp detect_source(name) do
    if String.starts_with?(name, "world_") and not String.contains?(name, "_standard_") and
         not String.contains?(name, "_archipelago_") and not String.contains?(name, "_pangea_") and
         not String.contains?(name, "_divided_") do
      "manual"
    else
      "generated"
    end
  end

  defp file_modified(path) do
    case File.stat(path) do
      {:ok, %{mtime: mtime}} ->
        mtime
        |> NaiveDateTime.from_erl!()
        |> NaiveDateTime.to_string()

      _ ->
        "unknown"
    end
  end

  defp config_path do
    Path.join([:code.priv_dir(:mentat), "settings", "config.json"])
  end

  defp scenarios_dir do
    Path.join(:code.priv_dir(:mentat), "scenarios")
  end
end
