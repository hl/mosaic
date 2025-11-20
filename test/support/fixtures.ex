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
  alias Mosaic.{Workers, Locations, Employments, Shifts, Schedules}
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
  Uses unique start times to avoid overlaps between test employments.
  """
  def employment_fixture(worker_id, attrs \\ %{}) do
    Seeds.seed_event_types()

    # Only use unique offset if start_time is not provided
    default_attrs =
      if Map.has_key?(attrs, "start_time") do
        # User provided start_time, just set end_time if not provided
        start_time = attrs["start_time"]

        %{
          "start_time" => start_time,
          # 1 year duration
          "end_time" => DateTime.add(start_time, 86400 * 365),
          "status" => "active",
          "role" => "Employee",
          "contract_type" => "full_time",
          "salary" => "50000"
        }
      else
        # No start_time provided, generate unique one with large spacing
        unique_offset = System.unique_integer([:positive, :monotonic]) |> rem(10000)

        base_time =
          DateTime.utc_now()
          # 3-year spacing between employments
          |> DateTime.add(unique_offset * 86400 * 1095)
          |> DateTime.truncate(:second)

        %{
          "start_time" => base_time,
          # 1 year duration
          "end_time" => DateTime.add(base_time, 86400 * 365),
          "status" => "active",
          "role" => "Employee",
          "contract_type" => "full_time",
          "salary" => "50000"
        }
      end

    attrs = deep_merge(default_attrs, attrs)

    case Employments.create_employment(worker_id, attrs) do
      {:ok, {employment, _participation}} -> employment
      {:error, reason} -> raise "Failed to create employment: #{inspect(reason)}"
    end
  end

  @doc """
  Creates a shift event with default or custom attributes.

  Requires employment_id and worker_id. Seeds event types if not already present.
  Uses unique start times to avoid overlaps between test shifts.
  """
  def shift_fixture(employment_id, worker_id, attrs \\ %{}) do
    Seeds.seed_event_types()

    # Get the employment to know its time bounds
    alias Mosaic.{Events, Repo}
    employment = Events.get_event!(employment_id) |> Repo.preload(:event_type)

    # Only use unique offset if start_time is not provided
    default_attrs =
      if Map.has_key?(attrs, "start_time") do
        # User provided start_time, just set end_time if not provided
        start_time = attrs["start_time"]

        %{
          "start_time" => start_time,
          # 8 hours later
          "end_time" => DateTime.add(start_time, 8 * 3600),
          "status" => "active",
          "location" => "Main Office",
          "department" => "Sales",
          "notes" => "Test shift",
          "auto_generate_periods" => false
        }
      else
        # No start_time provided, generate unique one within employment period
        # Use small offsets to ensure shifts stay within 1-year employment period
        unique_offset = System.unique_integer([:positive, :monotonic]) |> rem(100)

        # Start 7 days after employment start, with small offset (100 offsets * 1 day = 100 days max)
        base_time =
          DateTime.add(employment.start_time, 86400 * 7 + unique_offset * 86400)
          |> DateTime.truncate(:second)

        %{
          "start_time" => base_time,
          # 8 hours later
          "end_time" => DateTime.add(base_time, 8 * 3600),
          "status" => "active",
          "location" => "Main Office",
          "department" => "Sales",
          "notes" => "Test shift",
          "auto_generate_periods" => false
        }
      end

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
  Uses unique timestamps to avoid potential overlaps.
  """
  def event_fixture(attrs \\ %{}) do
    Seeds.seed_event_types()
    event_type = Seeds.get_event_type!("shift")

    unique_offset = System.unique_integer([:positive, :monotonic]) |> rem(100_000)

    base_time =
      DateTime.utc_now()
      # Minutes in the future
      |> DateTime.add(unique_offset * 60)
      |> DateTime.truncate(:second)

    default_attrs = %{
      "event_type_id" => event_type.id,
      "start_time" => base_time,
      # 1 hour later
      "end_time" => DateTime.add(base_time, 3600),
      "status" => "draft",
      "properties" => %{}
    }

    attrs = deep_merge(default_attrs, attrs)

    # If start_time was provided, ensure end_time is after it
    attrs =
      if Map.has_key?(attrs, "start_time") do
        start_time = attrs["start_time"]
        end_time = Map.get(attrs, "end_time")

        if is_nil(end_time) or DateTime.compare(end_time, start_time) != :gt do
          Map.put(attrs, "end_time", DateTime.add(start_time, 3600))
        else
          attrs
        end
      else
        attrs
      end

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
  Creates a schedule for a location with default or custom attributes.
  """
  def schedule_fixture(location_id, attrs \\ %{}) do
    default_attrs = %{
      "start_time" => DateTime.utc_now(),
      "end_time" => DateTime.add(DateTime.utc_now(), 30, :day),
      "status" => "draft",
      "properties" => %{
        "timezone" => "UTC",
        "version" => 1
      }
    }

    attrs = deep_merge(default_attrs, attrs)

    {:ok, {schedule, _participation}} = Schedules.create_schedule(location_id, attrs)
    schedule
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
