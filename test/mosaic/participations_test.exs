defmodule Mosaic.ParticipationsTest do
  use Mosaic.DataCase

  alias Mosaic.Participations
  alias Mosaic.Participations.Participation
  import Mosaic.Fixtures

  describe "add_participation/3" do
    test "creates participation with valid attributes" do
      worker = worker_fixture()
      event = event_fixture()

      attrs = %{"participation_type" => "worker"}

      assert {:ok, %Participation{} = participation} =
               Participations.add_participation(worker.id, event.id, attrs)

      assert participation.participant_id == worker.id
      assert participation.event_id == event.id
      assert participation.participation_type == "worker"
    end

    test "accepts optional attributes" do
      worker = worker_fixture()
      event = event_fixture()

      attrs = %{
        "participation_type" => "employee",
        "role" => "Manager",
        "properties" => %{"department" => "Sales"}
      }

      assert {:ok, participation} = Participations.add_participation(worker.id, event.id, attrs)
      assert participation.role == "Manager"
      assert participation.properties["department"] == "Sales"
    end

    test "requires participant_id" do
      event = event_fixture()
      # Manually try to create without participant_id
      assert_raise Ecto.InvalidChangesetError, fn ->
        %Participation{}
        |> Participation.changeset(%{"event_id" => event.id})
        |> Repo.insert!()
      end
    end

    test "requires event_id" do
      worker = worker_fixture()
      # Manually try to create without event_id
      assert_raise Ecto.InvalidChangesetError, fn ->
        %Participation{}
        |> Participation.changeset(%{"participant_id" => worker.id})
        |> Repo.insert!()
      end
    end

    test "requires participation_type" do
      worker = worker_fixture()
      event = event_fixture()

      assert_raise Ecto.InvalidChangesetError, fn ->
        %Participation{}
        |> Participation.changeset(%{
          "participant_id" => worker.id,
          "event_id" => event.id
        })
        |> Repo.insert!()
      end
    end
  end

  describe "remove_participation/1" do
    test "deletes the participation" do
      worker = worker_fixture()
      event = event_fixture()

      {:ok, participation} =
        Participations.add_participation(worker.id, event.id, %{"participation_type" => "worker"})

      assert {:ok, %Participation{}} = Participations.remove_participation(participation)
    end
  end

  describe "get_participation!/1" do
    test "returns the participation with given id" do
      worker = worker_fixture()
      event = event_fixture()

      {:ok, participation} =
        Participations.add_participation(worker.id, event.id, %{"participation_type" => "worker"})

      fetched = Participations.get_participation!(participation.id)
      assert fetched.id == participation.id
    end

    test "raises if participation doesn't exist" do
      assert_raise Ecto.NoResultsError, fn ->
        Participations.get_participation!(Ecto.UUID.generate())
      end
    end
  end

  describe "list_participations_for_event/1" do
    test "returns all participations for an event" do
      event = event_fixture()
      worker1 = worker_fixture()
      worker2 = worker_fixture()

      {:ok, p1} =
        Participations.add_participation(worker1.id, event.id, %{"participation_type" => "worker"})

      {:ok, p2} =
        Participations.add_participation(worker2.id, event.id, %{"participation_type" => "worker"})

      participations = Participations.list_participations_for_event(event.id)
      p_ids = Enum.map(participations, & &1.id)

      assert p1.id in p_ids
      assert p2.id in p_ids
    end
  end

  describe "list_participations_for_entity/1" do
    test "returns all participations for an entity" do
      worker = worker_fixture()
      event1 = event_fixture()
      event2 = event_fixture()

      {:ok, p1} =
        Participations.add_participation(worker.id, event1.id, %{"participation_type" => "worker"})

      {:ok, p2} =
        Participations.add_participation(worker.id, event2.id, %{"participation_type" => "worker"})

      participations = Participations.list_participations_for_entity(worker.id)
      p_ids = Enum.map(participations, & &1.id)

      assert p1.id in p_ids
      assert p2.id in p_ids
    end
  end
end
