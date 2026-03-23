defmodule Mentat.Repo.Migrations.CreateTileSnapshots do
  use Ecto.Migration

  def change do
    create table(:tile_snapshots) do
      add :world_run_id, references(:world_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tick, :integer, null: false
      add :tile_id, :string, null: false
      add :state, :map, null: false

      timestamps(updated_at: false)
    end

    create index(:tile_snapshots, [:world_run_id, :tick])
  end
end
