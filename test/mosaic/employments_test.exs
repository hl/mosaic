defmodule Mosaic.EmploymentsTest do
  use Mosaic.DataCase

  alias Mosaic.Employments
  alias Mosaic.Test.Seeds
  import Mosaic.Fixtures

  setup do
    Seeds.seed_event_types()
    :ok
  end

  describe "create_employment/2" do
    test "creates employment with valid attributes" do
      worker = worker_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        "start_time" => now,
        "status" => "active",
        "role" => "Software Engineer",
        "contract_type" => "full_time",
        "salary" => "75000"
      }

      assert {:ok, {employment, participation}} = Employments.create_employment(worker.id, attrs)
      assert employment.status == "active"
      assert employment.properties["role"] == "Software Engineer"
      assert participation.participant_id == worker.id
      assert participation.participation_type == "employee"
    end

    test "creates participation with role" do
      worker = worker_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        "start_time" => now,
        "role" => "Manager"
      }

      assert {:ok, {_employment, participation}} = Employments.create_employment(worker.id, attrs)
      assert participation.role == "Manager"
    end

    test "prevents overlapping employments" do
      worker = worker_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs1 = %{
        "start_time" => now,
        # 1 year
        "end_time" => DateTime.add(now, 86400 * 365),
        "status" => "active"
      }

      {:ok, _employment1} = Employments.create_employment(worker.id, attrs1)

      # Try to create overlapping employment
      attrs2 = %{
        # 30 days later
        "start_time" => DateTime.add(now, 86400 * 30),
        "end_time" => DateTime.add(now, 86400 * 400),
        "status" => "active"
      }

      assert {:error, reason} = Employments.create_employment(worker.id, attrs2)
      assert reason =~ "overlapping"
    end

    test "allows non-overlapping employments" do
      worker = worker_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # First employment
      attrs1 = %{
        "start_time" => now,
        # Ends in 30 days
        "end_time" => DateTime.add(now, 86400 * 30),
        "status" => "active"
      }

      {:ok, _employment1} = Employments.create_employment(worker.id, attrs1)

      # Second employment starts after first ends
      attrs2 = %{
        # Starts in 31 days
        "start_time" => DateTime.add(now, 86400 * 31),
        "status" => "active"
      }

      assert {:ok, _employment2} = Employments.create_employment(worker.id, attrs2)
    end
  end

  describe "update_employment/2" do
    test "updates employment with valid attributes" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      attrs = %{"status" => "completed"}
      assert {:ok, updated} = Employments.update_employment(employment.id, attrs)
      assert updated.status == "completed"
    end

    test "prevents creating overlaps when updating" do
      worker = worker_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create two non-overlapping employments
      employment1 =
        employment_fixture(worker.id, %{
          "start_time" => now,
          "end_time" => DateTime.add(now, 86400 * 30)
        })

      employment2 =
        employment_fixture(worker.id, %{
          "start_time" => DateTime.add(now, 86400 * 60),
          "end_time" => DateTime.add(now, 86400 * 90)
        })

      # Try to extend employment1 to overlap with employment2
      attrs = %{"end_time" => DateTime.add(now, 86400 * 70)}

      assert {:error, reason} = Employments.update_employment(employment1.id, attrs)
      assert reason =~ "overlapping"
    end
  end

  describe "get_employment!/1" do
    test "returns employment with preloaded associations" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      fetched = Employments.get_employment!(employment.id)
      assert fetched.id == employment.id
      assert is_list(fetched.children)
      assert is_list(fetched.participations)
    end
  end

  describe "list_employments/0" do
    test "returns all employments ordered by start_time desc" do
      worker1 = worker_fixture()
      worker2 = worker_fixture()

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      _emp1 = employment_fixture(worker1.id, %{"start_time" => DateTime.add(now, -86400)})
      emp2 = employment_fixture(worker2.id, %{"start_time" => now})

      employments = Employments.list_employments()
      # Most recent first
      assert hd(employments).id == emp2.id
    end
  end

  describe "list_employments_for_worker/1" do
    test "returns employments for specific worker" do
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
  end

  describe "count_active_employments/1" do
    test "counts active employments for worker" do
      worker = worker_fixture()

      employment_fixture(worker.id, %{"status" => "active"})
      employment_fixture(worker.id, %{"status" => "active"})
      employment_fixture(worker.id, %{"status" => "completed"})

      count = Employments.count_active_employments(worker.id)
      assert count == 2
    end
  end
end
