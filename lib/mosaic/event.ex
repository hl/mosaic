defmodule Mosaic.Event do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "events" do
    field :start_time, :utc_datetime
    field :end_time, :utc_datetime
    field :status, :string, default: "draft"
    field :properties, :map, default: %{}

    belongs_to :event_type, Mosaic.EventType
    belongs_to :parent, Mosaic.Event

    has_many :children, Mosaic.Event, foreign_key: :parent_id
    has_many :participations, Mosaic.Participation

    timestamps(type: :utc_datetime)
  end

  @valid_statuses ~w(draft active completed cancelled)

  @doc false
  def changeset(event, attrs) do
    event
    |> cast(attrs, [:event_type_id, :parent_id, :start_time, :end_time, :status, :properties])
    |> validate_required([:event_type_id, :start_time])
    |> validate_inclusion(:status, @valid_statuses)
    |> validate_time_range()
    |> foreign_key_constraint(:event_type_id)
    |> foreign_key_constraint(:parent_id)
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

  @doc """
  Calculate duration in hours between start_time and end_time.
  """
  def duration_hours(%__MODULE__{start_time: start_time, end_time: end_time})
      when not is_nil(start_time) and not is_nil(end_time) do
    DateTime.diff(end_time, start_time, :second) / 3600
  end

  def duration_hours(_), do: nil
end
