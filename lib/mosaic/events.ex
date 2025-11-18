defmodule Mosaic.Events do
  @moduledoc """
  Core Events context for generic CRUD operations on events.
  Domain-specific logic should be in separate contexts (Employments, Shifts, etc).
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Events.{Event, EventType}

  @doc """
  Returns the list of events with optional filtering and preloading.

  ## Options
  - :preload - list of associations to preload (e.g., [:event_type, :participations])
  - :event_type - filter by event type name
  - :status - filter by status
  - :parent_id - filter by parent event
  """
  def list_events(opts \\ []) do
    query = from(e in Event)

    query =
      if event_type = opts[:event_type] do
        from e in query,
          join: et in assoc(e, :event_type),
          where: et.name == ^event_type
      else
        query
      end

    query =
      if status = opts[:status] do
        from e in query, where: e.status == ^status
      else
        query
      end

    query =
      if parent_id = opts[:parent_id] do
        from e in query, where: e.parent_id == ^parent_id
      else
        query
      end

    query =
      if preload = opts[:preload] do
        from e in query, preload: ^preload
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Gets a single event.

  Raises `Ecto.NoResultsError` if the Event does not exist.
  """
  def get_event!(id, opts \\ []) do
    preloads = opts[:preload] || []

    Event
    |> Repo.get!(id)
    |> Repo.preload(preloads)
  end

  @doc """
  Creates an event.
  """
  def create_event(attrs \\ %{}) do
    %Event{}
    |> get_changeset_for_event_type(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an event.
  """
  def update_event(%Event{} = event, attrs) do
    event
    |> get_changeset_for_event_type(attrs)
    |> Repo.update()
  end

  # Gets the appropriate changeset based on event type
  defp get_changeset_for_event_type(%Event{} = event, attrs) do
    event_type_id =
      Map.get(attrs, :event_type_id) || Map.get(attrs, "event_type_id") || event.event_type_id

    case event_type_id do
      nil ->
        Event.changeset(event, attrs)

      id ->
        case Repo.get(EventType, id) do
          %EventType{} = event_type ->
            Mosaic.Events.EventTypeBehaviour.changeset(event_type, event, attrs)

          nil ->
            Event.changeset(event, attrs)
        end
    end
  end

  @doc """
  Deletes an event.
  """
  def delete_event(%Event{} = event) do
    Repo.delete(event)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking event changes.
  """
  def change_event(%Event{} = event, attrs \\ %{}) do
    Event.changeset(event, attrs)
  end

  @doc """
  Gets the full event hierarchy (parent and children).
  """
  def get_event_hierarchy(event_id) do
    event =
      get_event!(event_id,
        preload: [:parent, :children, :event_type, participations: :participant]
      )

    %{
      event: event,
      parent: event.parent,
      children: event.children
    }
  end

  @doc """
  Gets an event type by name.
  """
  def get_event_type_by_name(name) do
    case Repo.get_by(EventType, name: name, is_active: true) do
      nil -> {:error, "Event type not found: #{name}"}
      event_type -> {:ok, event_type}
    end
  end

  @doc """
  Lists all event types.
  """
  def list_event_types do
    Repo.all(from et in EventType, where: et.is_active == true)
  end

  @doc """
  Validates that an event exists and is of the expected type.
  Returns {:ok, event} or {:error, reason}.

  ## Examples

      iex> validate_event_type(event_id, "shift", preload: [:participations])
      {:ok, %Event{}}

      iex> validate_event_type(invalid_id, "shift")
      {:error, "Event not found"}

      iex> validate_event_type(employment_id, "shift")
      {:error, "Event is not a shift"}
  """
  def validate_event_type(event_id, expected_type, opts \\ []) do
    preload = Keyword.get(opts, :preload, [:event_type])

    try do
      event = get_event!(event_id, preload: preload)

      if event.event_type.name == expected_type do
        {:ok, event}
      else
        {:error, "Event is not #{article(expected_type)} #{expected_type}"}
      end
    rescue
      Ecto.NoResultsError -> {:error, "Event not found"}
    end
  end

  @doc """
  Gets the participant_id for a specific participation_type from an event.
  Returns the participant_id or nil if no matching participation found.

  ## Examples

      iex> get_participant_id(shift, "worker")
      "worker-uuid-123"

      iex> get_participant_id(event, "nonexistent")
      nil
  """
  def get_participant_id(%Event{} = event, participation_type) do
    event
    |> Repo.preload(:participations)
    |> Map.get(:participations)
    |> Enum.find(&(&1.participation_type == participation_type))
    |> case do
      nil -> nil
      participation -> participation.participant_id
    end
  end

  @doc """
  Lists all events of a specific type.

  ## Options
  - :preload - associations to preload
  - :order_by - ordering (defaults to start_time ascending)

  ## Examples

      iex> list_events_by_type("shift", preload: [:participations])
      [%Event{}, ...]
  """
  def list_events_by_type(type_name, opts \\ []) do
    preload = Keyword.get(opts, :preload, [:event_type])
    order_by = Keyword.get(opts, :order_by, asc: :start_time)

    from(e in Event,
      join: et in assoc(e, :event_type),
      where: et.name == ^type_name,
      order_by: ^order_by,
      preload: ^preload
    )
    |> Repo.all()
  end

  @doc """
  Lists all events of a type for a specific participant (worker).

  ## Options
  - :preload - associations to preload
  - :date_from - filter events starting on or after this date
  - :date_to - filter events starting on or before this date

  ## Examples

      iex> list_events_for_participant("shift", worker_id, date_from: ~U[2024-01-01])
      [%Event{}, ...]
  """
  def list_events_for_participant(type_name, participant_id, opts \\ []) do
    preload = Keyword.get(opts, :preload, [:event_type, :parent])

    query =
      from(e in Event,
        join: et in assoc(e, :event_type),
        join: p in assoc(e, :participations),
        where: et.name == ^type_name and p.participant_id == ^participant_id,
        order_by: [asc: e.start_time],
        preload: ^preload
      )

    query =
      if date_from = opts[:date_from] do
        from(e in query, where: e.start_time >= ^date_from)
      else
        query
      end

    query =
      if date_to = opts[:date_to] do
        from(e in query, where: e.start_time <= ^date_to)
      else
        query
      end

    Repo.all(query)
  end

  # Returns appropriate article (a/an) for a word
  defp article(word) do
    if String.starts_with?(word, ~w(a e i o u)) do
      "an"
    else
      "a"
    end
  end
end
