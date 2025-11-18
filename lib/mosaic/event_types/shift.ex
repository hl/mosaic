defmodule Mosaic.EventTypes.Shift do
  @moduledoc """
  Shift-specific business logic and validations.
  """

  import Ecto.Changeset
  alias Mosaic.Event

  # Define which properties should be exposed as form fields
  @property_fields [:location, :department, :notes]

  @doc """
  Shift-specific changeset with custom validations.
  Handles virtual fields that get stored in properties map.
  """
  def changeset(event, attrs) do
    event
    |> Event.changeset(attrs)
    |> cast_properties_as_virtuals(attrs)
    |> validate_required([:end_time])
    |> validate_shift_properties()
    |> sync_virtuals_to_properties()
  end

  # Cast property fields from attrs into the properties map
  defp cast_properties_as_virtuals(changeset, attrs) do
    properties = get_field(changeset, :properties, %{})

    # Merge property fields from attrs into properties map
    updated_properties =
      Enum.reduce(@property_fields, properties, fn field, acc ->
        field_str = to_string(field)

        case Map.get(attrs, field) || Map.get(attrs, field_str) do
          nil -> acc
          value -> Map.put(acc, field_str, value)
        end
      end)

    put_change(changeset, :properties, updated_properties)
  end

  # For display: add properties as virtual fields in changeset data
  defp sync_virtuals_to_properties(changeset) do
    changeset
  end

  defp validate_shift_properties(changeset) do
    # Only validate properties if the changeset has an action (validation is active)
    # This prevents validation errors on initial empty forms
    case changeset.action do
      nil ->
        changeset

      _ ->
        properties = get_field(changeset, :properties) || %{}

        changeset
        |> validate_property_presence(properties, "location", "Location is required")
    end
  end

  defp validate_property_presence(changeset, properties, key, message) do
    value = Map.get(properties, key)

    if is_nil(value) || value == "" do
      add_error(changeset, :properties, message, field: key)
    else
      changeset
    end
  end
end
