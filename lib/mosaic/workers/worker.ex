defmodule Mosaic.Workers.Worker do
  @moduledoc """
  Domain-specific module for Worker entities.

  A Worker wraps the generic Entity schema with worker-specific business logic
  and validation. Workers are entities of type "person" that participate in
  employment and shift events.
  """

  import Ecto.Changeset
  alias Mosaic.Entities.Entity

  @doc """
  Validates worker-specific properties and returns a changeset.

  Required properties:
  - name: Full name of the worker
  - email: Valid email address

  Optional properties:
  - phone: Contact phone number
  - address: Physical address
  - emergency_contact: Emergency contact information
  """
  def changeset(%Entity{} = entity, attrs) do
    entity
    |> Entity.changeset(Map.put(attrs, :entity_type, "person"))
    |> validate_worker_properties()
  end

  @doc """
  Creates a new worker entity struct with default values.
  """
  def new(attrs \\ %{}) do
    %Entity{entity_type: "person", properties: %{}}
    |> changeset(attrs)
  end

  defp validate_worker_properties(changeset) do
    case get_field(changeset, :properties) do
      %{} = props ->
        changeset
        |> validate_property_present(props, "name", "Name is required")
        |> validate_property_present(props, "email", "Email is required")
        |> validate_email_format(props)

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

  defp validate_email_format(changeset, props) do
    email = Map.get(props, "email")

    if email && !String.match?(email, ~r/@/) do
      add_error(changeset, :properties, "Email must be valid", field: "email")
    else
      changeset
    end
  end

  @doc """
  Extracts worker properties from an entity for display/forms.
  """
  def from_entity(%Entity{entity_type: "person", properties: properties}) do
    %{
      name: Map.get(properties, "name"),
      email: Map.get(properties, "email"),
      phone: Map.get(properties, "phone"),
      address: Map.get(properties, "address"),
      emergency_contact: Map.get(properties, "emergency_contact")
    }
  end

  def from_entity(%Entity{}) do
    raise ArgumentError, "Entity must be of type 'person' to convert to Worker"
  end

  @doc """
  Gets the worker's name from properties.
  """
  def name(%Entity{properties: properties}) do
    Map.get(properties, "name")
  end

  @doc """
  Gets the worker's email from properties.
  """
  def email(%Entity{properties: properties}) do
    Map.get(properties, "email")
  end
end
