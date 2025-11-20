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

      # Create shift within employment period (7 days after employment starts)
      shift_start = DateTime.add(employment.start_time, 86400 * 7)

      attrs = %{
        "start_time" => shift_start,
        # 8 hours
        "end_time" => DateTime.add(shift_start, 28800),
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

      # Start shift within employment period
      shift_start = DateTime.add(employment.start_time, 86400 * 7)

      attrs1 = %{
        "start_time" => shift_start,
        # 8 hours
        "end_time" => DateTime.add(shift_start, 28800),
        "status" => "active"
      }

      {:ok, _shift1} = Shifts.create_shift(employment.id, worker.id, attrs1)

      # Try to create overlapping shift
      attrs2 = %{
        # Overlaps by starting during shift1
        "start_time" => DateTime.add(shift_start, 3600),
        "end_time" => DateTime.add(shift_start, 32400),
        "status" => "active"
      }

      assert {:error, reason} = Shifts.create_shift(employment.id, worker.id, attrs2)
      assert reason =~ "overlapping"
    end

    test "allows non-overlapping shifts" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      # Start shifts within employment period
      shift_start = DateTime.add(employment.start_time, 86400 * 7)

      # First shift
      attrs1 = %{
        "start_time" => shift_start,
        "end_time" => DateTime.add(shift_start, 28800),
        "status" => "active"
      }

      {:ok, _shift1} = Shifts.create_shift(employment.id, worker.id, attrs1)

      # Second shift starts after first ends
      attrs2 = %{
        "start_time" => DateTime.add(shift_start, 28800),
        "end_time" => DateTime.add(shift_start, 57600),
        "status" => "active"
      }

      assert {:ok, _shift2} = Shifts.create_shift(employment.id, worker.id, attrs2)
    end

    test "auto-generates work periods when requested" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      # Create shift within employment period
      shift_start = DateTime.add(employment.start_time, 86400 * 7)

      attrs = %{
        "start_time" => shift_start,
        # 8 hours
        "end_time" => DateTime.add(shift_start, 28800),
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

      employment =
        employment_fixture(worker.id, %{
          # Starts in 30 days
          "start_time" => DateTime.add(now, 86400 * 30),
          # Ends in 60 days
          "end_time" => DateTime.add(now, 86400 * 60)
        })

      # Try to create shift before employment starts
      attrs = %{
        # Tomorrow (before employment)
        "start_time" => DateTime.add(now, 86400),
        "end_time" => DateTime.add(now, 86400 + 28800),
        "status" => "active"
      }

      assert {:error, reason} = Shifts.create_shift(employment.id, worker.id, attrs)
      assert reason =~ "before employment period"
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
      # Start shifts within employment period
      shift_start = DateTime.add(employment.start_time, 86400 * 7)

      # Create two non-overlapping shifts
      shift1 =
        shift_fixture(employment.id, worker.id, %{
          "start_time" => shift_start,
          # 4 hours
          "end_time" => DateTime.add(shift_start, 14400)
        })

      _shift2 =
        shift_fixture(employment.id, worker.id, %{
          # 6 hours later
          "start_time" => DateTime.add(shift_start, 21600),
          "end_time" => DateTime.add(shift_start, 36000)
        })

      # Try to extend shift1 to overlap with shift2
      # Extend into shift2
      attrs = %{"end_time" => DateTime.add(shift_start, 25200)}

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

      # Create shifts within employment period at different times
      base = DateTime.add(employment.start_time, 86400 * 7)
      # 3 days before base
      past = DateTime.add(base, -86400 * 3)
      # 3 days after base
      future = DateTime.add(base, 86400 * 3)

      shift_past = shift_fixture(employment.id, worker.id, %{"start_time" => past})
      shift_now = shift_fixture(employment.id, worker.id, %{"start_time" => base})
      shift_future = shift_fixture(employment.id, worker.id, %{"start_time" => future})

      # Get shifts from 1 day before base onwards
      filter_start = DateTime.add(base, -86400)
      shifts = Shifts.list_shifts_for_worker(worker.id, date_from: filter_start)

      shift_ids = Enum.map(shifts, & &1.id)
      assert shift_now.id in shift_ids
      assert shift_future.id in shift_ids
      refute shift_past.id in shift_ids
    end
  end

  describe "calculate hours functions" do
    test "calculates worked hours from work_period children" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      # Create shift within employment period
      shift_start = DateTime.add(employment.start_time, 86400 * 7)

      shift =
        shift_fixture(employment.id, worker.id, %{
          "start_time" => shift_start,
          # 8 hours
          "end_time" => DateTime.add(shift_start, 28800),
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

      # Create shift within employment period
      shift_start = DateTime.add(employment.start_time, 86400 * 7)

      shift =
        shift_fixture(employment.id, worker.id, %{
          "start_time" => shift_start,
          "end_time" => DateTime.add(shift_start, 28800),
          "auto_generate_periods" => true
        })

      break_hours = Shifts.calculate_break_hours(shift.id)
      # Should have at least one 30-minute break for 8-hour shift
      assert break_hours >= 0.5
    end

    test "calculates net hours (worked - unpaid breaks)" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)

      # Create shift within employment period
      shift_start = DateTime.add(employment.start_time, 86400 * 7)

      shift =
        shift_fixture(employment.id, worker.id, %{
          "start_time" => shift_start,
          "end_time" => DateTime.add(shift_start, 28800),
          "auto_generate_periods" => true
        })

      net_hours = Shifts.calculate_net_hours(shift.id)
      worked_hours = Shifts.calculate_worked_hours(shift.id)

      # Net should be equal to or less than worked (depending on unpaid breaks)
      assert net_hours <= worked_hours
      assert net_hours > 0
    end
  end

  describe "create_shift_in_schedule/3" do
    test "creates shift with valid attributes" do
      location = location_fixture()

      schedule =
        schedule_fixture(location.id, %{
          "start_time" => ~U[2024-01-01 00:00:00Z],
          "end_time" => ~U[2024-01-31 23:59:59Z]
        })

      worker = worker_fixture()

      attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z],
        "properties" => %{
          "location" => "Warehouse 1",
          "department" => "Receiving"
        }
      }

      assert {:ok, {shift, participation}} =
               Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs)

      assert shift.start_time == ~U[2024-01-15 09:00:00Z]
      assert shift.end_time == ~U[2024-01-15 17:00:00Z]
      assert shift.parent_id == schedule.id
      assert shift.properties["location"] == "Warehouse 1"
      assert participation.participant_id == worker.id
      assert participation.participation_type == "worker"
    end

    test "validates shift is within schedule period" do
      location = location_fixture()

      schedule =
        schedule_fixture(location.id, %{
          "start_time" => ~U[2024-01-01 00:00:00Z],
          "end_time" => ~U[2024-01-31 23:59:59Z]
        })

      worker = worker_fixture()

      # Shift starts before schedule
      attrs = %{
        "start_time" => ~U[2023-12-31 09:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z]
      }

      assert {:error, reason} = Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs)
      assert reason =~ "Shift starts before schedule period"
    end

    test "validates shift does not end after schedule" do
      location = location_fixture()

      schedule =
        schedule_fixture(location.id, %{
          "start_time" => ~U[2024-01-01 00:00:00Z],
          "end_time" => ~U[2024-01-31 23:59:59Z]
        })

      worker = worker_fixture()

      # Shift ends after schedule
      attrs = %{
        "start_time" => ~U[2024-01-30 09:00:00Z],
        "end_time" => ~U[2024-02-01 17:00:00Z]
      }

      assert {:error, reason} = Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs)
      assert reason =~ "Shift ends after schedule period"
    end

    test "prevents overlapping shifts for same worker" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)
      worker = worker_fixture()

      attrs1 = %{
        "start_time" => DateTime.add(schedule.start_time, 3600),
        "end_time" => DateTime.add(schedule.start_time, 10800)
      }

      {:ok, _} = Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs1)

      # Overlapping shift
      attrs2 = %{
        "start_time" => DateTime.add(schedule.start_time, 7200),
        "end_time" => DateTime.add(schedule.start_time, 14400)
      }

      assert {:error, reason} = Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs2)
      assert reason =~ "overlap"
    end

    test "allows shifts for different workers at same time" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)
      worker1 = worker_fixture()
      worker2 = worker_fixture()

      attrs = %{
        "start_time" => DateTime.add(schedule.start_time, 3600),
        "end_time" => DateTime.add(schedule.start_time, 10800)
      }

      assert {:ok, _} = Shifts.create_shift_in_schedule(schedule.id, worker1.id, attrs)
      assert {:ok, _} = Shifts.create_shift_in_schedule(schedule.id, worker2.id, attrs)
    end

    test "validates schedule exists and is correct type" do
      worker = worker_fixture()
      fake_schedule_id = Ecto.UUID.generate()

      attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z]
      }

      assert {:error, _reason} =
               Shifts.create_shift_in_schedule(fake_schedule_id, worker.id, attrs)
    end

    test "requires start_time and end_time" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)
      worker = worker_fixture()

      # Missing end_time
      attrs = %{
        "start_time" => ~U[2024-01-15 09:00:00Z]
      }

      assert {:error, reason} = Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs)
      assert reason =~ "end time is required"
    end
  end

  describe "list_shifts_for_schedule/1" do
    test "returns shifts for specific schedule" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)
      worker = worker_fixture()

      attrs1 = %{
        "start_time" => DateTime.add(schedule.start_time, 3600),
        "end_time" => DateTime.add(schedule.start_time, 10800)
      }

      attrs2 = %{
        "start_time" => DateTime.add(schedule.start_time, 86400),
        "end_time" => DateTime.add(schedule.start_time, 90000)
      }

      {:ok, {shift1, _}} = Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs1)
      {:ok, {shift2, _}} = Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs2)

      shifts = Shifts.list_shifts_for_schedule(schedule.id)
      shift_ids = Enum.map(shifts, & &1.id)

      assert length(shifts) == 2
      assert shift1.id in shift_ids
      assert shift2.id in shift_ids
    end

    test "returns shifts ordered by start_time" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)
      worker = worker_fixture()

      # Create in reverse chronological order
      attrs2 = %{
        "start_time" => DateTime.add(schedule.start_time, 86400),
        "end_time" => DateTime.add(schedule.start_time, 90000)
      }

      attrs1 = %{
        "start_time" => DateTime.add(schedule.start_time, 3600),
        "end_time" => DateTime.add(schedule.start_time, 10800)
      }

      {:ok, {_shift2, _}} = Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs2)
      {:ok, {shift1, _}} = Shifts.create_shift_in_schedule(schedule.id, worker.id, attrs1)

      shifts = Shifts.list_shifts_for_schedule(schedule.id)

      # Should be ordered by start_time ascending
      assert List.first(shifts).id == shift1.id
    end

    test "returns empty list for schedule without shifts" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)

      assert Shifts.list_shifts_for_schedule(schedule.id) == []
    end

    test "does not return shifts from other schedules" do
      location = location_fixture()

      schedule1 =
        schedule_fixture(location.id, %{
          "start_time" => ~U[2024-01-01 00:00:00Z],
          "end_time" => ~U[2024-01-31 23:59:59Z]
        })

      schedule2 =
        schedule_fixture(location.id, %{
          "start_time" => ~U[2024-02-01 00:00:00Z],
          "end_time" => ~U[2024-02-28 23:59:59Z]
        })

      worker = worker_fixture()

      attrs1 = %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z]
      }

      attrs2 = %{
        "start_time" => ~U[2024-02-15 09:00:00Z],
        "end_time" => ~U[2024-02-15 17:00:00Z]
      }

      {:ok, {shift1, _}} = Shifts.create_shift_in_schedule(schedule1.id, worker.id, attrs1)
      {:ok, {_shift2, _}} = Shifts.create_shift_in_schedule(schedule2.id, worker.id, attrs2)

      shifts = Shifts.list_shifts_for_schedule(schedule1.id)

      assert length(shifts) == 1
      assert List.first(shifts).id == shift1.id
    end
  end
end
