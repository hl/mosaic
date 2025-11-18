defmodule Mosaic.Participations.Participation do
  use Ecto.Schema
  import Ecto.Changeset

  alias Mosaic.Entities.Entity
  alias Mosaic.Events.Event

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "participations" do
    field :participation_type, :string
    field :role, :string
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :properties, :map, default: %{}

    belongs_to :participant, Entity
    belongs_to :event, Event

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(participation, attrs) do
    participation
    |> cast(attrs, [
      :participant_id,
      :event_id,
      :participation_type,
      :role,
      :start_time,
      :end_time,
      :properties
    ])
    |> validate_required([:participant_id, :event_id, :participation_type])
    |> validate_time_range()
    |> foreign_key_constraint(:participant_id)
    |> foreign_key_constraint(:event_id)
    |> unique_constraint([:participant_id, :event_id, :participation_type])
  end

  defp validate_time_range(changeset) do
    start_time = get_field(changeset, :start_time)
    end_time = get_field(changeset, :end_time)

    if start_time && end_time && DateTime.compare(end_time, start_time) != :gt do
      add_error(changeset, :end_time, "must be after start time")
    else
      changeset
    end
  end
end
