defmodule Mosaic.Repo.Migrations.CreateEntities do
  use Ecto.Migration

  def change do
    create table(:entities, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :entity_type, :string, null: false
      add :properties, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:entities, [:entity_type])
  end
end
