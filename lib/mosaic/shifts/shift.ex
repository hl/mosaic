defmodule Mosaic.Shifts.Shift do
  @moduledoc """
  Shift-specific business logic and validations.
  """

  import Ecto.Changeset
  import Mosaic.ChangesetHelpers
  alias Mosaic.Events.Event

  # Define which properties should be exposed as form fields
  @property_fields [:location, :department, :notes]

  @doc """
  Shift-specific changeset with custom validations.
  Handles virtual fields that get stored in properties map.
  """
  def changeset(event, attrs) do
    event
    |> Event.changeset(attrs)
    |> cast_properties(attrs, @property_fields)
    |> validate_required([:end_time])
    |> validate_shift_properties()
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
end
