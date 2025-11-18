defmodule Mosaic.Events do
  @moduledoc """
  Core Events context for generic CRUD operations on events.
  Domain-specific logic should be in separate contexts (Employments, Shifts, etc).
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.{Event, EventType}

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
            Mosaic.EventTypeBehaviour.changeset(event_type, event, attrs)

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
end
