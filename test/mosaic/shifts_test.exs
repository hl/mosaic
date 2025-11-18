defmodule Mosaic.ShiftsTest do
  use Mosaic.DataCase

  alias Mosaic.Shifts
  alias Mosaic.Test.Seeds
  import Mosaic.Fixtures

  setup do
    Seeds.seed_event_types()
    :ok
  end

  describe "create_shift/3" do
    test "creates shift with valid attributes" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      attrs = %{
        "start_time" => DateTime.add(now, 86400),
        "end_time" => DateTime.add(now, 86400 + 28800),  # 8 hours
        "status" => "active",
        "location" => "Main Office",
        "department" => "Sales"
      }

      assert {:ok, {shift, participation}} = Shifts.create_shift(employment.id, worker.id, attrs)
      assert shift.status == "active"
      assert shift.properties["location"] == "Main Office"
      assert shift.parent_id == employment.id
      assert participation.participant_id == worker.id
    end

    test "prevents overlapping shifts" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs1 = %{
        "start_time" => DateTime.add(now, 86400),
        "end_time" => DateTime.add(now, 86400 + 28800),  # 8 hours
        "status" => "active"
      }

      {:ok, _shift1} = Shifts.create_shift(employment.id, worker.id, attrs1)

      # Try to create overlapping shift
      attrs2 = %{
        "start_time" => DateTime.add(now, 86400 + 3600),  # Overlaps by starting during shift1
        "end_time" => DateTime.add(now, 86400 + 32400),
        "status" => "active"
      }

      assert {:error, reason} = Shifts.create_shift(employment.id, worker.id, attrs2)
      assert reason =~ "overlapping"
    end

    test "allows non-overlapping shifts" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # First shift
      attrs1 = %{
        "start_time" => DateTime.add(now, 86400),
        "end_time" => DateTime.add(now, 86400 + 28800),
        "status" => "active"
      }

      {:ok, _shift1} = Shifts.create_shift(employment.id, worker.id, attrs1)

      # Second shift starts after first ends
      attrs2 = %{
        "start_time" => DateTime.add(now, 86400 + 28800),
        "end_time" => DateTime.add(now, 86400 + 57600),
        "status" => "active"
      }

      assert {:ok, _shift2} = Shifts.create_shift(employment.id, worker.id, attrs2)
    end

    test "auto-generates work periods when requested" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      attrs = %{
        "start_time" => DateTime.add(now, 86400),
        "end_time" => DateTime.add(now, 86400 + 28800),  # 8 hours
        "status" => "active",
        "auto_generate_periods" => true
      }

      assert {:ok, {shift, _participation}} = Shifts.create_shift(employment.id, worker.id, attrs)

      # Reload shift with children
      shift_with_children = Shifts.get_shift!(shift.id)
      assert length(shift_with_children.children) > 0
    end

    test "validates shift is within employment period" do
      worker = worker_fixture()
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      employment = employment_fixture(worker.id, %{
        "start_time" => DateTime.add(now, 86400 * 30),  # Starts in 30 days
        "end_time" => DateTime.add(now, 86400 * 60)     # Ends in 60 days
      })

      # Try to create shift before employment starts
      attrs = %{
        "start_time" => DateTime.add(now, 86400),  # Tomorrow (before employment)
        "end_time" => DateTime.add(now, 86400 + 28800),
        "status" => "active"
      }

      assert {:error, reason} = Shifts.create_shift(employment.id, worker.id, attrs)
      assert reason =~ "must be within the employment period"
    end
  end

  describe "update_shift/2" do
    test "updates shift with valid attributes" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)
      shift = shift_fixture(employment.id, worker.id)

      attrs = %{"status" => "completed"}
      assert {:ok, updated} = Shifts.update_shift(shift.id, attrs)
      assert updated.status == "completed"
    end

    test "prevents creating overlaps when updating" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      # Create two non-overlapping shifts
      shift1 = shift_fixture(employment.id, worker.id, %{
        "start_time" => DateTime.add(now, 86400),
        "end_time" => DateTime.add(now, 86400 + 14400)  # 4 hours
      })

      _shift2 = shift_fixture(employment.id, worker.id, %{
        "start_time" => DateTime.add(now, 86400 + 21600),  # 6 hours later
        "end_time" => DateTime.add(now, 86400 + 36000)
      })

      # Try to extend shift1 to overlap with shift2
      attrs = %{"end_time" => DateTime.add(now, 86400 + 25200)}  # Extend into shift2

      assert {:error, reason} = Shifts.update_shift(shift1.id, attrs)
      assert reason =~ "overlapping"
    end
  end

  describe "get_shift!/1" do
    test "returns shift with all related data" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)
      shift = shift_fixture(employment.id, worker.id)

      fetched = Shifts.get_shift!(shift.id)
      assert fetched.id == shift.id
      assert %Mosaic.Events.Event{} = fetched.parent
      assert is_list(fetched.children)
      assert is_list(fetched.participations)
    end
  end

  describe "list_shifts/0" do
    test "returns all shifts" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      shift1 = shift_fixture(employment.id, worker.id)
      shift2 = shift_fixture(employment.id, worker.id)

      shifts = Shifts.list_shifts()
      shift_ids = Enum.map(shifts, & &1.id)

      assert shift1.id in shift_ids
      assert shift2.id in shift_ids
    end
  end

  describe "list_shifts_for_employment/1" do
    test "returns shifts for specific employment" do
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
  end

  describe "list_shifts_for_worker/2" do
    test "returns shifts for specific worker" do
      worker1 = worker_fixture()
      worker2 = worker_fixture()

      employment1 = employment_fixture(worker1.id)
      employment2 = employment_fixture(worker2.id)

      shift1 = shift_fixture(employment1.id, worker1.id)
      shift2 = shift_fixture(employment1.id, worker1.id)
      _shift3 = shift_fixture(employment2.id, worker2.id)

      shifts = Shifts.list_shifts_for_worker(worker1.id)
      shift_ids = Enum.map(shifts, & &1.id)

      assert shift1.id in shift_ids
      assert shift2.id in shift_ids
      assert length(shifts) == 2
    end

    test "filters by date range" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)
      past = DateTime.add(now, -86400 * 10)
      future = DateTime.add(now, 86400 * 10)

      _shift_past = shift_fixture(employment.id, worker.id, %{"start_time" => past})
      shift_now = shift_fixture(employment.id, worker.id, %{"start_time" => now})
      shift_future = shift_fixture(employment.id, worker.id, %{"start_time" => future})

      # Get shifts from yesterday onwards
      yesterday = DateTime.add(now, -86400)
      shifts = Shifts.list_shifts_for_worker(worker.id, start_date: yesterday)

      shift_ids = Enum.map(shifts, & &1.id)
      assert shift_now.id in shift_ids
      assert shift_future.id in shift_ids
      assert length(shifts) == 2
    end
  end

  describe "calculate hours functions" do
    test "calculates worked hours from work_period children" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      shift = shift_fixture(employment.id, worker.id, %{
        "start_time" => now,
        "end_time" => DateTime.add(now, 28800),  # 8 hours
        "auto_generate_periods" => true
      })

      hours = Shifts.calculate_worked_hours(shift.id)
      # Should have work periods totaling less than 8 hours (due to breaks)
      assert hours > 0
      assert hours < 8
    end

    test "calculates break hours" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      shift = shift_fixture(employment.id, worker.id, %{
        "start_time" => now,
        "end_time" => DateTime.add(now, 28800),
        "auto_generate_periods" => true
      })

      break_hours = Shifts.calculate_break_hours(shift.id)
      # Should have at least one 30-minute break for 8-hour shift
      assert break_hours >= 0.5
    end

    test "calculates net hours (worked - unpaid breaks)" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      shift = shift_fixture(employment.id, worker.id, %{
        "start_time" => now,
        "end_time" => DateTime.add(now, 28800),
        "auto_generate_periods" => true
      })

      net_hours = Shifts.calculate_net_hours(shift.id)
      worked_hours = Shifts.calculate_worked_hours(shift.id)

      # Net should be equal to or less than worked (depending on unpaid breaks)
      assert net_hours <= worked_hours
      assert net_hours > 0
    end
  end
end
