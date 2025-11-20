defmodule Mosaic.Test.Seeds do
  @moduledoc """
  Test database seeding helpers.

  This module provides functions to seed the test database with necessary
  fixtures like event types that are required for many tests to run.
  """

  alias Mosaic.Repo
  alias Mosaic.Events.EventType

  @doc """
  Seeds all event types needed for tests.

  This is typically called in test setup to ensure event types exist
  before creating events.
  """
  def seed_event_types do
    event_types = [
      %{
        name: "employment",
        category: "contract",
        can_nest: false,
        can_have_children: true,
        requires_participation: true,
        schema: %{},
        rules: %{
          "allowed_children" => ["shift"],
          "max_duration_days" => nil
        },
        is_active: true
      },
      %{
        name: "shift",
        category: "work",
        can_nest: true,
        can_have_children: true,
        requires_participation: true,
        schema: %{},
        rules: %{
          "allowed_children" => ["work_period", "break", "task"],
          "allowed_parents" => ["employment"]
        },
        is_active: true
      },
      %{
        name: "work_period",
        category: "work",
        can_nest: true,
        can_have_children: false,
        requires_participation: true,
        schema: %{},
        rules: %{
          "allowed_parents" => ["shift"]
        },
        is_active: true
      },
      %{
        name: "break",
        category: "work",
        can_nest: true,
        can_have_children: false,
        requires_participation: true,
        schema: %{},
        rules: %{
          "allowed_parents" => ["shift"],
          "is_paid" => false
        },
        is_active: true
      },
      %{
        name: "task",
        category: "work",
        can_nest: true,
        can_have_children: false,
        requires_participation: true,
        schema: %{},
        rules: %{
          "allowed_parents" => ["shift"]
        },
        is_active: true
      },
      %{
        name: "location_membership",
        category: "organizational",
        can_nest: false,
        can_have_children: false,
        requires_participation: true,
        schema: %{},
        rules: %{
          "participation_types" => ["parent_location", "child_location"]
        },
        is_active: true
      },
      %{
        name: "schedule",
        category: "planning",
        can_nest: false,
        can_have_children: true,
        requires_participation: true,
        schema: %{},
        rules: %{
          "allowed_children" => ["shift"],
          "allowed_statuses" => ["draft", "active", "archived"]
        },
        is_active: true
      },
      %{
        name: "clock_event",
        category: "timekeeping",
        can_nest: false,
        can_have_children: false,
        requires_participation: true,
        schema: %{},
        rules: %{},
        is_active: true
      },
      %{
        name: "clock_period",
        category: "timekeeping",
        can_nest: false,
        can_have_children: false,
        requires_participation: true,
        schema: %{},
        rules: %{},
        is_active: true
      }
    ]

    Enum.each(event_types, fn event_type_attrs ->
      Repo.insert!(
        %EventType{}
        |> EventType.changeset(event_type_attrs),
        on_conflict: :nothing,
        conflict_target: :name
      )
    end)

    :ok
  end

  @doc """
  Gets an event type by name, assuming it's been seeded.
  """
  def get_event_type!(name) do
    Repo.get_by!(EventType, name: name)
  end
end
