defprotocol Mosaic.Events.EventTypeBehaviour do
  @moduledoc """
  Protocol for event type-specific implementations.
  Each event type struct can implement this protocol to provide custom changeset logic.

  This protocol is implemented for the EventType struct and dispatches based on the
  event type's name field to the appropriate module.
  """

  @doc """
  Returns a changeset for the event with event type-specific validations and transformations.
  """
  @spec changeset(t(), Ecto.Schema.t(), map()) :: Ecto.Changeset.t()
  def changeset(event_type, event, attrs)
end

defimpl Mosaic.Events.EventTypeBehaviour, for: Mosaic.Events.EventType do
  @moduledoc """
  Protocol implementation that dispatches to event type-specific modules based on name.
  """

  alias Mosaic.Events.Event

  @doc """
  Dispatches to the appropriate event type module based on the EventType name.
  Falls back to generic Event.changeset if no specific implementation exists.
  """
  def changeset(%Mosaic.Events.EventType{name: "shift"}, event, attrs) do
    Mosaic.Shifts.Shift.changeset(event, attrs)
  end

  def changeset(%Mosaic.Events.EventType{name: "employment"}, event, attrs) do
    Mosaic.Employments.Employment.changeset(event, attrs)
  end

  # Fallback for event types without custom implementations
  def changeset(%Mosaic.Events.EventType{}, event, attrs) do
    Event.changeset(event, attrs)
  end
end
