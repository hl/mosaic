defmodule Mosaic.Events.EventWrapper do
  @moduledoc """
  Behavior for event wrapper modules.

  Event wrappers provide domain-specific validation and business logic
  for specific event types (shifts, employments, etc).

  All event wrapper modules must implement this behavior to ensure
  they define their event_type.
  """

  @doc """
  Returns the event type name for this wrapper.

  This function must return a string that matches the event type name
  in the event_types table.

  ## Examples

      iex> Mosaic.Shifts.Shift.event_type()
      "shift"

      iex> Mosaic.Employments.Employment.event_type()
      "employment"
  """
  @callback event_type() :: String.t()
end
