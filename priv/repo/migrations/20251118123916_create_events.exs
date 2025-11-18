defmodule Mosaic.Repo.Migrations.CreateEvents do
  use Ecto.Migration

  def change do
    create table(:events, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :event_type_id, references(:event_types, type: :binary_id, on_delete: :restrict),
        null: false

      add :parent_id, references(:events, type: :binary_id, on_delete: :nilify_all)
      add :start_time, :utc_datetime, null: false
      add :end_time, :utc_datetime
      add :status, :string, default: "draft"
      add :properties, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:events, [:start_time, :end_time])
    create index(:events, [:parent_id])
    create index(:events, [:event_type_id, :start_time])
    create index(:events, [:status])

    execute(
      "CREATE INDEX events_properties_gin_idx ON events USING GIN (properties)",
      "DROP INDEX events_properties_gin_idx"
    )
  end
end
