defmodule Mosaic.Workers do
  @moduledoc """
  The Workers context manages worker entities and their domain-specific operations.

  Workers are people who participate in employment periods and shifts. This context
  provides worker-specific business logic on top of the generic Entity system.
  """

  import Ecto.Query, warn: false
  alias Mosaic.Repo
  alias Mosaic.Entities.Entity
  alias Mosaic.Workers.Worker

  @doc """
  Returns the list of all workers (entities with entity_type = "person").

  ## Examples

      iex> list_workers()
      [%Entity{}, ...]

  """
  def list_workers do
    from(e in Entity,
      where: e.entity_type == ^Worker.entity_type(),
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  @doc """
  Gets a single worker.

  Raises `Ecto.NoResultsError` if the Worker does not exist or is not a person entity.

  ## Examples

      iex> get_worker!("123")
      %Entity{entity_type: "person"}

      iex> get_worker!("456")
      ** (Ecto.NoResultsError)

  """
  def get_worker!(id) do
    entity = Repo.get!(Entity, id) |> Repo.preload(participations: [:event])

    if entity.entity_type != Worker.entity_type() do
      raise Ecto.NoResultsError, queryable: Entity
    end

    entity
  end

  @doc """
  Creates a worker.

  ## Examples

      iex> create_worker(%{properties: %{"name" => "John Doe", "email" => "john@example.com"}})
      {:ok, %Entity{}}

      iex> create_worker(%{properties: %{"name" => ""}})
      {:error, %Ecto.Changeset{}}

  """
  def create_worker(attrs \\ %{}) do
    %Entity{}
    |> Worker.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a worker.

  ## Examples

      iex> update_worker(worker, %{properties: %{"name" => "Jane Doe"}})
      {:ok, %Entity{}}

      iex> update_worker(worker, %{properties: %{"email" => "invalid"}})
      {:error, %Ecto.Changeset{}}

  """
  def update_worker(%Entity{} = worker, attrs) do
    worker
    |> Worker.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a worker.

  ## Examples

      iex> delete_worker(worker)
      {:ok, %Entity{}}

      iex> delete_worker(worker)
      {:error, %Ecto.Changeset{}}

  """
  def delete_worker(%Entity{} = worker) do
    Repo.delete(worker)
  end

  @doc """
  Returns an `%Ecto.Changeset{}` for tracking worker changes.

  ## Examples

      iex> change_worker(worker)
      %Ecto.Changeset{data: %Entity{}}

  """
  def change_worker(%Entity{} = worker, attrs \\ %{}) do
    Worker.changeset(worker, attrs)
  end

  @doc """
  Searches workers by name or email.

  ## Examples

      iex> search_workers("john")
      [%Entity{}, ...]

  """
  def search_workers(query_string) when is_binary(query_string) do
    search_pattern = "%#{query_string}%"

    from(e in Entity,
      where: e.entity_type == "person",
      where:
        ilike(fragment("?->>'name'", e.properties), ^search_pattern) or
          ilike(fragment("?->>'email'", e.properties), ^search_pattern),
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  @doc """
  Gets workers by a list of IDs.

  ## Examples

      iex> get_workers_by_ids(["id1", "id2"])
      [%Entity{}, ...]

  """
  def get_workers_by_ids(ids) when is_list(ids) do
    from(e in Entity,
      where: e.entity_type == "person" and e.id in ^ids,
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  @doc """
  Checks if a worker with the given email already exists.

  ## Examples

      iex> worker_exists_with_email?("john@example.com")
      true

  """
  def worker_exists_with_email?(email) when is_binary(email) do
    from(e in Entity,
      where: e.entity_type == "person",
      where: fragment("?->>'email' = ?", e.properties, ^email)
    )
    |> Repo.exists?()
  end
end
