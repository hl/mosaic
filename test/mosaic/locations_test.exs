defmodule Mosaic.LocationsTest do
  use Mosaic.DataCase

  alias Mosaic.Locations
  alias Mosaic.Entities.Entity
  import Mosaic.Fixtures

  describe "list_locations/0" do
    test "returns all locations ordered by name" do
      _loc1 =
        location_fixture(%{"properties" => %{"name" => "A Location", "address" => "123 A St"}})

      _loc2 =
        location_fixture(%{"properties" => %{"name" => "B Location", "address" => "456 B St"}})

      locations = Locations.list_locations()
      assert length(locations) >= 2

      names = Enum.map(locations, & &1.properties["name"])
      assert Enum.sort(names) == names
    end
  end

  describe "get_location!/1" do
    test "returns location by id" do
      location = location_fixture()
      fetched = Locations.get_location!(location.id)
      assert fetched.id == location.id
    end

    test "raises if location doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Locations.get_location!(Ecto.UUID.generate())
      end
    end

    test "raises if entity is not a location type" do
      worker = worker_fixture()

      assert_raise Ecto.NoResultsError, fn ->
        Locations.get_location!(worker.id)
      end
    end
  end

  describe "create_location/1" do
    test "creates location with valid attributes" do
      attrs = %{
        "properties" => %{
          "name" => "Main Office",
          "address" => "123 Main St",
          "capacity" => 100
        }
      }

      assert {:ok, %Entity{} = location} = Locations.create_location(attrs)
      assert location.entity_type == "location"
      assert location.properties["name"] == "Main Office"
      assert location.properties["capacity"] == 100
    end

    test "requires name property" do
      attrs = %{
        "properties" => %{
          "address" => "123 Test St"
        }
      }

      assert {:error, changeset} = Locations.create_location(attrs)
      assert "Name is required" in errors_on(changeset).properties
    end

    test "requires address property" do
      attrs = %{
        "properties" => %{
          "name" => "Test Location"
        }
      }

      assert {:error, changeset} = Locations.create_location(attrs)
      assert "Address is required" in errors_on(changeset).properties
    end

    test "validates capacity is positive integer" do
      attrs = %{
        "properties" => %{
          "name" => "Test Location",
          "address" => "123 Test St",
          "capacity" => -10
        }
      }

      assert {:error, changeset} = Locations.create_location(attrs)
      assert "Capacity must be a positive integer" in errors_on(changeset).properties
    end

    test "accepts optional properties" do
      attrs = %{
        "properties" => %{
          "name" => "Test Location",
          "address" => "123 Test St",
          "facilities" => ["WiFi", "Parking"],
          "operating_hours" => "9am-5pm"
        }
      }

      assert {:ok, location} = Locations.create_location(attrs)
      assert location.properties["facilities"] == ["WiFi", "Parking"]
    end
  end

  describe "update_location/2" do
    test "updates location with valid attributes" do
      location = location_fixture()

      attrs = %{
        "properties" => %{
          "name" => "Updated Name",
          "address" => location.properties["address"]
        }
      }

      assert {:ok, updated} = Locations.update_location(location, attrs)
      assert updated.properties["name"] == "Updated Name"
    end
  end

  describe "delete_location/1" do
    test "deletes the location" do
      location = location_fixture()
      assert {:ok, %Entity{}} = Locations.delete_location(location)
      assert_raise Ecto.NoResultsError, fn -> Locations.get_location!(location.id) end
    end
  end

  describe "search_locations/1" do
    test "finds locations by name" do
      location =
        location_fixture(%{"properties" => %{"name" => "Unique Office", "address" => "123 St"}})

      _other =
        location_fixture(%{"properties" => %{"name" => "Other Place", "address" => "456 Ave"}})

      results = Locations.search_locations("Unique")
      result_ids = Enum.map(results, & &1.id)
      assert location.id in result_ids
    end

    test "finds locations by address" do
      location =
        location_fixture(%{"properties" => %{"name" => "Office", "address" => "789 Unique St"}})

      _other =
        location_fixture(%{"properties" => %{"name" => "Place", "address" => "123 Other Ave"}})

      results = Locations.search_locations("Unique St")
      result_ids = Enum.map(results, & &1.id)
      assert location.id in result_ids
    end
  end

  describe "get_locations_with_capacity/1" do
    test "returns locations with minimum capacity" do
      large =
        location_fixture(%{
          "properties" => %{"name" => "Large", "address" => "123 St", "capacity" => 100}
        })

      medium =
        location_fixture(%{
          "properties" => %{"name" => "Medium", "address" => "456 St", "capacity" => 50}
        })

      _small =
        location_fixture(%{
          "properties" => %{"name" => "Small", "address" => "789 St", "capacity" => 10}
        })

      results = Locations.get_locations_with_capacity(40)
      result_ids = Enum.map(results, & &1.id)

      assert large.id in result_ids
      assert medium.id in result_ids
      assert length(results) == 2
    end
  end

  describe "set_parent/2" do
    setup do
      Mosaic.Test.Seeds.seed_event_types()
      :ok
    end

    test "links a child location to a parent" do
      parent =
        location_fixture(%{"properties" => %{"name" => "HQ", "address" => "100 Main St"}})

      child =
        location_fixture(%{"properties" => %{"name" => "Branch", "address" => "200 Side St"}})

      assert {:ok, _event} = Locations.set_parent(child.id, parent.id)

      # Verify the relationship was created
      assert Locations.get_parent(child.id) == parent.id
      assert child.id in Locations.get_children(parent.id)
    end

    test "creates location_membership event with correct participations" do
      parent = location_fixture()
      child = location_fixture()

      assert {:ok, event} = Locations.set_parent(child.id, parent.id)

      # Load event with participations
      event = Mosaic.Repo.preload(event, :participations)

      assert length(event.participations) == 2

      parent_participation =
        Enum.find(event.participations, &(&1.participation_type == "parent_location"))

      child_participation =
        Enum.find(event.participations, &(&1.participation_type == "child_location"))

      assert parent_participation.participant_id == parent.id
      assert child_participation.participant_id == child.id
    end

    test "prevents circular references" do
      location_a = location_fixture()
      location_b = location_fixture()

      # Create A -> B relationship
      assert {:ok, _} = Locations.set_parent(location_b.id, location_a.id)

      # Try to create B -> A relationship (which would be circular)
      assert {:error, reason} = Locations.set_parent(location_a.id, location_b.id)
      assert reason =~ "circular reference"
    end

    test "prevents multi-level circular references" do
      location_a = location_fixture()
      location_b = location_fixture()
      location_c = location_fixture()

      # Create chain: C -> B -> A
      assert {:ok, _} = Locations.set_parent(location_b.id, location_a.id)
      assert {:ok, _} = Locations.set_parent(location_c.id, location_b.id)

      # Try to create A -> C (circular: A -> B -> C -> A)
      assert {:error, reason} = Locations.set_parent(location_a.id, location_c.id)
      assert reason =~ "circular reference"
    end

    test "validates child location exists" do
      parent = location_fixture()
      fake_id = Ecto.UUID.generate()

      assert {:error, reason} = Locations.set_parent(fake_id, parent.id)
      assert reason =~ "Location not found"
    end

    test "validates parent location exists" do
      child = location_fixture()
      fake_id = Ecto.UUID.generate()

      assert {:error, reason} = Locations.set_parent(child.id, fake_id)
      assert reason =~ "Location not found"
    end

    test "can set custom start time" do
      parent = location_fixture()
      child = location_fixture()
      start_time = ~U[2024-01-01 00:00:00Z]

      assert {:ok, event} = Locations.set_parent(child.id, parent.id, start_time)
      assert event.start_time == start_time
    end
  end

  describe "get_parent/1" do
    setup do
      Mosaic.Test.Seeds.seed_event_types()
      :ok
    end

    test "returns parent location id" do
      parent = location_fixture()
      child = location_fixture()

      {:ok, _} = Locations.set_parent(child.id, parent.id)

      assert Locations.get_parent(child.id) == parent.id
    end

    test "returns nil for location without parent" do
      location = location_fixture()
      assert Locations.get_parent(location.id) == nil
    end

    test "returns nil for removed parent relationship" do
      parent = location_fixture()
      child = location_fixture()

      {:ok, _} = Locations.set_parent(child.id, parent.id)
      assert Locations.get_parent(child.id) == parent.id

      {:ok, _} = Locations.remove_parent(child.id)
      assert Locations.get_parent(child.id) == nil
    end

    test "can query parent at specific time" do
      parent1 = location_fixture()
      parent2 = location_fixture()
      child = location_fixture()

      time1 = ~U[2024-01-01 00:00:00Z]
      time2 = ~U[2024-06-01 00:00:00Z]

      # Set parent1 at time1
      {:ok, event1} = Locations.set_parent(child.id, parent1.id, time1)

      # End parent1 relationship and set parent2 at time2
      Mosaic.Events.update_event(event1, %{"end_time" => time2})
      {:ok, _event2} = Locations.set_parent(child.id, parent2.id, time2)

      # Query at different times
      assert Locations.get_parent(child.id, time1) == parent1.id
      assert Locations.get_parent(child.id, time2) == parent2.id
    end
  end

  describe "get_children/1" do
    setup do
      Mosaic.Test.Seeds.seed_event_types()
      :ok
    end

    test "returns all child location ids" do
      parent = location_fixture()
      child1 = location_fixture()
      child2 = location_fixture()

      {:ok, _} = Locations.set_parent(child1.id, parent.id)
      {:ok, _} = Locations.set_parent(child2.id, parent.id)

      children = Locations.get_children(parent.id)
      assert length(children) == 2
      assert child1.id in children
      assert child2.id in children
    end

    test "returns empty list for location without children" do
      location = location_fixture()
      assert Locations.get_children(location.id) == []
    end

    test "does not return children whose relationship has ended" do
      parent = location_fixture()
      child1 = location_fixture()
      child2 = location_fixture()

      {:ok, _} = Locations.set_parent(child1.id, parent.id)
      {:ok, _} = Locations.set_parent(child2.id, parent.id)

      # Remove child1
      {:ok, _} = Locations.remove_parent(child1.id)

      children = Locations.get_children(parent.id)
      assert length(children) == 1
      assert child2.id in children
      refute child1.id in children
    end
  end

  describe "remove_parent/1" do
    setup do
      Mosaic.Test.Seeds.seed_event_types()
      :ok
    end

    test "ends active parent relationship" do
      parent = location_fixture()
      child = location_fixture()

      {:ok, _} = Locations.set_parent(child.id, parent.id)
      assert Locations.get_parent(child.id) == parent.id

      assert {:ok, event} = Locations.remove_parent(child.id)
      assert event.end_time != nil
      assert Locations.get_parent(child.id) == nil
    end

    test "returns error if no active parent relationship exists" do
      location = location_fixture()

      assert {:error, message} = Locations.remove_parent(location.id)
      assert message =~ "No active parent relationship found"
    end
  end

  describe "location hierarchy - complex scenarios" do
    setup do
      Mosaic.Test.Seeds.seed_event_types()
      :ok
    end

    test "supports multi-level hierarchy" do
      # Create: HQ -> Region -> Branch -> Desk
      hq = location_fixture(%{"properties" => %{"name" => "HQ", "address" => "100 Main"}})

      region =
        location_fixture(%{"properties" => %{"name" => "East Region", "address" => "200 East"}})

      branch =
        location_fixture(%{
          "properties" => %{"name" => "Boston Branch", "address" => "300 Boston"}
        })

      desk =
        location_fixture(%{"properties" => %{"name" => "Desk 1", "address" => "300 Boston D1"}})

      {:ok, _} = Locations.set_parent(region.id, hq.id)
      {:ok, _} = Locations.set_parent(branch.id, region.id)
      {:ok, _} = Locations.set_parent(desk.id, branch.id)

      # Verify structure
      assert Locations.get_parent(region.id) == hq.id
      assert Locations.get_parent(branch.id) == region.id
      assert Locations.get_parent(desk.id) == branch.id

      assert region.id in Locations.get_children(hq.id)
      assert branch.id in Locations.get_children(region.id)
      assert desk.id in Locations.get_children(branch.id)
    end

    test "location can have multiple children but only one parent" do
      parent = location_fixture()
      child1 = location_fixture()
      child2 = location_fixture()
      child3 = location_fixture()

      {:ok, _} = Locations.set_parent(child1.id, parent.id)
      {:ok, _} = Locations.set_parent(child2.id, parent.id)
      {:ok, _} = Locations.set_parent(child3.id, parent.id)

      children = Locations.get_children(parent.id)
      assert length(children) == 3
      assert Enum.all?([child1.id, child2.id, child3.id], &(&1 in children))

      # Each child should have only one parent
      assert Locations.get_parent(child1.id) == parent.id
      assert Locations.get_parent(child2.id) == parent.id
      assert Locations.get_parent(child3.id) == parent.id
    end
  end
end
