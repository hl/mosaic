defmodule Mosaic.Schedules do
  @moduledoc """
  The Schedules context handles schedule-specific business logic.

  Schedules are planning documents that define staffing requirements for locations.
  They parent shifts and support draft/publish workflows.
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Events.Event
  alias Mosaic.Events
  alias Mosaic.Participations.Participation
  alias Mosaic.Schedules.Schedule

  @doc """
  Creates a schedule for a location.
  Returns {:ok, {schedule, participation}} or {:error, changeset}.

  Attrs should include:
  - start_time (required)
  - end_time (required)
  - status (optional, defaults to "draft")
  - properties (optional, can include timezone, recurrence_rule, coverage_notes, version)
  """
  def create_schedule(location_id, attrs \\ %{}) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name(Schedule.event_type()),
           attrs <-
             Map.merge(attrs, %{
               "event_type_id" => event_type.id,
               "status" => attrs["status"] || attrs[:status] || "draft"
             }),
           # Set default properties
           attrs <-
             update_in(attrs, ["properties"], fn props ->
               props = props || %{}

               props
               |> Map.put_new("timezone", "UTC")
               |> Map.put_new("version", 1)
             end),
           changeset <- %Event{} |> Schedule.changeset(attrs),
           {:ok, schedule} <- Repo.insert(changeset),
           participation_attrs <- %{
             "participant_id" => location_id,
             "event_id" => schedule.id,
             "participation_type" => "location_scope",
             "properties" => %{}
           },
           {:ok, participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        {schedule, participation}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates a schedule.
  """
  def update_schedule(%Event{} = schedule, attrs) do
    schedule
    |> Schedule.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Publishes a schedule (changes status to active).
  """
  def publish_schedule(schedule_id) do
    with {:ok, schedule} <- validate_schedule(schedule_id) do
      Events.update_event(schedule, %{
        "status" => "active",
        "properties" =>
          Map.merge(schedule.properties, %{
            "published_at" => DateTime.utc_now()
          })
      })
    end
  end

  @doc """
  Archives a schedule (sets status to completed).
  """
  def archive_schedule(schedule_id) do
    with {:ok, schedule} <- validate_schedule(schedule_id) do
      Events.update_event(schedule, %{
        "status" => "completed"
      })
    end
  end

  @doc """
  Gets a single schedule.
  """
  def get_schedule!(id) do
    event = Repo.get!(Event, id) |> Repo.preload(:event_type)

    if event.event_type.name != Schedule.event_type() do
      raise Ecto.NoResultsError, queryable: Event
    end

    event
  end

  @doc """
  Lists all schedules.
  """
  def list_schedules do
    Events.list_events_by_type(Schedule.event_type(),
      preload: [:event_type, :children, participations: :participant],
      order_by: [desc: :start_time]
    )
  end

  @doc """
  Lists all schedules for a location.
  """
  def list_schedules_for_location(location_id) do
    from(e in Event,
      join: et in assoc(e, :event_type),
      join: p in assoc(e, :participations),
      where: et.name == ^Schedule.event_type(),
      where: p.participant_id == ^location_id,
      where: p.participation_type == "location_scope",
      order_by: [desc: e.start_time],
      preload: [:event_type, :children, participations: :participant]
    )
    |> Repo.all()
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking schedule changes.
  """
  def change_schedule(%Event{} = schedule, attrs \\ %{}) do
    Schedule.changeset(schedule, attrs)
  end

  # Private helper functions

  defp validate_schedule(schedule_id) do
    Events.validate_event_type(schedule_id, Schedule.event_type(), preload: [:event_type])
  end
end
