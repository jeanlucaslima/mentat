defmodule Mentat.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events) do
      add :world_run_id, references(:world_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tick, :integer, null: false
      add :event_type, :string, null: false
      add :nation_id, :string
      add :tile_id, :string
      add :payload, :map, null: false

      timestamps(updated_at: false)
    end

    create index(:events, [:world_run_id, :tick])
    create index(:events, [:world_run_id, :event_type])
  end
end
