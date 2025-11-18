defmodule Mosaic.EventTypeBehaviour do
  @moduledoc """
  Behaviour for event type-specific implementations.
  Each event type module can implement this behaviour to provide custom changeset logic.
  """

  @doc """
  Returns a changeset for the event with event type-specific validations and transformations.
  """
  @callback changeset(event :: Ecto.Schema.t(), attrs :: map()) :: Ecto.Changeset.t()

  @doc """
  Gets the module that implements event type-specific logic for a given event type name.
  Returns nil if no implementation exists.
  """
  def module_for_name("shift"), do: Mosaic.EventTypes.Shift
  def module_for_name("employment"), do: Mosaic.EventTypes.Employment
  def module_for_name("work_period"), do: nil
  def module_for_name("break"), do: nil
  def module_for_name(_), do: nil

  @doc """
  Returns true if the event type has a custom implementation.
  """
  def has_implementation?(event_type_name) do
    !is_nil(module_for_name(event_type_name))
  end
end
