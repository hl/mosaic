defmodule Mosaic.Employments.Employment do
  @moduledoc """
  Employment-specific business logic and validations.
  """

  @behaviour Mosaic.Events.EventWrapper

  import Ecto.Changeset
  import Mosaic.ChangesetHelpers
  alias Mosaic.Events.Event

  # Define which properties should be exposed as form fields
  @property_fields [:role, :contract_type, :salary]

  @impl Mosaic.Events.EventWrapper
  def event_type, do: "employment"

  @doc """
  Employment-specific changeset with custom validations.
  Handles virtual fields that get stored in properties map.
  """
  def changeset(event, attrs) do
    event
    |> Event.changeset(attrs)
    |> cast_properties(attrs, @property_fields)
    |> validate_employment_properties()
  end

  defp validate_employment_properties(changeset) do
    # Only validate properties if the changeset has an action (validation is active)
    # This prevents validation errors on initial empty forms
    case changeset.action do
      nil ->
        changeset

      _ ->
        properties = get_field(changeset, :properties) || %{}

        changeset
        |> validate_property_presence(properties, "contract_type", "Contract type is required")
        |> validate_property_presence(properties, "role", "Role is required")
    end
  end
end
