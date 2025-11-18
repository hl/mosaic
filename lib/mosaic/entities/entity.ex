defmodule Mosaic.Entities.Entity do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mosaic.Participations.Participation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "entities" do
    field :entity_type, :string
    field :properties, :map, default: %{}

    has_many :participations, Participation, foreign_key: :participant_id

    timestamps(type: :utc_datetime)
  end

  @entity_types ~w(person organization location resource)

  @doc false
  def changeset(entity, attrs) do
    entity
    |> cast(attrs, [:entity_type, :properties])
    |> validate_required([:entity_type])
    |> validate_inclusion(:entity_type, @entity_types)
  end
end
