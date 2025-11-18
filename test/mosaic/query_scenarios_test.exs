defmodule Mosaic.QueryScenariosTest do
  use Mosaic.DataCase

  alias Mosaic.{Workers, Employments, Shifts, Events}
  alias Mosaic.Test.Seeds
  import Mosaic.Fixtures

  setup do
    Seeds.seed_event_types()
    :ok
  end

  describe "worker queries" do
    test "finds workers by email (exact match)" do
      _worker1 =
        worker_fixture(%{"properties" => %{"name" => "Alice", "email" => "alice@company.com"}})

      worker2 =
        worker_fixture(%{"properties" => %{"name" => "Bob", "email" => "bob@company.com"}})

      results = Workers.search_workers("bob@company.com")
      assert length(results) == 1
      assert hd(results).id == worker2.id
    end

    test "finds workers by email (partial match)" do
      worker1 =
        worker_fixture(%{"properties" => %{"name" => "Alice", "email" => "alice@company.com"}})

      worker2 =
        worker_fixture(%{"properties" => %{"name" => "Bob", "email" => "bob@company.com"}})

      _worker3 =
        worker_fixture(%{
          "properties" => %{"name" => "Charlie", "email" => "charlie@othercompany.com"}
        })

      results = Workers.search_workers("@company.com")
      result_ids = Enum.map(results, & &1.id)

      assert worker1.id in result_ids
      assert worker2.id in result_ids
      assert length(results) == 2
    end

    test "finds workers by name (case insensitive)" do
      worker =
        worker_fixture(%{
          "properties" => %{"name" => "Alice Johnson", "email" => "alice@test.com"}
        })

      results = Workers.search_workers("alice")
      assert length(results) >= 1
      assert worker.id in Enum.map(results, & &1.id)

      results_upper = Workers.search_workers("ALICE")
      assert length(results_upper) >= 1
      assert worker.id in Enum.map(results_upper, & &1.id)
    end

    test "searches workers with multiple results ordered by name" do
      worker_a =
        worker_fixture(%{"properties" => %{"name" => "Alice Smith", "email" => "alice@test.com"}})

      worker_b =
        worker_fixture(%{"properties" => %{"name" => "Bob Smith", "email" => "bob@test.com"}})

      worker_c =
        worker_fixture(%{
          "properties" => %{"name" => "Charlie Smith", "email" => "charlie@test.com"}
        })

      results = Workers.search_workers("Smith")
      names = Enum.map(results, & &1.properties["name"])

      # Should be ordered alphabetically
      assert names == Enum.sort(names)
      assert length(results) >= 3
    end

    test "checks worker existence by email" do
      worker_fixture(%{"properties" => %{"name" => "Test", "email" => "exists@test.com"}})

      assert Workers.worker_exists_with_email?("exists@test.com")
      refute Workers.worker_exists_with_email?("notfound@test.com")
    end
  end

  describe "employment queries" do
    test "lists employments for specific worker" do
      worker1 = worker_fixture()
      worker2 = worker_fixture()

      emp1 = employment_fixture(worker1.id)
      emp2 = employment_fixture(worker1.id)
      _emp3 = employment_fixture(worker2.id)

      employments = Employments.list_employments_for_worker(worker1.id)
      emp_ids = Enum.map(employments, & &1.id)

      assert emp1.id in emp_ids
      assert emp2.id in emp_ids
      assert length(employments) == 2
    end

    test "counts active employments for worker" do
      worker = worker_fixture()

      employment_fixture(worker.id, %{"status" => "active"})
      employment_fixture(worker.id, %{"status" => "active"})
      employment_fixture(worker.id, %{"status" => "completed"})

      count = Employments.count_active_employments(worker.id)
      assert count == 2
    end

    test "lists employments ordered by start_time descending" do
      worker = worker_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _emp_old = employment_fixture(worker.id, %{"start_time" => DateTime.add(now, -86400 * 365)})
      emp_recent = employment_fixture(worker.id, %{"start_time" => now})

      employments = Employments.list_employments_for_worker(worker.id)

      # Most recent should be first
      assert hd(employments).id == emp_recent.id
    end
  end

  describe "shift queries by status" do
    test "filters shifts by active status" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      shift1 = shift_fixture(employment.id, worker.id, %{"status" => "active"})
      _shift2 = shift_fixture(employment.id, worker.id, %{"status" => "completed"})
      shift3 = shift_fixture(employment.id, worker.id, %{"status" => "active"})

      # Query using Events.list_events with status filter
      active_shifts = Events.list_events(%{"status" => "active", "event_type" => "shift"})
      shift_ids = Enum.map(active_shifts, & &1.id)

      assert shift1.id in shift_ids
      assert shift3.id in shift_ids
      assert length(Enum.filter(shift_ids, &(&1 in [shift1.id, shift3.id]))) == 2
    end

    test "filters shifts by completed status" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      _shift1 = shift_fixture(employment.id, worker.id, %{"status" => "active"})
      shift2 = shift_fixture(employment.id, worker.id, %{"status" => "completed"})

      completed_shifts = Events.list_events(%{"status" => "completed", "event_type" => "shift"})
      shift_ids = Enum.map(completed_shifts, & &1.id)

      assert shift2.id in shift_ids
    end

    test "lists all shifts for worker regardless of status" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      shift1 = shift_fixture(employment.id, worker.id, %{"status" => "active"})
      shift2 = shift_fixture(employment.id, worker.id, %{"status" => "completed"})
      shift3 = shift_fixture(employment.id, worker.id, %{"status" => "cancelled"})

      all_shifts = Shifts.list_shifts_for_worker(worker.id)
      shift_ids = Enum.map(all_shifts, & &1.id)

      assert shift1.id in shift_ids
      assert shift2.id in shift_ids
      assert shift3.id in shift_ids
      assert length(all_shifts) >= 3
    end
  end

  describe "shift queries by date range" do
    test "filters shifts by start_date" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      base = DateTime.add(employment.start_time, 86400 * 7)
      past = DateTime.add(base, -86400 * 5)
      future = DateTime.add(base, 86400 * 5)

      _shift_past = shift_fixture(employment.id, worker.id, %{"start_time" => past})
      shift_now = shift_fixture(employment.id, worker.id, %{"start_time" => base})
      shift_future = shift_fixture(employment.id, worker.id, %{"start_time" => future})

      # Get shifts from 2 days before base
      filter_start = DateTime.add(base, -86400 * 2)
      shifts = Shifts.list_shifts_for_worker(worker.id, start_date: filter_start)
      shift_ids = Enum.map(shifts, & &1.id)

      assert shift_now.id in shift_ids
      assert shift_future.id in shift_ids
      assert length(shifts) >= 2
    end

    test "filters shifts by end_date" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      base = DateTime.add(employment.start_time, 86400 * 7)
      shift_early = shift_fixture(employment.id, worker.id, %{"start_time" => base})

      shift_later =
        shift_fixture(employment.id, worker.id, %{"start_time" => DateTime.add(base, 86400 * 10)})

      # Only get shifts before 5 days from base
      filter_end = DateTime.add(base, 86400 * 5)
      shifts = Shifts.list_shifts_for_worker(worker.id, end_date: filter_end)
      shift_ids = Enum.map(shifts, & &1.id)

      assert shift_early.id in shift_ids
      # shift_later should be excluded as it starts after filter_end
    end

    test "filters shifts by both start and end date" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      base = DateTime.add(employment.start_time, 86400 * 15)

      _shift_before =
        shift_fixture(employment.id, worker.id, %{"start_time" => DateTime.add(base, -86400 * 5)})

      shift_in_range = shift_fixture(employment.id, worker.id, %{"start_time" => base})

      _shift_after =
        shift_fixture(employment.id, worker.id, %{"start_time" => DateTime.add(base, 86400 * 10)})

      shifts =
        Shifts.list_shifts_for_worker(worker.id,
          start_date: DateTime.add(base, -86400 * 2),
          end_date: DateTime.add(base, 86400 * 2)
        )

      shift_ids = Enum.map(shifts, & &1.id)
      assert shift_in_range.id in shift_ids
      assert length(shifts) >= 1
    end
  end

  describe "shift queries by employment" do
    test "lists shifts for specific employment" do
      worker = worker_fixture()
      employment1 = employment_fixture(worker.id)
      employment2 = employment_fixture(worker.id)

      shift1 = shift_fixture(employment1.id, worker.id)
      shift2 = shift_fixture(employment1.id, worker.id)
      _shift3 = shift_fixture(employment2.id, worker.id)

      shifts = Shifts.list_shifts_for_employment(employment1.id)
      shift_ids = Enum.map(shifts, & &1.id)

      assert shift1.id in shift_ids
      assert shift2.id in shift_ids
      assert length(shifts) == 2
    end

    test "finds shifts by parent employment" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      shift = shift_fixture(employment.id, worker.id)

      # Verify parent relationship
      fetched_shift = Shifts.get_shift!(shift.id)
      assert fetched_shift.parent_id == employment.id
      assert fetched_shift.parent.id == employment.id
    end
  end

  describe "location queries" do
    test "searches locations by name" do
      location =
        location_fixture(%{
          "properties" => %{"name" => "Headquarters", "address" => "123 Main St"}
        })

      _other =
        location_fixture(%{
          "properties" => %{"name" => "Branch Office", "address" => "456 Elm St"}
        })

      results = Mosaic.Locations.search_locations("Headquarters")
      result_ids = Enum.map(results, & &1.id)

      assert location.id in result_ids
    end

    test "searches locations by address" do
      location =
        location_fixture(%{
          "properties" => %{"name" => "Office", "address" => "123 Unique Street"}
        })

      _other =
        location_fixture(%{"properties" => %{"name" => "Store", "address" => "789 Other Ave"}})

      results = Mosaic.Locations.search_locations("Unique Street")
      result_ids = Enum.map(results, & &1.id)

      assert location.id in result_ids
    end

    test "filters locations by minimum capacity" do
      large =
        location_fixture(%{
          "properties" => %{"name" => "Large", "address" => "1 St", "capacity" => 100}
        })

      medium =
        location_fixture(%{
          "properties" => %{"name" => "Medium", "address" => "2 St", "capacity" => 50}
        })

      _small =
        location_fixture(%{
          "properties" => %{"name" => "Small", "address" => "3 St", "capacity" => 10}
        })

      results = Mosaic.Locations.get_locations_with_capacity(40)
      result_ids = Enum.map(results, & &1.id)

      assert large.id in result_ids
      assert medium.id in result_ids
      assert length(results) == 2
    end
  end

  describe "complex query scenarios" do
    test "finds all shifts for a worker across multiple employments" do
      worker = worker_fixture()
      employment1 = employment_fixture(worker.id)
      employment2 = employment_fixture(worker.id)

      shift1 = shift_fixture(employment1.id, worker.id)
      shift2 = shift_fixture(employment1.id, worker.id)
      shift3 = shift_fixture(employment2.id, worker.id)

      all_shifts = Shifts.list_shifts_for_worker(worker.id)
      shift_ids = Enum.map(all_shifts, & &1.id)

      assert shift1.id in shift_ids
      assert shift2.id in shift_ids
      assert shift3.id in shift_ids
      assert length(all_shifts) >= 3
    end

    test "queries events by type and status combination" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      shift1 = shift_fixture(employment.id, worker.id, %{"status" => "active"})
      _shift2 = shift_fixture(employment.id, worker.id, %{"status" => "completed"})

      # Query for active shifts specifically
      active_shifts = Events.list_events(%{"event_type" => "shift", "status" => "active"})
      shift_ids = Enum.map(active_shifts, & &1.id)

      assert shift1.id in shift_ids
    end

    test "finds workers by partial name and verifies their active employments" do
      worker =
        worker_fixture(%{"properties" => %{"name" => "John Doe", "email" => "john@test.com"}})

      employment_fixture(worker.id, %{"status" => "active"})
      employment_fixture(worker.id, %{"status" => "active"})

      # Search for worker
      results = Workers.search_workers("John")
      found_worker = hd(results)

      # Verify active employments
      count = Employments.count_active_employments(found_worker.id)
      assert count == 2
    end
  end
end
