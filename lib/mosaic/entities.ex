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
  Returns the list of workers (entities with entity_type = "person").
  """
  def list_workers do
    Entity
    |> where([e], e.entity_type == "person")
    |> Repo.all()
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
  Creates a worker (entity with type "person").
  Worker properties should include: name, email, phone.
  """
  def create_worker(attrs \\ %{}) do
    %Entity{}
    |> Entity.worker_changeset(attrs)
    |> Repo.insert()
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
  Returns an `%Ecto.Changeset{}` for tracking worker changes.
  """
  def change_worker(%Entity{} = entity, attrs \\ %{}) do
    Entity.worker_changeset(entity, attrs)
  end
end
