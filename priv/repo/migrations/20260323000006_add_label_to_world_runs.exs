defmodule Mentat.Repo.Migrations.AddLabelToWorldRuns do
  use Ecto.Migration

  def change do
    alter table(:world_runs) do
      add :label, :string
    end
  end
end
