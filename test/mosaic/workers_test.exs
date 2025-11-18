defmodule Mosaic.WorkersTest do
  use Mosaic.DataCase

  alias Mosaic.Workers
  alias Mosaic.Entities.Entity
  import Mosaic.Fixtures

  describe "list_workers/0" do
    test "returns all workers ordered by name" do
      worker1 = worker_fixture(%{"properties" => %{"name" => "Alice", "email" => "alice@test.com"}})
      worker2 = worker_fixture(%{"properties" => %{"name" => "Bob", "email" => "bob@test.com"}})

      workers = Workers.list_workers()
      assert length(workers) >= 2

      # Check ordering
      names = Enum.map(workers, & &1.properties["name"])
      assert Enum.sort(names) == names
    end
  end

  describe "get_worker!/1" do
    test "returns worker with participations preloaded" do
      worker = worker_fixture()
      fetched = Workers.get_worker!(worker.id)

      assert fetched.id == worker.id
      assert is_list(fetched.participations)
    end

    test "raises if worker doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Workers.get_worker!(Ecto.UUID.generate())
      end
    end

    test "raises if entity is not a person type" do
      location = location_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Workers.get_worker!(location.id)
      end
    end
  end

  describe "create_worker/1" do
    test "creates worker with valid attributes" do
      attrs = %{
        "properties" => %{
          "name" => "John Doe",
          "email" => "john@example.com",
          "phone" => "555-1234"
        }
      }

      assert {:ok, %Entity{} = worker} = Workers.create_worker(attrs)
      assert worker.entity_type == "person"
      assert worker.properties["name"] == "John Doe"
      assert worker.properties["email"] == "john@example.com"
    end

    test "requires name property" do
      attrs = %{
        "properties" => %{
          "email" => "test@example.com"
        }
      }

      assert {:error, changeset} = Workers.create_worker(attrs)
      assert "Name is required" in errors_on(changeset).properties
    end

    test "requires email property" do
      attrs = %{
        "properties" => %{
          "name" => "Test Worker"
        }
      }

      assert {:error, changeset} = Workers.create_worker(attrs)
      assert "Email is required" in errors_on(changeset).properties
    end

    test "validates email format" do
      attrs = %{
        "properties" => %{
          "name" => "Test Worker",
          "email" => "invalid-email"
        }
      }

      assert {:error, changeset} = Workers.create_worker(attrs)
      assert "Email must be valid" in errors_on(changeset).properties
    end

    test "accepts optional phone property" do
      attrs = %{
        "properties" => %{
          "name" => "Test Worker",
          "email" => "test@example.com",
          "phone" => "555-9999"
        }
      }

      assert {:ok, worker} = Workers.create_worker(attrs)
      assert worker.properties["phone"] == "555-9999"
    end
  end

  describe "update_worker/2" do
    test "updates worker with valid attributes" do
      worker = worker_fixture()

      attrs = %{
        "properties" => %{
          "name" => "Updated Name",
          "email" => worker.properties["email"]
        }
      }

      assert {:ok, updated} = Workers.update_worker(worker, attrs)
      assert updated.properties["name"] == "Updated Name"
    end

    test "returns error with invalid email" do
      worker = worker_fixture()

      attrs = %{
        "properties" => %{
          "name" => worker.properties["name"],
          "email" => "invalid"
        }
      }

      assert {:error, %Ecto.Changeset{}} = Workers.update_worker(worker, attrs)
    end
  end

  describe "delete_worker/1" do
    test "deletes the worker" do
      worker = worker_fixture()
      assert {:ok, %Entity{}} = Workers.delete_worker(worker)
      assert_raise Ecto.NoResultsError, fn -> Workers.get_worker!(worker.id) end
    end
  end

  describe "search_workers/1" do
    test "finds workers by name" do
      worker = worker_fixture(%{"properties" => %{"name" => "Unique Name", "email" => "test@test.com"}})
      _other = worker_fixture(%{"properties" => %{"name" => "Other Worker", "email" => "other@test.com"}})

      results = Workers.search_workers("Unique")
      result_ids = Enum.map(results, & &1.id)
      assert worker.id in result_ids
    end

    test "finds workers by email" do
      worker = worker_fixture(%{"properties" => %{"name" => "Test", "email" => "unique@example.com"}})
      _other = worker_fixture(%{"properties" => %{"name" => "Other", "email" => "other@example.com"}})

      results = Workers.search_workers("unique@")
      result_ids = Enum.map(results, & &1.id)
      assert worker.id in result_ids
    end

    test "search is case insensitive" do
      worker = worker_fixture(%{"properties" => %{"name" => "Test Worker", "email" => "test@test.com"}})

      results = Workers.search_workers("TEST")
      result_ids = Enum.map(results, & &1.id)
      assert worker.id in result_ids
    end
  end

  describe "get_workers_by_ids/1" do
    test "returns workers with given IDs" do
      worker1 = worker_fixture()
      worker2 = worker_fixture()
      _worker3 = worker_fixture()

      workers = Workers.get_workers_by_ids([worker1.id, worker2.id])
      worker_ids = Enum.map(workers, & &1.id)

      assert worker1.id in worker_ids
      assert worker2.id in worker_ids
      assert length(workers) == 2
    end
  end

  describe "worker_exists_with_email?/1" do
    test "returns true if worker exists with email" do
      worker = worker_fixture(%{"properties" => %{"name" => "Test", "email" => "exists@test.com"}})
      assert Workers.worker_exists_with_email?("exists@test.com")
    end

    test "returns false if no worker has email" do
      refute Workers.worker_exists_with_email?("nonexistent@test.com")
    end
  end
end
