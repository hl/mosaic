defmodule Mosaic.Repo.Migrations.CreateEventTypes do
  use Ecto.Migration

  def change do
    create table(:event_types, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false
      add :category, :string
      add :can_nest, :boolean, default: false
      add :can_have_children, :boolean, default: false
      add :requires_participation, :boolean, default: true
      add :schema, :map, default: %{}
      add :rules, :map, default: %{}
      add :is_active, :boolean, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:event_types, [:name])
    create index(:event_types, [:is_active])
  end
end
