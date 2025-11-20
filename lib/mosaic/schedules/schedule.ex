defmodule Mosaic.Schedules.Schedule do
  @moduledoc """
  Schedule-specific business logic and validations.

  Schedules are planning documents that define staffing requirements for a location
  over a period of time. They can parent shifts and have draft/active/archived status.
  """

  @behaviour Mosaic.Events.EventWrapper

  import Ecto.Changeset
  import Mosaic.ChangesetHelpers
  alias Mosaic.Events.Event

  # Define which properties should be exposed as form fields
  @property_fields [:timezone, :recurrence_rule, :coverage_notes, :version, :published_at]

  @impl Mosaic.Events.EventWrapper
  def event_type, do: "schedule"

  @doc """
  Schedule-specific changeset with custom validations.
  Handles virtual fields that get stored in properties map.
  """
  def changeset(event, attrs) do
    event
    |> Event.changeset(attrs)
    |> cast_properties(attrs, @property_fields)
    |> validate_required([:end_time])
    |> validate_schedule_properties()
  end

  defp validate_schedule_properties(changeset) do
    # Only validate properties if the changeset has an action (validation is active)
    case changeset.action do
      nil ->
        changeset

      _ ->
        properties = get_field(changeset, :properties) || %{}

        changeset
        |> validate_timezone(properties)
        |> validate_version(properties)
    end
  end

  defp validate_timezone(changeset, properties) do
    timezone = Map.get(properties, "timezone", "UTC")

    # Basic timezone validation - check if it's a string
    if is_binary(timezone) do
      changeset
    else
      add_error(changeset, :properties, "Timezone must be a string", field: "timezone")
    end
  end

  defp validate_version(changeset, properties) do
    version = Map.get(properties, "version")

    cond do
      is_nil(version) ->
        changeset

      is_integer(version) and version > 0 ->
        changeset

      true ->
        add_error(changeset, :properties, "Version must be a positive integer", field: "version")
    end
  end
end
