defmodule Mosaic.Entities do
  @moduledoc """
  The Entities context for managing people, organizations, locations, and resources.
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Entities.Entity

  @doc """
  Returns the list of all entities.
  """
  def list_entities do
    Repo.all(Entity)
  end

  @doc """
  Returns the list of entities filtered by type.
  """
  def list_entities_by_type(entity_type) do
    Entity
    |> where([e], e.entity_type == ^entity_type)
    |> Repo.all()
  end

  @doc """
  Returns the list of workers (entities with entity_type = "person").
  This is a convenience function that delegates to list_entities_by_type.
  """
  def list_workers do
    list_entities_by_type("person")
  end

  @doc """
  Gets a single entity.

  Raises `Ecto.NoResultsError` if the Entity does not exist.
  """
  def get_entity!(id) do
    Repo.get!(Entity, id)
  end

  @doc """
  Gets a single entity with preloaded associations.
  """
  def get_entity_with_participations!(id) do
    Entity
    |> Repo.get!(id)
    |> Repo.preload(participations: [:event])
  end

  @doc """
  Creates an entity of type "person".

  Note: This is a convenience function. For domain-specific worker logic,
  consider creating a separate Workers context module.
  """
  def create_person(attrs \\ %{}) do
    attrs_with_type = Map.put(attrs, :entity_type, "person")

    %Entity{}
    |> Entity.changeset(attrs_with_type)
    |> Repo.insert()
  end

  @doc """
  Creates a worker (entity with type "person").
  Deprecated: Use create_person/1 instead, or create a Workers context.
  """
  def create_worker(attrs \\ %{}) do
    create_person(attrs)
  end

  @doc """
  Creates a generic entity.
  """
  def create_entity(attrs \\ %{}) do
    %Entity{}
    |> Entity.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an entity.
  """
  def update_entity(%Entity{} = entity, attrs) do
    entity
    |> Entity.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an entity.
  """
  def delete_entity(%Entity{} = entity) do
    Repo.delete(entity)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking entity changes.
  """
  def change_entity(%Entity{} = entity, attrs \\ %{}) do
    Entity.changeset(entity, attrs)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking changes to a person entity.
  Deprecated: Use change_entity/2 instead, or create a Workers context.
  """
  def change_worker(%Entity{} = entity, attrs \\ %{}) do
    Entity.changeset(entity, attrs)
  end
end
