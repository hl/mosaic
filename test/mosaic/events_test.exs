defmodule Mosaic.EventsTest do
  use Mosaic.DataCase

  alias Mosaic.Events
  alias Mosaic.Events.Event
  alias Mosaic.Test.Seeds
  import Mosaic.Fixtures

  setup do
    Seeds.seed_event_types()
    :ok
  end

  describe "list_events/1" do
    test "returns all events" do
      event1 = event_fixture()
      event2 = event_fixture()

      events = Events.list_events()
      assert length(events) == 2
      assert Enum.any?(events, &(&1.id == event1.id))
      assert Enum.any?(events, &(&1.id == event2.id))
    end

    test "filters by event_type" do
      shift_type = Seeds.get_event_type!("shift")
      employment_type = Seeds.get_event_type!("employment")

      shift_event = event_fixture(%{"event_type_id" => shift_type.id})
      _employment_event = event_fixture(%{"event_type_id" => employment_type.id})

      events = Events.list_events(event_type: shift_type.id)
      assert length(events) == 1
      assert hd(events).id == shift_event.id
    end

    test "filters by status" do
      active_event = event_fixture(%{"status" => "active"})
      _draft_event = event_fixture(%{"status" => "draft"})

      events = Events.list_events(status: "active")
      assert length(events) == 1
      assert hd(events).id == active_event.id
    end

    test "filters by parent_id" do
      parent = event_fixture()
      child = event_fixture(%{"parent_id" => parent.id})
      _other = event_fixture()

      events = Events.list_events(parent_id: parent.id)
      assert length(events) == 1
      assert hd(events).id == child.id
    end
  end

  describe "get_event!/2" do
    test "returns the event with given id" do
      event = event_fixture()
      fetched = Events.get_event!(event.id)
      assert fetched.id == event.id
    end

    test "raises if event doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Events.get_event!(Ecto.UUID.generate())
      end
    end

    test "preloads associations when requested" do
      event = event_fixture()
      fetched = Events.get_event!(event.id, preload: [:event_type])
      assert %Mosaic.Events.EventType{} = fetched.event_type
    end
  end

  describe "create_event/1" do
    test "creates event with valid attributes" do
      event_type = Seeds.get_event_type!("shift")

      attrs = %{
        "event_type_id" => event_type.id,
        "start_time" => DateTime.utc_now(),
        "status" => "draft",
        "properties" => %{"location" => "Office"}
      }

      assert {:ok, %Event{} = event} = Events.create_event(attrs)
      assert event.status == "draft"
      assert event.properties["location"] == "Office"
    end

    test "returns error with invalid attributes" do
      assert {:error, %Ecto.Changeset{}} = Events.create_event(%{})
    end

    test "requires event_type_id" do
      attrs = %{"start_time" => DateTime.utc_now()}
      assert {:error, changeset} = Events.create_event(attrs)
      assert "can't be blank" in errors_on(changeset).event_type_id
    end

    test "requires start_time" do
      event_type = Seeds.get_event_type!("shift")
      attrs = %{"event_type_id" => event_type.id}
      assert {:error, changeset} = Events.create_event(attrs)
      assert "can't be blank" in errors_on(changeset).start_time
    end

    test "validates status is in allowed list" do
      event_type = Seeds.get_event_type!("shift")

      attrs = %{
        "event_type_id" => event_type.id,
        "start_time" => DateTime.utc_now(),
        "status" => "invalid_status"
      }

      assert {:error, changeset} = Events.create_event(attrs)
      assert "is invalid" in errors_on(changeset).status
    end
  end

  describe "update_event/2" do
    test "updates event with valid attributes" do
      event = event_fixture(%{"status" => "draft"})
      assert {:ok, updated} = Events.update_event(event, %{"status" => "active"})
      assert updated.status == "active"
    end

    test "returns error with invalid attributes" do
      event = event_fixture()
      assert {:error, %Ecto.Changeset{}} = Events.update_event(event, %{"status" => "invalid"})
    end

    test "can update properties" do
      event = event_fixture(%{"properties" => %{"note" => "original"}})

      assert {:ok, updated} =
               Events.update_event(event, %{"properties" => %{"note" => "updated"}})

      assert updated.properties["note"] == "updated"
    end
  end

  describe "delete_event/1" do
    test "deletes the event" do
      event = event_fixture()
      assert {:ok, %Event{}} = Events.delete_event(event)
      assert_raise Ecto.NoResultsError, fn -> Events.get_event!(event.id) end
    end
  end

  describe "change_event/2" do
    test "returns an event changeset" do
      event = event_fixture()
      assert %Ecto.Changeset{} = Events.change_event(event)
    end

    test "returns changeset with given changes" do
      event = event_fixture(%{"status" => "draft"})
      changeset = Events.change_event(event, %{"status" => "active"})
      assert changeset.changes.status == "active"
    end
  end

  describe "get_event_hierarchy/1" do
    test "returns parent and children" do
      parent = event_fixture()
      child1 = event_fixture(%{"parent_id" => parent.id})
      child2 = event_fixture(%{"parent_id" => parent.id})

      hierarchy = Events.get_event_hierarchy(parent.id)
      assert hierarchy.id == parent.id
      assert length(hierarchy.children) == 2
      child_ids = Enum.map(hierarchy.children, & &1.id)
      assert child1.id in child_ids
      assert child2.id in child_ids
    end
  end

  describe "get_event_type_by_name/1" do
    test "returns event type by name" do
      assert {:ok, event_type} = Events.get_event_type_by_name("shift")
      assert event_type.name == "shift"
    end

    test "returns error if event type doesn't exist" do
      assert {:error, _} = Events.get_event_type_by_name("nonexistent")
    end
  end

  describe "list_event_types/0" do
    test "returns all active event types" do
      event_types = Events.list_event_types()
      assert length(event_types) >= 4
      assert Enum.all?(event_types, & &1.is_active)
    end
  end

  describe "validate_event_type/3" do
    test "returns ok tuple if event type matches" do
      shift_type = Seeds.get_event_type!("shift")
      event = event_fixture(%{"event_type_id" => shift_type.id})

      assert {:ok, fetched} = Events.validate_event_type(event.id, "shift")
      assert fetched.id == event.id
    end

    test "returns error if event type doesn't match" do
      shift_type = Seeds.get_event_type!("shift")
      event = event_fixture(%{"event_type_id" => shift_type.id})

      assert {:error, message} = Events.validate_event_type(event.id, "employment")
      assert message =~ "not an employment"
    end

    test "returns error if event doesn't exist" do
      assert {:error, "Event not found"} =
               Events.validate_event_type(Ecto.UUID.generate(), "shift")
    end
  end

  describe "get_participant_id/2" do
    test "returns participant_id for given participation_type" do
      event = event_fixture()
      worker = worker_fixture()

      _participation =
        participation_fixture(worker.id, event.id, %{"participation_type" => "worker"})

      event = Events.get_event!(event.id, preload: [:participations])
      assert Events.get_participant_id(event, "worker") == worker.id
    end

    test "returns nil if participation_type doesn't exist" do
      event = event_fixture()
      event = Events.get_event!(event.id, preload: [:participations])
      assert Events.get_participant_id(event, "worker") == nil
    end
  end

  describe "list_events_by_type/2" do
    test "returns events filtered by type name" do
      shift_type = Seeds.get_event_type!("shift")
      employment_type = Seeds.get_event_type!("employment")

      shift = event_fixture(%{"event_type_id" => shift_type.id})
      _employment = event_fixture(%{"event_type_id" => employment_type.id})

      events = Events.list_events_by_type("shift")
      assert length(events) == 1
      assert hd(events).id == shift.id
    end
  end

  describe "list_events_for_participant/3" do
    test "returns events for a specific participant" do
      worker = worker_fixture()
      event1 = event_fixture()
      event2 = event_fixture()
      # Not participated
      _event3 = event_fixture()

      participation_fixture(worker.id, event1.id)
      participation_fixture(worker.id, event2.id)

      events = Events.list_events_for_participant("shift", worker.id)
      assert length(events) == 2
      event_ids = Enum.map(events, & &1.id)
      assert event1.id in event_ids
      assert event2.id in event_ids
    end

    test "filters by date range" do
      worker = worker_fixture()
      now = DateTime.utc_now()
      # 30 days ago
      past = DateTime.add(now, -86400 * 30)
      # 30 days from now
      future = DateTime.add(now, 86400 * 30)

      event_past = event_fixture(%{"start_time" => past})
      event_now = event_fixture(%{"start_time" => now})
      event_future = event_fixture(%{"start_time" => future})

      participation_fixture(worker.id, event_past.id)
      participation_fixture(worker.id, event_now.id)
      participation_fixture(worker.id, event_future.id)

      # Get events from yesterday onwards
      yesterday = DateTime.add(now, -86400)
      events = Events.list_events_for_participant("shift", worker.id, start_date: yesterday)

      event_ids = Enum.map(events, & &1.id)
      refute event_past.id in event_ids
      assert event_now.id in event_ids
      assert event_future.id in event_ids
    end
  end
end
