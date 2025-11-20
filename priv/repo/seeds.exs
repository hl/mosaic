# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     Mosaic.Repo.insert!(%Mosaic.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias Mosaic.Repo
alias Mosaic.Events.EventType

# Seed Event Types
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
    can_have_children: true,
    requires_participation: true,
    schema: %{},
    rules: %{
      "allowed_children" => ["payroll_piece"]
    },
    is_active: true
  },
  %{
    name: "payroll_piece",
    category: "payroll",
    can_nest: false,
    can_have_children: false,
    requires_participation: false,
    schema: %{},
    rules: %{
      "allowed_parents" => ["clock_period"]
    },
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

IO.puts("Seeded event types successfully!")
