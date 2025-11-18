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

  @doc """
  Returns the list of all locations.

  ## Examples

      iex> list_locations()
      [%Entity{}, ...]

  """
  def list_locations do
    from(e in Entity,
      where: e.entity_type == "location",
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

    if entity.entity_type != "location" do
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
      where: e.entity_type == "location",
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
      where: e.entity_type == "location" and e.id in ^ids,
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
      where: e.entity_type == "location",
      where: fragment("(?->>'capacity')::integer >= ?", e.properties, ^min_capacity),
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end
end
