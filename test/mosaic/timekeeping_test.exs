defmodule Mosaic.TimekeepingTest do
  use Mosaic.DataCase

  alias Mosaic.Timekeeping
  alias Mosaic.Events
  alias Mosaic.Test.Seeds
  import Mosaic.Fixtures

  setup do
    Seeds.seed_event_types()
    :ok
  end

  describe "clock_in/2" do
    test "creates clock-in event with default timestamp" do
      worker = worker_fixture()

      assert {:ok, clock_event} = Timekeeping.clock_in(worker.id)
      assert clock_event.properties["event_type"] == "in"
      assert clock_event.status == "active"
      # Clock events are point-in-time, but Event schema requires end > start
      # So end_time should be start_time + 1 second
      assert DateTime.diff(clock_event.end_time, clock_event.start_time) == 1
      # Should be recent (within last 5 seconds)
      assert DateTime.diff(DateTime.utc_now(), clock_event.start_time) < 5
    end

    test "creates clock-in event with custom timestamp" do
      worker = worker_fixture()
      custom_time = ~U[2024-01-15 09:00:00Z]

      assert {:ok, clock_event} = Timekeeping.clock_in(worker.id, timestamp: custom_time)
      assert clock_event.start_time == custom_time
      assert clock_event.end_time == DateTime.add(custom_time, 1, :second)
      assert clock_event.properties["event_type"] == "in"
    end

    test "creates clock-in event with device_id" do
      worker = worker_fixture()

      assert {:ok, clock_event} = Timekeeping.clock_in(worker.id, device_id: "terminal_01")
      assert clock_event.properties["device_id"] == "terminal_01"
      assert clock_event.properties["event_type"] == "in"
    end

    test "creates clock-in event with location_id" do
      worker = worker_fixture()
      location = location_fixture()

      assert {:ok, clock_event} =
               Timekeeping.clock_in(worker.id, location_id: location.id)

      assert clock_event.properties["location_id"] == location.id
      assert clock_event.properties["event_type"] == "in"
    end

    test "creates clock-in event with gps_coords" do
      worker = worker_fixture()
      coords = %{"lat" => 40.7128, "lng" => -74.0060}

      assert {:ok, clock_event} = Timekeeping.clock_in(worker.id, gps_coords: coords)
      assert clock_event.properties["gps_coords"] == coords
      assert clock_event.properties["event_type"] == "in"
    end

    test "creates clock-in event with multiple options" do
      worker = worker_fixture()
      location = location_fixture()

      opts = [
        device_id: "terminal_01",
        location_id: location.id,
        gps_coords: %{"lat" => 40.7128, "lng" => -74.0060}
      ]

      assert {:ok, clock_event} = Timekeeping.clock_in(worker.id, opts)
      assert clock_event.properties["device_id"] == "terminal_01"
      assert clock_event.properties["location_id"] == location.id
      assert clock_event.properties["gps_coords"]["lat"] == 40.7128
    end

    test "creates participation for worker" do
      worker = worker_fixture()

      assert {:ok, clock_event} = Timekeeping.clock_in(worker.id)

      clock_event_with_participations =
        Events.get_event!(clock_event.id, preload: :participations)

      assert length(clock_event_with_participations.participations) == 1

      participation = List.first(clock_event_with_participations.participations)
      assert participation.participant_id == worker.id
      assert participation.participation_type == "worker"
    end

    test "allows multiple clock-ins for same worker" do
      worker = worker_fixture()

      assert {:ok, clock_event1} =
               Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])

      assert {:ok, clock_event2} =
               Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 13:00:00Z])

      assert clock_event1.id != clock_event2.id
      assert clock_event1.properties["event_type"] == "in"
      assert clock_event2.properties["event_type"] == "in"
    end
  end

  describe "clock_out/2" do
    test "creates clock-out event with default timestamp" do
      worker = worker_fixture()

      assert {:ok, clock_event} = Timekeeping.clock_out(worker.id)
      assert clock_event.properties["event_type"] == "out"
      assert clock_event.status == "active"
      # Clock events are point-in-time, but Event schema requires end > start
      # So end_time should be start_time + 1 second
      assert DateTime.diff(clock_event.end_time, clock_event.start_time) == 1
      # Should be recent (within last 5 seconds)
      assert DateTime.diff(DateTime.utc_now(), clock_event.start_time) < 5
    end

    test "creates clock-out event with custom timestamp" do
      worker = worker_fixture()
      custom_time = ~U[2024-01-15 17:00:00Z]

      assert {:ok, clock_event} = Timekeeping.clock_out(worker.id, timestamp: custom_time)
      assert clock_event.start_time == custom_time
      assert clock_event.end_time == DateTime.add(custom_time, 1, :second)
      assert clock_event.properties["event_type"] == "out"
    end

    test "creates clock-out event with device_id" do
      worker = worker_fixture()

      assert {:ok, clock_event} = Timekeeping.clock_out(worker.id, device_id: "terminal_01")
      assert clock_event.properties["device_id"] == "terminal_01"
      assert clock_event.properties["event_type"] == "out"
    end

    test "creates clock-out event with location_id" do
      worker = worker_fixture()
      location = location_fixture()

      assert {:ok, clock_event} =
               Timekeeping.clock_out(worker.id, location_id: location.id)

      assert clock_event.properties["location_id"] == location.id
      assert clock_event.properties["event_type"] == "out"
    end

    test "creates clock-out event with gps_coords" do
      worker = worker_fixture()
      coords = %{"lat" => 40.7128, "lng" => -74.0060}

      assert {:ok, clock_event} = Timekeeping.clock_out(worker.id, gps_coords: coords)
      assert clock_event.properties["gps_coords"] == coords
      assert clock_event.properties["event_type"] == "out"
    end

    test "creates participation for worker" do
      worker = worker_fixture()

      assert {:ok, clock_event} = Timekeeping.clock_out(worker.id)

      clock_event_with_participations =
        Events.get_event!(clock_event.id, preload: :participations)

      assert length(clock_event_with_participations.participations) == 1

      participation = List.first(clock_event_with_participations.participations)
      assert participation.participant_id == worker.id
      assert participation.participation_type == "worker"
    end
  end

  describe "create_clock_period/3" do
    test "creates clock period from valid clock events" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      assert {:ok, clock_period} =
               Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      assert clock_period.start_time == ~U[2024-01-15 09:00:00Z]
      assert clock_period.end_time == ~U[2024-01-15 17:00:00Z]
      assert clock_period.status == "active"
      assert clock_period.properties["clock_in_event_id"] == clock_in.id
      assert clock_period.properties["clock_out_event_id"] == clock_out.id
    end

    test "references matching shift in properties" do
      worker = worker_fixture()
      employment = employment_fixture(worker.id)
      shift = shift_fixture(employment.id, worker.id)

      # Clock in/out within the shift time bounds
      clock_in_time = DateTime.add(shift.start_time, 5 * 60, :second)
      clock_out_time = DateTime.add(shift.end_time, -5 * 60, :second)

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: clock_in_time)
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: clock_out_time)

      assert {:ok, clock_period} =
               Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      assert clock_period.properties["planned_shift_id"] == shift.id
    end

    test "handles no matching shift gracefully" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      assert {:ok, clock_period} =
               Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      assert clock_period.properties["planned_shift_id"] == nil
    end

    test "validates clock-out is after clock-in" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])

      assert {:error, reason} =
               Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      assert reason =~ "Clock-out must be after clock-in"
    end

    test "validates clock-in event is type 'in'" do
      worker = worker_fixture()

      {:ok, clock_out1} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out2} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      assert {:error, reason} =
               Timekeeping.create_clock_period(worker.id, clock_out1.id, clock_out2.id)

      assert reason =~ "is not a in event"
    end

    test "validates clock-out event is type 'out'" do
      worker = worker_fixture()

      {:ok, clock_in1} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_in2} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      assert {:error, reason} =
               Timekeeping.create_clock_period(worker.id, clock_in1.id, clock_in2.id)

      assert reason =~ "is not a out event"
    end

    test "validates clock events belong to worker" do
      worker1 = worker_fixture()
      worker2 = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker1.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker2.id, timestamp: ~U[2024-01-15 17:00:00Z])

      assert {:error, reason} =
               Timekeeping.create_clock_period(worker1.id, clock_in.id, clock_out.id)

      assert reason =~ "does not belong to worker"
    end

    test "creates participation for worker" do
      worker = worker_fixture()

      {:ok, clock_in} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      assert {:ok, clock_period} =
               Timekeeping.create_clock_period(worker.id, clock_in.id, clock_out.id)

      clock_period_with_participations =
        Events.get_event!(clock_period.id, preload: :participations)

      assert length(clock_period_with_participations.participations) == 1

      participation = List.first(clock_period_with_participations.participations)
      assert participation.participant_id == worker.id
      assert participation.participation_type == "worker"
    end
  end

  describe "list_clock_events/2" do
    test "returns all clock events for worker" do
      worker = worker_fixture()

      {:ok, clock_in1} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out1} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])
      {:ok, clock_in2} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-16 09:00:00Z])

      events = Timekeeping.list_clock_events(worker.id)
      event_ids = Enum.map(events, & &1.id)

      assert length(events) == 3
      assert clock_in1.id in event_ids
      assert clock_out1.id in event_ids
      assert clock_in2.id in event_ids
    end

    test "returns empty list for worker with no clock events" do
      worker = worker_fixture()

      assert Timekeeping.list_clock_events(worker.id) == []
    end

    test "does not return clock events from other workers" do
      worker1 = worker_fixture()
      worker2 = worker_fixture()

      {:ok, clock_in1} = Timekeeping.clock_in(worker1.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, _clock_in2} = Timekeeping.clock_in(worker2.id, timestamp: ~U[2024-01-15 09:00:00Z])

      events = Timekeeping.list_clock_events(worker1.id)
      event_ids = Enum.map(events, & &1.id)

      assert length(events) == 1
      assert clock_in1.id in event_ids
    end
  end

  describe "list_clock_periods/2" do
    test "returns all clock periods for worker" do
      worker = worker_fixture()

      {:ok, clock_in1} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-15 09:00:00Z])
      {:ok, clock_out1} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-15 17:00:00Z])

      {:ok, period1} =
        Timekeeping.create_clock_period(worker.id, clock_in1.id, clock_out1.id)

      {:ok, clock_in2} = Timekeeping.clock_in(worker.id, timestamp: ~U[2024-01-16 09:00:00Z])
      {:ok, clock_out2} = Timekeeping.clock_out(worker.id, timestamp: ~U[2024-01-16 17:00:00Z])

      {:ok, period2} =
        Timekeeping.create_clock_period(worker.id, clock_in2.id, clock_out2.id)

      periods = Timekeeping.list_clock_periods(worker.id)
      period_ids = Enum.map(periods, & &1.id)

      assert length(periods) == 2
      assert period1.id in period_ids
      assert period2.id in period_ids
    end

    test "returns empty list for worker with no clock periods" do
      worker = worker_fixture()

      assert Timekeeping.list_clock_periods(worker.id) == []
    end
  end
end
