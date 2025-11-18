defmodule Mosaic.Shifts do
  @moduledoc """
  The Shifts context handles shift-specific business logic including
  work periods, breaks, and shift scheduling.
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Events.Event
  alias Mosaic.Events
  alias Mosaic.Participations.Participation
  alias Mosaic.Shifts.Shift

  @doc """
  Creates a shift under an employment period.
  Returns {:ok, {shift, participation}} or {:error, changeset}.

  Attrs should include:
  - start_time (required)
  - end_time (required)
  - status (optional, defaults to "draft")
  - properties (optional, can include location, department, notes, etc.)
  - auto_generate_periods (optional, boolean, defaults to false)
  """
  def create_shift(employment_id, worker_id, attrs \\ %{}) do
    Repo.transaction(fn ->
      with {:ok, employment} <- validate_employment(employment_id),
           :ok <- validate_shift_in_employment(attrs, employment),
           :ok <- validate_no_shift_overlap(worker_id, attrs),
           {:ok, event_type} <- Events.get_event_type_by_name("shift"),
           attrs <- Map.merge(attrs, %{event_type_id: event_type.id, parent_id: employment_id}),
           {:ok, shift} <- Events.create_event(attrs),
           participation_attrs <- %{
             participant_id: worker_id,
             event_id: shift.id,
             participation_type: "worker",
             properties: %{}
           },
           {:ok, participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        if attrs[:auto_generate_periods] || attrs["auto_generate_periods"] do
          case auto_generate_periods(shift, worker_id) do
            {:ok, _periods} -> {shift, participation}
            {:error, reason} -> Repo.rollback(reason)
          end
        else
          {shift, participation}
        end
      else
        {:error, reason} -> Repo.rollback(reason)
        :error -> Repo.rollback("Failed to create shift")
      end
    end)
  end

  @doc """
  Updates a shift.
  """
  def update_shift(shift_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, shift} <- validate_shift(shift_id),
           employment <- Events.get_event!(shift.parent_id, preload: [:event_type]),
           :ok <- validate_shift_in_employment(attrs, employment),
           worker_id <- get_worker_id(shift),
           :ok <- validate_no_shift_overlap(worker_id, Map.put(attrs, :id, shift_id)),
           {:ok, updated_shift} <- Events.update_event(shift, attrs) do
        updated_shift
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Gets a shift by ID with all related data.
  """
  def get_shift!(id) do
    Events.get_event!(id,
      preload: [:event_type, :parent, children: :event_type, participations: :participant]
    )
  end

  @doc """
  Lists all shifts.
  """
  def list_shifts do
    Events.list_events_by_type("shift",
      preload: [:event_type, :parent, :children, participations: :participant]
    )
  end

  @doc """
  Lists all shifts under an employment period.
  """
  def list_shifts_for_employment(employment_id) do
    from(e in Event,
      join: et in assoc(e, :event_type),
      where: et.name == "shift" and e.parent_id == ^employment_id,
      order_by: [asc: e.start_time],
      preload: [:event_type, :children, participations: :participant]
    )
    |> Repo.all()
  end

  @doc """
  Lists all shifts for a worker across all employments.
  """
  def list_shifts_for_worker(worker_id, opts \\ []) do
    opts =
      Keyword.merge(opts,
        preload: [:event_type, :parent, :children, participations: :participant]
      )

    Events.list_events_for_participant("shift", worker_id, opts)
  end

  @doc """
  Auto-generates work periods and breaks for a shift.
  Adds a break after 4 hours if shift is longer than 4 hours.
  """
  def auto_generate_periods(shift, worker_id) do
    duration_hours = Event.duration_hours(shift)

    if is_nil(duration_hours) or duration_hours <= 0 do
      {:error, "Invalid shift duration"}
    else
      Repo.transaction(fn ->
        with {:ok, work_period_type} <- Events.get_event_type_by_name("work_period"),
             {:ok, break_type} <- Events.get_event_type_by_name("break") do
          if duration_hours > 4 do
            break_start = DateTime.add(shift.start_time, 4 * 3600, :second)
            break_end = DateTime.add(break_start, 30 * 60, :second)

            create_work_period(
              shift.id,
              worker_id,
              shift.start_time,
              break_start,
              work_period_type.id
            )

            create_break(shift.id, worker_id, break_start, break_end, break_type.id)

            create_work_period(
              shift.id,
              worker_id,
              break_end,
              shift.end_time,
              work_period_type.id
            )
          else
            create_work_period(
              shift.id,
              worker_id,
              shift.start_time,
              shift.end_time,
              work_period_type.id
            )
          end
        else
          {:error, reason} -> Repo.rollback(reason)
        end
      end)
    end
  end

  @doc """
  Calculates total worked hours by summing work_period durations.
  """
  def calculate_worked_hours(shift_id) do
    query =
      from e in Event,
        join: et in assoc(e, :event_type),
        where: e.parent_id == ^shift_id and et.name == "work_period",
        select: e

    Repo.all(query)
    |> Enum.reduce(0, fn event, acc ->
      case Event.duration_hours(event) do
        nil -> acc
        hours -> acc + hours
      end
    end)
  end

  @doc """
  Calculates total break time.
  """
  def calculate_break_hours(shift_id) do
    query =
      from e in Event,
        join: et in assoc(e, :event_type),
        where: e.parent_id == ^shift_id and et.name == "break",
        select: e

    Repo.all(query)
    |> Enum.reduce(0, fn event, acc ->
      case Event.duration_hours(event) do
        nil -> acc
        hours -> acc + hours
      end
    end)
  end

  @doc """
  Calculates net working time (worked hours - unpaid breaks).
  """
  def calculate_net_hours(shift_id) do
    worked = calculate_worked_hours(shift_id)
    unpaid_breaks = calculate_unpaid_break_hours(shift_id)
    worked - unpaid_breaks
  end

  @doc """
  Calculates unpaid break time only.
  """
  def calculate_unpaid_break_hours(shift_id) do
    query =
      from e in Event,
        join: et in assoc(e, :event_type),
        where:
          e.parent_id == ^shift_id and
            et.name == "break" and
            fragment("(?->>'is_paid')::boolean = false", e.properties),
        select: e

    Repo.all(query)
    |> Enum.reduce(0, fn event, acc ->
      case Event.duration_hours(event) do
        nil -> acc
        hours -> acc + hours
      end
    end)
  end

  @doc """
  Validates that shift dates fall within employment period.
  """
  def validate_shift_in_employment(shift_attrs, employment) do
    shift_start = shift_attrs[:start_time] || shift_attrs["start_time"]
    shift_end = shift_attrs[:end_time] || shift_attrs["end_time"]

    cond do
      is_nil(shift_start) ->
        {:error, "Shift start time is required"}

      is_nil(shift_end) ->
        {:error, "Shift end time is required"}

      DateTime.compare(shift_start, employment.start_time) == :lt ->
        {:error, "Shift starts before employment period"}

      not is_nil(employment.end_time) and
          DateTime.compare(shift_end, employment.end_time) == :gt ->
        {:error, "Shift ends after employment period"}

      true ->
        :ok
    end
  end

  @doc """
  Validates that worker doesn't have overlapping shifts.
  """
  def validate_no_shift_overlap(worker_id, shift_attrs) do
    shift_start = shift_attrs[:start_time] || shift_attrs["start_time"]
    shift_end = shift_attrs[:end_time] || shift_attrs["end_time"]
    shift_id = shift_attrs[:id] || shift_attrs["id"]

    # Skip validation if start or end times are nil - they'll be caught by required validation
    if is_nil(shift_start) or is_nil(shift_end) do
      :ok
    else
      base_query =
        from e in Event,
          join: et in assoc(e, :event_type),
          join: p in assoc(e, :participations),
          where:
            et.name == "shift" and
              p.participant_id == ^worker_id and
              e.status != "cancelled"

      # Build overlap query - shifts must have both start and end times
      query =
        from [e, et, p] in base_query,
          where:
            not is_nil(e.start_time) and
              not is_nil(e.end_time) and
              ((e.start_time <= ^shift_start and e.end_time > ^shift_start) or
                 (e.start_time < ^shift_end and e.end_time >= ^shift_end) or
                 (e.start_time >= ^shift_start and e.end_time <= ^shift_end))

      query =
        if shift_id do
          from e in query, where: e.id != ^shift_id
        else
          query
        end

      case Repo.one(from e in query, select: count(e.id)) do
        0 -> :ok
        _ -> {:error, "Worker has overlapping shifts"}
      end
    end
  end

  defp create_work_period(shift_id, worker_id, start_time, end_time, event_type_id) do
    with {:ok, event} <-
           Events.create_event(%{
             event_type_id: event_type_id,
             parent_id: shift_id,
             start_time: start_time,
             end_time: end_time,
             status: "active"
           }),
         {:ok, _participation} <-
           %Participation{}
           |> Participation.changeset(%{
             participant_id: worker_id,
             event_id: event.id,
             participation_type: "worker"
           })
           |> Repo.insert() do
      {:ok, event}
    end
  end

  defp create_break(shift_id, worker_id, start_time, end_time, event_type_id) do
    with {:ok, event} <-
           Events.create_event(%{
             event_type_id: event_type_id,
             parent_id: shift_id,
             start_time: start_time,
             end_time: end_time,
             status: "active",
             properties: %{"is_paid" => false}
           }),
         {:ok, _participation} <-
           %Participation{}
           |> Participation.changeset(%{
             participant_id: worker_id,
             event_id: event.id,
             participation_type: "worker"
           })
           |> Repo.insert() do
      {:ok, event}
    end
  end

  defp validate_employment(employment_id) do
    Events.validate_event_type(employment_id, "employment")
  end

  defp validate_shift(shift_id) do
    Events.validate_event_type(shift_id, "shift", preload: [:event_type, :participations])
  end

  defp get_worker_id(shift) do
    Events.get_participant_id(shift, "worker")
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for shift events with custom validations.
  """
  def change_shift(%Event{} = event, attrs \\ %{}) do
    Shift.changeset(event, attrs)
  end
end
