defmodule Mosaic.ChangesetHelpers do
  @moduledoc """
  Shared changeset helper functions for working with properties JSONB fields.
  """

  import Ecto.Changeset

  @doc """
  Casts property fields from attrs into the properties JSONB map.

  ## Parameters
  - changeset: The changeset to update
  - attrs: Input attributes (can have atom or string keys)
  - property_fields: List of field names to extract into properties

  ## Examples

      @property_fields [:location, :department, :notes]

      changeset
      |> cast_properties(attrs, @property_fields)
  """
  def cast_properties(changeset, attrs, property_fields) do
    properties = get_field(changeset, :properties, %{})

    # Merge property fields from attrs into properties map
    updated_properties =
      Enum.reduce(property_fields, properties, fn field, acc ->
        field_str = to_string(field)

        case Map.get(attrs, field) || Map.get(attrs, field_str) do
          nil -> acc
          value -> Map.put(acc, field_str, value)
        end
      end)

    put_change(changeset, :properties, updated_properties)
  end

  @doc """
  Validates that a property exists and is not empty.

  ## Parameters
  - changeset: The changeset to update
  - properties: The properties map
  - key: Property key to validate (string)
  - message: Error message if validation fails

  ## Examples

      properties = get_field(changeset, :properties) || %{}

      changeset
      |> validate_property_presence(properties, "location", "Location is required")
  """
  def validate_property_presence(changeset, properties, key, message) do
    value = Map.get(properties, key)

    if is_nil(value) || value == "" do
      add_error(changeset, :properties, message, field: key)
    else
      changeset
    end
  end
end
