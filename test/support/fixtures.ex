defmodule Mosaic.Fixtures do
  @moduledoc """
  Test fixtures for creating test data.

  This module provides helper functions to create valid test data
  for entities, events, participations, and domain-specific records.
  """

  alias Mosaic.Repo
  alias Mosaic.Entities.Entity
  alias Mosaic.Events.Event
  alias Mosaic.Participations.Participation
  alias Mosaic.{Workers, Locations, Employments, Shifts}
  alias Mosaic.Test.Seeds

  @doc """
  Creates a worker (person entity) with default or custom attributes.

  ## Examples

      worker = worker_fixture()
      worker = worker_fixture(%{"properties" => %{"name" => "Custom Name"}})
  """
  def worker_fixture(attrs \\ %{}) do
    default_attrs = %{
      "properties" => %{
        "name" => "Test Worker #{System.unique_integer([:positive])}",
        "email" => "worker#{System.unique_integer([:positive])}@example.com",
        "phone" => "555-0100"
      }
    }

    attrs = deep_merge(default_attrs, attrs)

    {:ok, worker} = Workers.create_worker(attrs)
    worker
  end

  @doc """
  Creates a location entity with default or custom attributes.
  """
  def location_fixture(attrs \\ %{}) do
    default_attrs = %{
      "properties" => %{
        "name" => "Test Location #{System.unique_integer([:positive])}",
        "address" => "123 Test St",
        "capacity" => 50
      }
    }

    attrs = deep_merge(default_attrs, attrs)

    {:ok, location} = Locations.create_location(attrs)
    location
  end

  @doc """
  Creates an employment event with default or custom attributes.

  Requires a worker_id. Seeds event types if not already present.
  """
  def employment_fixture(worker_id, attrs \\ %{}) do
    Seeds.seed_event_types()

    default_attrs = %{
      "start_time" => DateTime.utc_now() |> DateTime.truncate(:second),
      "end_time" => nil,
      "status" => "active",
      "role" => "Employee",
      "contract_type" => "full_time",
      "salary" => "50000"
    }

    attrs = deep_merge(default_attrs, attrs)

    case Employments.create_employment(worker_id, attrs) do
      {:ok, {employment, _participation}} -> employment
      {:error, reason} -> raise "Failed to create employment: #{inspect(reason)}"
    end
  end

  @doc """
  Creates a shift event with default or custom attributes.

  Requires employment_id and worker_id. Seeds event types if not already present.
  """
  def shift_fixture(employment_id, worker_id, attrs \\ %{}) do
    Seeds.seed_event_types()

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    default_attrs = %{
      "start_time" => now,
      # 8 hours later
      "end_time" => DateTime.add(now, 8 * 3600),
      "status" => "active",
      "location" => "Main Office",
      "department" => "Sales",
      "notes" => "Test shift",
      "auto_generate_periods" => false
    }

    attrs = deep_merge(default_attrs, attrs)

    case Shifts.create_shift(employment_id, worker_id, attrs) do
      {:ok, {shift, _participation}} -> shift
      {:error, reason} -> raise "Failed to create shift: #{inspect(reason)}"
    end
  end

  @doc """
  Creates a generic event with default or custom attributes.

  Requires event_type_id. Use this for creating custom event types
  or when you need more control than the domain-specific fixtures.
  """
  def event_fixture(attrs \\ %{}) do
    Seeds.seed_event_types()
    event_type = Seeds.get_event_type!("shift")

    default_attrs = %{
      "event_type_id" => event_type.id,
      "start_time" => DateTime.utc_now() |> DateTime.truncate(:second),
      "end_time" => DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second),
      "status" => "draft",
      "properties" => %{}
    }

    attrs = deep_merge(default_attrs, attrs)

    %Event{}
    |> Event.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Creates a generic entity with default or custom attributes.
  """
  def entity_fixture(attrs \\ %{}) do
    default_attrs = %{
      "entity_type" => "person",
      "properties" => %{
        "name" => "Test Entity #{System.unique_integer([:positive])}"
      }
    }

    attrs = deep_merge(default_attrs, attrs)

    %Entity{}
    |> Entity.changeset(attrs)
    |> Repo.insert!()
  end

  @doc """
  Creates a participation linking an entity to an event.
  """
  def participation_fixture(participant_id, event_id, attrs \\ %{}) do
    default_attrs = %{
      "participation_type" => "worker",
      "role" => nil,
      "start_time" => nil,
      "end_time" => nil,
      "properties" => %{}
    }

    attrs = deep_merge(default_attrs, attrs)

    %Participation{}
    |> Participation.changeset(
      attrs
      |> Map.put("participant_id", participant_id)
      |> Map.put("event_id", event_id)
    )
    |> Repo.insert!()
  end

  # Helper to deep merge maps with string keys
  defp deep_merge(left, right) do
    Map.merge(left, right, fn
      _key, left_val, right_val when is_map(left_val) and is_map(right_val) ->
        deep_merge(left_val, right_val)

      _key, _left_val, right_val ->
        right_val
    end)
  end
end
