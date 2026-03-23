defmodule Mentat.Repo.Migrations.CreateWorldRuns do
  use Ecto.Migration

  def change do
    create table(:world_runs, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :scenario_id, :string, null: false
      add :status, :string, null: false
      add :tick_rate_ms, :integer, null: false

      timestamps(updated_at: false)
    end
  end
end
