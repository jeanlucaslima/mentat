defmodule Mentat.Repo.Migrations.CreateActions do
  use Ecto.Migration

  def change do
    create table(:actions) do
      add :world_run_id, references(:world_runs, type: :binary_id, on_delete: :delete_all),
        null: false

      add :tick, :integer, null: false
      add :nation_id, :string, null: false
      add :action_type, :string, null: false
      add :payload, :map, null: false
      add :status, :string, null: false
      add :reason, :string

      timestamps(updated_at: false)
    end

    create index(:actions, [:world_run_id, :tick])
    create index(:actions, [:world_run_id, :nation_id])
  end
end
