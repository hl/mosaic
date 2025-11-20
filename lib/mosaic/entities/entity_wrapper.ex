defmodule Mosaic.Entities.EntityWrapper do
  @moduledoc """
  Behavior for entity wrapper modules.

  Entity wrappers provide domain-specific validation and business logic
  for specific entity types (workers, locations, etc).

  All entity wrapper modules must implement this behavior to ensure
  they define their entity_type.
  """

  @doc """
  Returns the entity type name for this wrapper.

  This function must return a string that matches the entity_type
  value stored in the entities table.

  ## Examples

      iex> Mosaic.Workers.Worker.entity_type()
      "person"

      iex> Mosaic.Locations.Location.entity_type()
      "location"
  """
  @callback entity_type() :: String.t()
end
