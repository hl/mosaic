defmodule Mosaic.Events.EventType do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mosaic.Events.Event

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "event_types" do
    field :name, :string
    field :category, :string
    field :can_nest, :boolean, default: false
    field :can_have_children, :boolean, default: false
    field :requires_participation, :boolean, default: true
    field :schema, :map, default: %{}
    field :rules, :map, default: %{}
    field :is_active, :boolean, default: true

    has_many :events, Event

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(event_type, attrs) do
    event_type
    |> cast(attrs, [
      :name,
      :category,
      :can_nest,
      :can_have_children,
      :requires_participation,
      :schema,
      :rules,
      :is_active
    ])
    |> validate_required([:name])
    |> unique_constraint(:name)
  end
end
