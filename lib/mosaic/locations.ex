defmodule Mosaic.Locations do
  @moduledoc """
  The Locations context manages location entities and their domain-specific operations.

  Locations are physical places where events (like shifts) occur. This context
  provides location-specific business logic on top of the generic Entity system.
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Entities.Entity
  alias Mosaic.Locations.Location
  alias Mosaic.Events
  alias Mosaic.Events.Event
  alias Mosaic.Events.EventType
  alias Mosaic.Participations.Participation

  @location_membership_event_type "location_membership"

  @doc """
  Returns the list of all locations.

  ## Examples

      iex> list_locations()
      [%Entity{}, ...]

  """
  def list_locations do
    from(e in Entity,
      where: e.entity_type == ^Location.entity_type(),
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single location.

  Raises `Ecto.NoResultsError` if the Location does not exist or is not a location entity.

  ## Examples

      iex> get_location!("123")
      %Entity{entity_type: "location"}

      iex> get_location!("456")
      ** (Ecto.NoResultsError)

  """
  def get_location!(id) do
    entity = Repo.get!(Entity, id)

    if entity.entity_type != Location.entity_type() do
      raise Ecto.NoResultsError, queryable: Entity
    end

    entity
  end

  @doc """
  Creates a location.

  ## Examples

      iex> create_location(%{properties: %{"name" => "Office", "address" => "123 Main St"}})
      {:ok, %Entity{}}

      iex> create_location(%{properties: %{"name" => ""}})
      {:error, %Ecto.Changeset{}}

  """
  def create_location(attrs \\ %{}) do
    %Entity{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a location.

  ## Examples

      iex> update_location(location, %{properties: %{"name" => "New Office"}})
      {:ok, %Entity{}}

      iex> update_location(location, %{properties: %{"address" => ""}})
      {:error, %Ecto.Changeset{}}

  """
  def update_location(%Entity{} = location, attrs) do
    location
    |> Location.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a location.

  ## Examples

      iex> delete_location(location)
      {:ok, %Entity{}}

      iex> delete_location(location)
      {:error, %Ecto.Changeset{}}

  """
  def delete_location(%Entity{} = location) do
    Repo.delete(location)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking location changes.

  ## Examples

      iex> change_location(location)
      %Ecto.Changeset{data: %Entity{}}

  """
  def change_location(%Entity{} = location, attrs \\ %{}) do
    Location.changeset(location, attrs)
  end

  @doc """
  Searches locations by name or address.

  ## Examples

      iex> search_locations("office")
      [%Entity{}, ...]

  """
  def search_locations(query_string) when is_binary(query_string) do
    search_pattern = "%#{query_string}%"

    from(e in Entity,
      where: e.entity_type == ^Location.entity_type(),
      where:
        ilike(fragment("?->>'name'", e.properties), ^search_pattern) or
          ilike(fragment("?->>'address'", e.properties), ^search_pattern),
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  @doc """
  Gets locations by a list of IDs.

  ## Examples

      iex> get_locations_by_ids(["id1", "id2"])
      [%Entity{}, ...]

  """
  def get_locations_by_ids(ids) when is_list(ids) do
    from(e in Entity,
      where: e.entity_type == ^Location.entity_type() and e.id in ^ids,
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  @doc """
  Gets locations with capacity greater than or equal to the specified amount.

  ## Examples

      iex> get_locations_with_capacity(10)
      [%Entity{}, ...]

  """
  def get_locations_with_capacity(min_capacity) when is_integer(min_capacity) do
    from(e in Entity,
      where: e.entity_type == ^Location.entity_type(),
      where: fragment("(?->>'capacity')::integer >= ?", e.properties, ^min_capacity),
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  # Location Hierarchy Functions

  @doc """
  Links a child location to a parent via a location_membership event.

  Creates an active location_membership event with two participations:
  - parent_location: The parent location
  - child_location: The child location

  ## Examples

      iex> set_parent(child_id, parent_id)
      {:ok, %Event{}}

      iex> set_parent(child_id, parent_id, ~U[2024-01-01 00:00:00Z])
      {:ok, %Event{}}

  """
  def set_parent(child_id, parent_id, start_time \\ nil) do
    start_time = start_time || DateTime.utc_now()

    Repo.transaction(fn ->
      with {:ok, _child} <- validate_location_exists(child_id),
           {:ok, _parent} <- validate_location_exists(parent_id),
           :ok <- validate_no_circular_reference(child_id, parent_id),
           {:ok, event_type} <- Events.get_event_type_by_name(@location_membership_event_type),
           attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => start_time,
             "status" => "active"
           },
           {:ok, event} <- Events.create_event(attrs),
           # Create parent participation
           parent_attrs <- %{
             "participant_id" => parent_id,
             "event_id" => event.id,
             "participation_type" => "parent_location"
           },
           {:ok, _parent_participation} <-
             %Participation{}
             |> Participation.changeset(parent_attrs)
             |> Repo.insert(),
           # Create child participation
           child_attrs <- %{
             "participant_id" => child_id,
             "event_id" => event.id,
             "participation_type" => "child_location"
           },
           {:ok, _child_participation} <-
             %Participation{}
             |> Participation.changeset(child_attrs)
             |> Repo.insert() do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Gets the current parent for a location at a given time.

  Returns the ID of the parent location if one exists, or nil if the location
  has no parent at the specified time.

  ## Examples

      iex> get_parent(location_id)
      "parent-location-id"

      iex> get_parent(location_id, ~U[2024-01-01 00:00:00Z])
      "parent-location-id"

      iex> get_parent(orphan_location_id)
      nil

  """
  def get_parent(location_id, at_time \\ nil) do
    at_time = at_time || DateTime.utc_now()

    query =
      from e in Event,
        join: et in EventType,
        on: e.event_type_id == et.id,
        join: p_child in Participation,
        on: p_child.event_id == e.id,
        join: p_parent in Participation,
        on: p_parent.event_id == e.id,
        where: et.name == ^@location_membership_event_type,
        where: p_child.participant_id == ^location_id,
        where: p_child.participation_type == "child_location",
        where: p_parent.participation_type == "parent_location",
        where: e.start_time <= ^at_time,
        where: is_nil(e.end_time) or e.end_time > ^at_time,
        where: e.status != "cancelled",
        select: p_parent.participant_id

    Repo.one(query)
  end

  @doc """
  Gets all children of a location at a given time.

  Returns a list of child location IDs.

  ## Examples

      iex> get_children(location_id)
      ["child-1-id", "child-2-id"]

      iex> get_children(location_id, ~U[2024-01-01 00:00:00Z])
      ["child-1-id"]

      iex> get_children(leaf_location_id)
      []

  """
  def get_children(location_id, at_time \\ nil) do
    at_time = at_time || DateTime.utc_now()

    query =
      from e in Event,
        join: et in EventType,
        on: e.event_type_id == et.id,
        join: p_parent in Participation,
        on: p_parent.event_id == e.id,
        join: p_child in Participation,
        on: p_child.event_id == e.id,
        where: et.name == ^@location_membership_event_type,
        where: p_parent.participant_id == ^location_id,
        where: p_parent.participation_type == "parent_location",
        where: p_child.participation_type == "child_location",
        where: e.start_time <= ^at_time,
        where: is_nil(e.end_time) or e.end_time > ^at_time,
        where: e.status != "cancelled",
        select: p_child.participant_id

    Repo.all(query)
  end

  @doc """
  Removes the parent relationship for a location by ending the active location_membership event.

  ## Examples

      iex> remove_parent(location_id)
      {:ok, %Event{}}

      iex> remove_parent(location_without_parent_id)
      {:error, "No active parent relationship found"}

  """
  def remove_parent(location_id) do
    # Use second-level precision to match :utc_datetime schema field
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    # Find the active parent relationship
    query =
      from e in Event,
        join: et in EventType,
        on: e.event_type_id == et.id,
        join: p_child in Participation,
        on: p_child.event_id == e.id,
        where: et.name == ^@location_membership_event_type,
        where: p_child.participant_id == ^location_id,
        where: p_child.participation_type == "child_location",
        where: e.start_time <= ^now,
        where: is_nil(e.end_time) or e.end_time > ^now,
        where: e.status == "active",
        select: e

    case Repo.one(query) do
      nil ->
        {:error, "No active parent relationship found"}

      event ->
        # Reload to ensure we have all fields
        event = Repo.get!(Event, event.id)

        # Ensure end_time is strictly after start_time (with second-level precision)
        # Use now if it's after start_time, otherwise use start_time + 1 second
        end_time =
          case DateTime.compare(now, event.start_time) do
            :gt -> now
            _ -> DateTime.add(event.start_time, 1, :second)
          end

        # Set status to cancelled to immediately exclude from active queries
        Events.update_event(event, %{"end_time" => end_time, "status" => "cancelled"})
    end
  end

  # Private helper functions

  defp validate_location_exists(location_id) do
    case Repo.get(Entity, location_id) do
      nil ->
        {:error, "Location not found: #{location_id}"}

      entity ->
        if entity.entity_type == Location.entity_type() do
          {:ok, entity}
        else
          {:error, "Entity is not a location: #{location_id}"}
        end
    end
  end

  defp validate_no_circular_reference(child_id, parent_id) do
    # Check if parent_id is a descendant of child_id (which would create a cycle)
    if is_descendant?(parent_id, child_id) do
      {:error, "Cannot create circular reference: parent is a descendant of child"}
    else
      :ok
    end
  end

  defp is_descendant?(potential_descendant_id, ancestor_id) do
    # Recursively check if potential_descendant is a child of ancestor
    case get_parent(potential_descendant_id) do
      nil ->
        false

      ^ancestor_id ->
        true

      parent_id ->
        is_descendant?(parent_id, ancestor_id)
    end
  end
end
