defmodule Mosaic.Timekeeping do
  @moduledoc """
  The Timekeeping context handles clock events and actual worked time tracking.

  Clock events are point-in-time records of when workers clock in and out.
  Clock periods consolidate paired clock-in/out events into time spans.
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Events
  alias Mosaic.Events.Event
  alias Mosaic.Participations.Participation
  alias Mosaic.Shifts.Shift

  @doc """
  Records a clock-in event for a worker.

  ## Options
  - device_id: Identifier for the clock-in device/terminal
  - location_id: Location where clock-in occurred
  - gps_coords: GPS coordinates of clock-in location
  - timestamp: Custom timestamp (defaults to current time)
  - Any other options will be added to properties

  Returns {:ok, clock_event} or {:error, changeset}.
  """
  def clock_in(worker_id, opts \\ []) do
    Repo.transaction(fn ->
      now = opts[:timestamp] || DateTime.utc_now()
      # Clock events are point-in-time, but Event schema requires end > start
      # Use same time + 1 second to represent instantaneous event
      end_time = DateTime.add(now, 1, :second)

      with {:ok, event_type} <- Events.get_event_type_by_name("clock_event"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => now,
             "end_time" => end_time,
             "status" => "active",
             "properties" =>
               %{
                 "event_type" => "in",
                 "device_id" => opts[:device_id],
                 "location_id" => opts[:location_id],
                 "gps_coords" => opts[:gps_coords]
               }
               |> Enum.reject(fn {_k, v} -> is_nil(v) end)
               |> Map.new()
           },
           {:ok, event} <- Events.create_event(event_attrs),
           participation_attrs <- %{
             "participant_id" => worker_id,
             "event_id" => event.id,
             "participation_type" => "worker"
           },
           {:ok, _participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Records a clock-out event for a worker.

  ## Options
  - device_id: Identifier for the clock-out device/terminal
  - location_id: Location where clock-out occurred
  - gps_coords: GPS coordinates of clock-out location
  - timestamp: Custom timestamp (defaults to current time)
  - Any other options will be added to properties

  Returns {:ok, clock_event} or {:error, changeset}.
  """
  def clock_out(worker_id, opts \\ []) do
    Repo.transaction(fn ->
      now = opts[:timestamp] || DateTime.utc_now()
      # Clock events are point-in-time, but Event schema requires end > start
      # Use same time + 1 second to represent instantaneous event
      end_time = DateTime.add(now, 1, :second)

      with {:ok, event_type} <- Events.get_event_type_by_name("clock_event"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => now,
             "end_time" => end_time,
             "status" => "active",
             "properties" =>
               %{
                 "event_type" => "out",
                 "device_id" => opts[:device_id],
                 "location_id" => opts[:location_id],
                 "gps_coords" => opts[:gps_coords]
               }
               |> Enum.reject(fn {_k, v} -> is_nil(v) end)
               |> Map.new()
           },
           {:ok, event} <- Events.create_event(event_attrs),
           participation_attrs <- %{
             "participant_id" => worker_id,
             "event_id" => event.id,
             "participation_type" => "worker"
           },
           {:ok, _participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Creates a clock period from clock-in and clock-out events.

  A clock period represents the actual time worked, bounded by
  clock-in and clock-out events. It can optionally reference a
  planned shift for comparison purposes.

  Returns {:ok, clock_period} or {:error, changeset}.
  """
  def create_clock_period(worker_id, clock_in_event_id, clock_out_event_id) do
    Repo.transaction(fn ->
      with {:ok, clock_in} <- validate_clock_event(clock_in_event_id, "in"),
           {:ok, clock_out} <- validate_clock_event(clock_out_event_id, "out"),
           :ok <- validate_clock_events_order(clock_in, clock_out),
           :ok <- validate_clock_events_worker(clock_in, clock_out, worker_id),
           {:ok, event_type} <- Events.get_event_type_by_name("clock_period"),
           shift_id <- find_matching_shift(worker_id, clock_in.start_time),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => clock_in.start_time,
             "end_time" => clock_out.start_time,
             "status" => "active",
             "properties" => %{
               "clock_in_event_id" => clock_in_event_id,
               "clock_out_event_id" => clock_out_event_id,
               "planned_shift_id" => shift_id
             }
           },
           {:ok, event} <- Events.create_event(event_attrs),
           participation_attrs <- %{
             "participant_id" => worker_id,
             "event_id" => event.id,
             "participation_type" => "worker"
           },
           {:ok, _participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Lists all clock events for a worker.
  """
  def list_clock_events(worker_id, opts \\ []) do
    opts =
      Keyword.merge(opts,
        preload: [:event_type, participations: :participant]
      )

    Events.list_events_for_participant("clock_event", worker_id, opts)
  end

  @doc """
  Lists all clock periods for a worker.
  """
  def list_clock_periods(worker_id, opts \\ []) do
    opts =
      Keyword.merge(opts,
        preload: [:event_type, participations: :participant]
      )

    Events.list_events_for_participant("clock_period", worker_id, opts)
  end

  # Private helper functions

  defp validate_clock_event(event_id, expected_type) do
    event = Events.get_event!(event_id, preload: :event_type)

    cond do
      event.event_type.name != "clock_event" ->
        {:error, "Event #{event_id} is not a clock event"}

      event.properties["event_type"] != expected_type ->
        {:error, "Clock event #{event_id} is not a #{expected_type} event"}

      true ->
        {:ok, event}
    end
  end

  defp validate_clock_events_order(clock_in, clock_out) do
    if DateTime.compare(clock_in.start_time, clock_out.start_time) == :lt do
      :ok
    else
      {:error, "Clock-out must be after clock-in"}
    end
  end

  defp validate_clock_events_worker(clock_in, clock_out, worker_id) do
    clock_in_worker = Events.get_participant_id(clock_in, "worker")
    clock_out_worker = Events.get_participant_id(clock_out, "worker")

    cond do
      clock_in_worker != worker_id ->
        {:error, "Clock-in event does not belong to worker"}

      clock_out_worker != worker_id ->
        {:error, "Clock-out event does not belong to worker"}

      true ->
        :ok
    end
  end

  defp find_matching_shift(worker_id, clock_time) do
    from(e in Event,
      join: et in assoc(e, :event_type),
      join: p in assoc(e, :participations),
      where: et.name == ^Shift.event_type(),
      where: p.participant_id == ^worker_id,
      where: p.participation_type == "worker",
      where: e.start_time <= ^clock_time,
      where: e.end_time >= ^clock_time,
      where: e.status != "cancelled",
      select: e.id
    )
    |> Repo.one()
  end
end
