defmodule Mosaic.EntitiesTest do
  use Mosaic.DataCase

  alias Mosaic.Entities
  alias Mosaic.Entities.Entity
  import Mosaic.Fixtures

  describe "list_entities/0" do
    test "returns all entities" do
      entity1 = entity_fixture()
      entity2 = entity_fixture()

      entities = Entities.list_entities()
      assert length(entities) >= 2
      entity_ids = Enum.map(entities, & &1.id)
      assert entity1.id in entity_ids
      assert entity2.id in entity_ids
    end
  end

  describe "list_entities_by_type/1" do
    test "returns entities filtered by type" do
      person1 = entity_fixture(%{"entity_type" => "person"})
      person2 = entity_fixture(%{"entity_type" => "person"})
      _location = entity_fixture(%{"entity_type" => "location"})

      entities = Entities.list_entities_by_type("person")
      entity_ids = Enum.map(entities, & &1.id)
      assert person1.id in entity_ids
      assert person2.id in entity_ids
      assert length(entities) >= 2
    end
  end

  describe "get_entity!/1" do
    test "returns the entity with given id" do
      entity = entity_fixture()
      fetched = Entities.get_entity!(entity.id)
      assert fetched.id == entity.id
    end

    test "raises if entity doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Entities.get_entity!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_entity_with_participations!/1" do
    test "returns entity with participations preloaded" do
      entity = entity_fixture()
      fetched = Entities.get_entity_with_participations!(entity.id)
      assert fetched.id == entity.id
      # participations should be loaded (empty list or populated)
      assert is_list(fetched.participations)
    end
  end

  describe "create_entity/1" do
    test "creates entity with valid attributes" do
      attrs = %{
        "entity_type" => "person",
        "properties" => %{"name" => "Test Person"}
      }

      assert {:ok, %Entity{} = entity} = Entities.create_entity(attrs)
      assert entity.entity_type == "person"
      assert entity.properties["name"] == "Test Person"
    end

    test "returns error with invalid attributes" do
      assert {:error, %Ecto.Changeset{}} = Entities.create_entity(%{})
    end

    test "requires entity_type" do
      attrs = %{"properties" => %{"name" => "Test"}}
      assert {:error, changeset} = Entities.create_entity(attrs)
      assert "can't be blank" in errors_on(changeset).entity_type
    end

    test "validates entity_type format" do
      attrs = %{
        "entity_type" => "Invalid-Type!",
        "properties" => %{}
      }

      assert {:error, changeset} = Entities.create_entity(attrs)
      assert "must be lowercase letters and underscores only" in errors_on(changeset).entity_type
    end

    test "allows valid entity_type formats" do
      valid_types = ["person", "location", "test_type", "some_long_type_name"]

      for type <- valid_types do
        attrs = %{"entity_type" => type, "properties" => %{}}
        assert {:ok, _entity} = Entities.create_entity(attrs)
      end
    end
  end

  describe "update_entity/2" do
    test "updates entity with valid attributes" do
      entity = entity_fixture(%{"properties" => %{"name" => "Original"}})

      assert {:ok, updated} =
               Entities.update_entity(entity, %{"properties" => %{"name" => "Updated"}})

      assert updated.properties["name"] == "Updated"
    end

    test "can update entity_type" do
      entity = entity_fixture(%{"entity_type" => "person"})
      assert {:ok, updated} = Entities.update_entity(entity, %{"entity_type" => "organization"})
      assert updated.entity_type == "organization"
    end

    test "returns error with invalid attributes" do
      entity = entity_fixture()

      assert {:error, %Ecto.Changeset{}} =
               Entities.update_entity(entity, %{"entity_type" => "Invalid!"})
    end
  end

  describe "delete_entity/1" do
    test "deletes the entity" do
      entity = entity_fixture()
      assert {:ok, %Entity{}} = Entities.delete_entity(entity)
      assert_raise Ecto.NoResultsError, fn -> Entities.get_entity!(entity.id) end
    end
  end

  describe "change_entity/2" do
    test "returns an entity changeset" do
      entity = entity_fixture()
      assert %Ecto.Changeset{} = Entities.change_entity(entity)
    end

    test "returns changeset with given changes" do
      entity = entity_fixture(%{"properties" => %{"name" => "Original"}})
      changeset = Entities.change_entity(entity, %{"properties" => %{"name" => "Updated"}})
      assert changeset.changes.properties["name"] == "Updated"
    end
  end

  describe "create_person/1" do
    test "creates person entity" do
      attrs = %{"properties" => %{"name" => "John Doe"}}
      assert {:ok, %Entity{} = entity} = Entities.create_person(attrs)
      assert entity.entity_type == "person"
      assert entity.properties["name"] == "John Doe"
    end

    test "automatically sets entity_type to person" do
      attrs = %{"properties" => %{"name" => "Jane"}}
      assert {:ok, entity} = Entities.create_person(attrs)
      assert entity.entity_type == "person"
    end
  end

  describe "list_workers/0" do
    test "returns only person entities" do
      person1 = entity_fixture(%{"entity_type" => "person"})
      person2 = entity_fixture(%{"entity_type" => "person"})
      _location = entity_fixture(%{"entity_type" => "location"})

      workers = Entities.list_workers()
      worker_ids = Enum.map(workers, & &1.id)
      assert person1.id in worker_ids
      assert person2.id in worker_ids
    end
  end
end
