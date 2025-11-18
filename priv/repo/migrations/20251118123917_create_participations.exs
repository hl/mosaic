defmodule Mosaic.Repo.Migrations.CreateParticipations do
  use Ecto.Migration

  def change do
    create table(:participations, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :participant_id, references(:entities, type: :binary_id, on_delete: :delete_all),
        null: false

      add :event_id, references(:events, type: :binary_id, on_delete: :delete_all), null: false
      add :participation_type, :string, null: false
      add :role, :string
      add :start_time, :utc_datetime
      add :end_time, :utc_datetime
      add :properties, :map, default: %{}

      timestamps(type: :utc_datetime)
    end

    create index(:participations, [:participant_id, :event_id])
    create index(:participations, [:event_id])
    create index(:participations, [:participation_type])

    create unique_index(:participations, [:participant_id, :event_id, :participation_type])
  end
end
