defmodule Mosaic.Employments do
  @moduledoc """
  The Employments context handles employment period specific business logic.
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Events.Event
  alias Mosaic.Events
  alias Mosaic.Participations.Participation
  alias Mosaic.Employments.Employment

  @doc """
  Creates an employment period for a worker.
  Returns {:ok, {event, participation}} or {:error, changeset}.

  Attrs should include:
  - start_time (required)
  - end_time (optional)
  - status (optional, defaults to "draft")
  - role (optional, stored in participation)
  - properties (optional, can include salary, contract_type, etc.)
  """
  def create_employment(worker_id, attrs \\ %{}) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name(Employment.event_type()),
           attrs <- Map.put(attrs, "event_type_id", event_type.id),
           {:ok, event} <- Events.create_event(attrs),
           :ok <- validate_no_overlapping_employments(worker_id, event, nil),
           participation_attrs <- %{
             "participant_id" => worker_id,
             "event_id" => event.id,
             "participation_type" => "employee",
             "role" => attrs["role"] || attrs[:role],
             "properties" =>
               attrs["participation_properties"] || attrs[:participation_properties] || %{}
           },
           {:ok, participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        {event, participation}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Updates an employment period.
  """
  def update_employment(employment_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, employment} <- validate_employment(employment_id),
           # Use changeset to get merged values for validation
           changeset <- Event.changeset(employment, attrs),
           merged_employment <- Ecto.Changeset.apply_changes(changeset),
           :ok <-
             validate_no_overlapping_employments(
               get_worker_id(employment),
               merged_employment,
               employment_id
             ),
           {:ok, updated_employment} <- Events.update_event(employment, attrs) do
        updated_employment
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Gets an employment by ID with preloaded associations.
  """
  def get_employment!(id) do
    Events.get_event!(id, preload: [:event_type, :children, participations: :participant])
  end

  @doc """
  Lists all employment periods.
  """
  def list_employments do
    Events.list_events_by_type(Employment.event_type(),
      preload: [:event_type, participations: :participant],
      order_by: [desc: :start_time]
    )
  end

  @doc """
  Lists all employment periods for a worker.
  """
  def list_employments_for_worker(worker_id) do
    Events.list_events_for_participant(Employment.event_type(), worker_id,
      preload: [:event_type, participations: :participant]
    )
    # Events.list_events_for_participant orders by asc, but we want desc for employments
    |> Enum.reverse()
  end

  @doc """
  Counts active employments for a worker.
  """
  def count_active_employments(worker_id) do
    query =
      from e in Event,
        join: et in assoc(e, :event_type),
        join: p in assoc(e, :participations),
        where:
          et.name == ^Employment.event_type() and
            p.participant_id == ^worker_id and
            e.status == "active",
        select: count(e.id)

    Repo.one(query)
  end

  @doc """
  Validates that a worker doesn't have overlapping active employment periods.
  """
  def validate_no_overlapping_employments(worker_id, employment, exclude_id) do
    start_time = employment.start_time

    # Skip validation if start_time is nil - it will be caught by required validation
    if is_nil(start_time) do
      :ok
    else
      with base_query <- build_base_employment_query(worker_id),
           overlap_query <- build_overlap_query(base_query, start_time, employment.end_time),
           final_query <- maybe_exclude_id(overlap_query, exclude_id),
           0 <- Repo.one(from e in final_query, select: count(e.id)) do
        :ok
      else
        _ -> {:error, "Worker has overlapping active employment periods"}
      end
    end
  end

  defp build_base_employment_query(worker_id) do
    from e in Event,
      join: et in assoc(e, :event_type),
      join: p in assoc(e, :participations),
      where:
        et.name == ^Employment.event_type() and
          p.participant_id == ^worker_id and
          e.status == "active"
  end

  defp build_overlap_query(base_query, start_time, nil) do
    # Employment has no end date (ongoing) - overlaps with anything that doesn't end before start
    from [e, et, p] in base_query,
      where: is_nil(e.end_time) or e.end_time > ^start_time
  end

  defp build_overlap_query(base_query, start_time, end_time) do
    # Employment has both start and end - check for overlaps
    from [e, et, p] in base_query,
      where:
        (is_nil(e.end_time) and e.start_time < ^end_time) or
          (not is_nil(e.end_time) and
             not (e.end_time <= ^start_time or e.start_time >= ^end_time))
  end

  defp maybe_exclude_id(query, nil), do: query
  defp maybe_exclude_id(query, exclude_id), do: from(e in query, where: e.id != ^exclude_id)

  defp validate_employment(employment_id) do
    Events.validate_event_type(employment_id, "employment",
      preload: [:event_type, :participations]
    )
  end

  defp get_worker_id(employment) do
    # Note: Employment uses "employee" instead of "worker" for participation_type
    Events.get_participant_id(employment, "employee")
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for employment events with custom validations.
  """
  def change_employment(%Event{} = event, attrs \\ %{}) do
    Employment.changeset(event, attrs)
  end
end
