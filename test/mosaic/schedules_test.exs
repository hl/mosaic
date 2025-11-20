defmodule Mosaic.SchedulesTest do
  use Mosaic.DataCase

  alias Mosaic.Schedules
  alias Mosaic.Events.Event
  import Mosaic.Fixtures

  setup do
    Mosaic.Test.Seeds.seed_event_types()
    :ok
  end

  describe "create_schedule/2" do
    test "creates schedule with valid attributes" do
      location = location_fixture()

      attrs = %{
        "start_time" => ~U[2024-01-01 00:00:00Z],
        "end_time" => ~U[2024-01-31 23:59:59Z],
        "status" => "draft",
        "properties" => %{
          "timezone" => "America/New_York",
          "coverage_notes" => "Need 3 workers per shift"
        }
      }

      assert {:ok, {%Event{} = schedule, participation}} =
               Schedules.create_schedule(location.id, attrs)

      assert schedule.start_time == ~U[2024-01-01 00:00:00Z]
      assert schedule.end_time == ~U[2024-01-31 23:59:59Z]
      assert schedule.status == "draft"
      assert schedule.properties["timezone"] == "America/New_York"
      assert schedule.properties["version"] == 1
      assert participation.participant_id == location.id
      assert participation.participation_type == "location_scope"
    end

    test "sets default timezone and version" do
      location = location_fixture()

      attrs = %{
        "start_time" => ~U[2024-01-01 00:00:00Z],
        "end_time" => ~U[2024-01-31 23:59:59Z]
      }

      assert {:ok, {schedule, _}} = Schedules.create_schedule(location.id, attrs)
      assert schedule.properties["timezone"] == "UTC"
      assert schedule.properties["version"] == 1
    end

    test "defaults to draft status" do
      location = location_fixture()

      attrs = %{
        "start_time" => ~U[2024-01-01 00:00:00Z],
        "end_time" => ~U[2024-01-31 23:59:59Z]
      }

      assert {:ok, {schedule, _}} = Schedules.create_schedule(location.id, attrs)
      assert schedule.status == "draft"
    end

    test "requires start_time" do
      location = location_fixture()

      attrs = %{
        "end_time" => ~U[2024-01-31 23:59:59Z]
      }

      assert {:error, changeset} = Schedules.create_schedule(location.id, attrs)
      assert "can't be blank" in errors_on(changeset).start_time
    end

    test "requires end_time" do
      location = location_fixture()

      attrs = %{
        "start_time" => ~U[2024-01-01 00:00:00Z]
      }

      assert {:error, changeset} = Schedules.create_schedule(location.id, attrs)
      assert "can't be blank" in errors_on(changeset).end_time
    end
  end

  describe "update_schedule/2" do
    test "updates schedule with valid attributes" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)

      attrs = %{
        "properties" => %{
          "coverage_notes" => "Updated notes",
          "timezone" => schedule.properties["timezone"],
          "version" => 2
        }
      }

      assert {:ok, updated} = Schedules.update_schedule(schedule, attrs)
      assert updated.properties["coverage_notes"] == "Updated notes"
      assert updated.properties["version"] == 2
    end
  end

  describe "publish_schedule/1" do
    test "changes status to active and sets published_at" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)

      assert {:ok, published} = Schedules.publish_schedule(schedule.id)
      assert published.status == "active"
      assert published.properties["published_at"] != nil
    end
  end

  describe "archive_schedule/1" do
    test "changes status to completed" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)

      assert {:ok, archived} = Schedules.archive_schedule(schedule.id)
      assert archived.status == "completed"
    end
  end

  describe "get_schedule!/1" do
    test "returns schedule by id" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)

      fetched = Schedules.get_schedule!(schedule.id)
      assert fetched.id == schedule.id
    end

    test "raises if schedule doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Schedules.get_schedule!(Ecto.UUID.generate())
      end
    end
  end

  describe "list_schedules/0" do
    test "returns all schedules ordered by start_time desc" do
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

      schedules = Schedules.list_schedules()
      schedule_ids = Enum.map(schedules, & &1.id)

      assert schedule1.id in schedule_ids
      assert schedule2.id in schedule_ids
      # Should be ordered desc by start_time
      assert List.first(schedules).id == schedule2.id
    end
  end

  describe "list_schedules_for_location/1" do
    test "returns schedules for specific location" do
      location1 = location_fixture()
      location2 = location_fixture()

      schedule1 = schedule_fixture(location1.id)
      _schedule2 = schedule_fixture(location2.id)

      schedules = Schedules.list_schedules_for_location(location1.id)
      schedule_ids = Enum.map(schedules, & &1.id)

      assert length(schedules) == 1
      assert schedule1.id in schedule_ids
    end

    test "returns empty list for location without schedules" do
      location = location_fixture()

      assert Schedules.list_schedules_for_location(location.id) == []
    end
  end

  describe "change_schedule/2" do
    test "returns a changeset" do
      location = location_fixture()
      schedule = schedule_fixture(location.id)

      changeset = Schedules.change_schedule(schedule)
      assert %Ecto.Changeset{} = changeset
    end
  end
end
