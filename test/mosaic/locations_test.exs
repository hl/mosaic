defmodule Mosaic.LocationsTest do
  use Mosaic.DataCase

  alias Mosaic.Locations
  alias Mosaic.Entities.Entity
  import Mosaic.Fixtures

  describe "list_locations/0" do
    test "returns all locations ordered by name" do
      loc1 = location_fixture(%{"properties" => %{"name" => "A Location", "address" => "123 A St"}})
      loc2 = location_fixture(%{"properties" => %{"name" => "B Location", "address" => "456 B St"}})

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
      location = location_fixture(%{"properties" => %{"name" => "Unique Office", "address" => "123 St"}})
      _other = location_fixture(%{"properties" => %{"name" => "Other Place", "address" => "456 Ave"}})

      results = Locations.search_locations("Unique")
      result_ids = Enum.map(results, & &1.id)
      assert location.id in result_ids
    end

    test "finds locations by address" do
      location = location_fixture(%{"properties" => %{"name" => "Office", "address" => "789 Unique St"}})
      _other = location_fixture(%{"properties" => %{"name" => "Place", "address" => "123 Other Ave"}})

      results = Locations.search_locations("Unique St")
      result_ids = Enum.map(results, & &1.id)
      assert location.id in result_ids
    end
  end

  describe "get_locations_with_capacity/1" do
    test "returns locations with minimum capacity" do
      large = location_fixture(%{"properties" => %{"name" => "Large", "address" => "123 St", "capacity" => 100}})
      medium = location_fixture(%{"properties" => %{"name" => "Medium", "address" => "456 St", "capacity" => 50}})
      _small = location_fixture(%{"properties" => %{"name" => "Small", "address" => "789 St", "capacity" => 10}})

      results = Locations.get_locations_with_capacity(40)
      result_ids = Enum.map(results, & &1.id)

      assert large.id in result_ids
      assert medium.id in result_ids
      assert length(results) == 2
    end
  end
end
