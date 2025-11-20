defmodule Mosaic.Locations.Location do
  @moduledoc """
  Domain-specific module for Location entities.

  A Location wraps the generic Entity schema with location-specific business logic
  and validation. Locations can participate in events (e.g., shifts happen at locations).
  """

  @behaviour Mosaic.Entities.EntityWrapper

  import Ecto.Changeset
  alias Mosaic.Entities.Entity

  @impl Mosaic.Entities.EntityWrapper
  def entity_type, do: "location"

  @doc """
  Validates location-specific properties and returns a changeset.

  Required properties:
  - name: Name of the location
  - address: Physical address

  Optional properties:
  - capacity: Maximum number of people
  - facilities: List of available facilities
  - operating_hours: Operating hours information
  """
  def changeset(%Entity{} = entity, attrs) do
    entity
    |> Entity.changeset(Map.put(attrs, "entity_type", entity_type()))
    |> validate_location_properties()
  end

  @doc """
  Creates a new location entity struct with default values.
  """
  def new(attrs \\ %{}) do
    %Entity{entity_type: entity_type(), properties: %{}}
    |> changeset(attrs)
  end

  defp validate_location_properties(changeset) do
    case get_field(changeset, :properties) do
      %{} = props ->
        changeset
        |> validate_property_present(props, "name", "Name is required")
        |> validate_property_present(props, "address", "Address is required")
        |> validate_capacity(props)

      _ ->
        add_error(changeset, :properties, "must be a map")
    end
  end

  defp validate_property_present(changeset, props, key, message) do
    value = Map.get(props, key)

    if is_nil(value) or value == "" do
      add_error(changeset, :properties, message, field: key)
    else
      changeset
    end
  end

  defp validate_capacity(changeset, props) do
    capacity = Map.get(props, "capacity")

    if capacity && (!is_integer(capacity) || capacity < 0) do
      add_error(changeset, :properties, "Capacity must be a positive integer", field: "capacity")
    else
      changeset
    end
  end

  @doc """
  Extracts location properties from an entity for display/forms.
  """
  def from_entity(%Entity{entity_type: type, properties: properties}) when type == "location" do
    %{
      name: Map.get(properties, "name"),
      address: Map.get(properties, "address"),
      capacity: Map.get(properties, "capacity"),
      facilities: Map.get(properties, "facilities", []),
      operating_hours: Map.get(properties, "operating_hours")
    }
  end

  def from_entity(%Entity{}) do
    raise ArgumentError, "Entity must be of type '#{entity_type()}' to convert to Location"
  end

  @doc """
  Gets the location's name from properties.
  """
  def name(%Entity{properties: properties}) do
    Map.get(properties, "name")
  end

  @doc """
  Gets the location's address from properties.
  """
  def address(%Entity{properties: properties}) do
    Map.get(properties, "address")
  end
end
