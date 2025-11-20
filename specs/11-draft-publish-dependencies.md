# Draft-Publish Implementation for Org Units

> **Navigation:** [📚 Index](index.md) | [🎯 Start Here](00-start-here.md) | [🔴 Architecture](architecture.md)

## Purpose
Implementation guide for building draft-and-publish workflows with dependency validation across schedule units (org units) in Mosaic.

**IMPORTANT NOTE:** This document proposes schema extensions and patterns that are NOT currently implemented. Current schema is documented in existing spec files. This is a roadmap for future implementation.

## The Problem We're Solving

Three org units (Logistics, Packing, Warehouse) need to:
- Draft schedules independently
- Share workers across units
- Publish on different timelines
- Never publish invalid combinations (overlapping worker assignments, coverage gaps)

**Core requirement**: Unit A can publish its schedule even if Unit B is still drafting, but the system must prevent publishing if it would violate shared constraints.

---

## Proposed Schema Extensions

**NOTE:** The following schema changes are PROPOSED additions, not part of the current schema.

### 1. Add Release State to Events (Proposed)

**Proposed Migration**: `priv/repo/migrations/20XX_add_release_fields_to_events.exs`

```elixir
defmodule Mosaic.Repo.Migrations.AddReleaseFieldsToEvents do
  use Ecto.Migration

  def change do
    alter table(:events) do
      # Proposed additions - NOT in current schema
      add :release_state, :string, default: "draft"  # draft, ready, published, archived
      add :release_sequence, :integer  # Version number within this org unit
      add :depends_on, :map  # JSONB: {org_unit_id => release_event_id}
      add :validation_state, :string  # pending, passed, failed, stale
      add :validation_report_id, :uuid  # FK to validation_reports if needed
      add :base_release_id, :uuid  # For draft overlays
    end

    create index(:events, [:release_state])
    create index(:events, [:validation_state])
  end
end
```

### 2. Create Schedule Dependencies Table (Proposed)

**Proposed Migration**: `priv/repo/migrations/20XX_create_schedule_dependencies.exs`

```elixir
defmodule Mosaic.Repo.Migrations.CreateScheduleDependencies do
  use Ecto.Migration

  def change do
    # Proposed new table - NOT in current schema
    create table(:schedule_dependencies, primary_key: false) do
      add :id, :uuid, primary_key: true
      add :source_org_unit_id, :uuid, null: false
      add :target_org_unit_id, :uuid, null: false
      add :constraint_type, :string, null: false  # no_overlap, shared_capacity, handoff_gap
      add :validation_function, :string  # Reference to validation rule
      add :criticality, :string, default: "blocking"  # blocking, warn
      add :properties, :map  # Constraint-specific config

      timestamps(type: :utc_datetime)
    end

    create index(:schedule_dependencies, [:source_org_unit_id])
    create index(:schedule_dependencies, [:target_org_unit_id])
    create unique_index(:schedule_dependencies, [:source_org_unit_id, :target_org_unit_id, :constraint_type])
  end
end
```

---

## Implementation Approach Using Current Schema

While the proposed schema extensions would be ideal, the draft-publish pattern can be implemented with the current schema using event properties and additional event types.

### Alternative: Use Event Properties for Release State

Instead of adding columns to the events table, store release information in properties.

**IMPORTANT:** The following examples are **domain context implementation code** (e.g., inside `lib/mosaic/schedules.ex`). Application code should call the domain context functions, not these internal implementations.

```elixir
# Inside lib/mosaic/schedules.ex (implementation code)
# Application code should call: Mosaic.Schedules.create_schedule(org_unit_id, attrs)

def create_schedule_with_release_tracking(org_unit_id, attrs) do
  Repo.transaction(fn ->
    with {:ok, event_type} <- Events.get_event_type_by_name("schedule"),
         event_attrs <- %{
           "event_type_id" => event_type.id,
           "start_time" => attrs.start_time,
           "end_time" => attrs.end_time,
           "status" => "draft",
           "properties" => %{
             "org_unit_id" => org_unit_id,
             "release_state" => "draft",  # Store in properties
             "release_sequence" => 1,
             "validation_state" => "pending"
           }
         },
         {:ok, event} <- Events.create_event(event_attrs) do
      event
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end)
end
```

### Alternative: Create Release Event Type

Create a "schedule_release" event type that tracks published versions:

```elixir
# Seed the release event type
Repo.insert!(%Mosaic.Events.EventType{
  name: "schedule_release",
  category: "planning",
  can_nest: false,
  can_have_children: true  # Children are the shifts in this release
})

# Inside lib/mosaic/releases.ex (implementation code)
# Application code should call: Mosaic.Releases.publish_schedule(schedule_id, org_unit_id)

def publish_schedule(schedule_id, org_unit_id) do
  Repo.transaction(fn ->
    schedule = Events.get_event!(schedule_id)

    # Validate the schedule
    with :ok <- validate_schedule(schedule),
         {:ok, event_type} <- Events.get_event_type_by_name("schedule_release"),
         # Create a release event that "snapshots" the current schedule
         event_attrs <- %{
           "event_type_id" => event_type.id,
           "start_time" => DateTime.utc_now(),
           "status" => "active",
           "properties" => %{
             "org_unit_id" => org_unit_id,
             "source_schedule_id" => schedule_id,
             "release_sequence" => get_next_release_sequence(org_unit_id),
             "validation_report" => generate_validation_report(schedule)
           }
         },
         {:ok, release_event} <- Events.create_event(event_attrs) do
      # Update original schedule status
      Events.update_event(schedule, %{"status" => "active"})

      release_event
    else
      {:error, reason} -> Repo.rollback(reason)
    end
  end)
end
```

---

## Implementation Modules (Using Current Schema)

**NOTE:** The following code shows how to **implement** the `Mosaic.Releases` domain context. This is infrastructure code that calls `Events.create_event()` internally. Application code should call the public functions of this context (e.g., `Releases.create_draft_schedule/2`, `Releases.publish_schedule/1`), not `Events` functions directly.

### Module: `lib/mosaic/releases.ex`

```elixir
defmodule Mosaic.Releases do
  @moduledoc """
  Manages schedule releases and publishing workflow.
  Uses current schema with properties for state tracking.

  This is a domain context that provides the public API for schedule
  release management. Application code should call these functions,
  not Events.create_event() directly.
  """
  
  import Ecto.Query
  alias Mosaic.Repo
  alias Mosaic.Events
  alias Mosaic.Events.Event
  alias Mosaic.Events.EventType
  
  @doc """
  Creates a draft schedule.
  """
  def create_draft_schedule(org_unit_id, attrs) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name("schedule"),
           event_attrs <- %{
             "event_type_id" => event_type.id,
             "start_time" => attrs.start_time,
             "end_time" => attrs.end_time,
             "status" => "draft",
             "properties" => %{
               "org_unit_id" => org_unit_id,
               "release_state" => "draft",
               "validation_state" => "pending"
             }
           },
           {:ok, event} <- Events.create_event(event_attrs) do
        event
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
  
  @doc """
  Validates a draft schedule before publishing.
  """
  def validate_schedule(schedule_id) do
    schedule = Events.get_event!(schedule_id, preload: [:children, participations: :participant])
    org_unit_id = schedule.properties["org_unit_id"]
    
    with :ok <- validate_internal_consistency(schedule),
         :ok <- validate_worker_availability(schedule),
         :ok <- validate_dependencies(org_unit_id, schedule) do
      # Update validation state in properties
      updated_properties = Map.put(schedule.properties, "validation_state", "passed")
      Events.update_event(schedule, %{"properties" => updated_properties})
      :ok
    else
      {:error, reason} ->
        updated_properties = Map.merge(schedule.properties, %{
          "validation_state" => "failed",
          "validation_errors" => reason
        })
        Events.update_event(schedule, %{"properties" => updated_properties})
        {:error, reason}
    end
  end
  
  @doc """
  Publishes a validated schedule.
  """
  def publish_schedule(schedule_id) do
    Repo.transaction(fn ->
      schedule = Events.get_event!(schedule_id)
      
      # Check validation state
      case schedule.properties["validation_state"] do
        "passed" ->
          # Update to published
          updated_properties = Map.merge(schedule.properties, %{
            "release_state" => "published",
            "published_at" => DateTime.utc_now()
          })
          
          Events.update_event(schedule, %{
            "status" => "active",
            "properties" => updated_properties
          })
          
        _ ->
          Repo.rollback("Schedule must be validated before publishing")
      end
    end)
  end
  
  @doc """
  Gets the latest published schedule for an org unit.
  """
  def get_latest_published_schedule(org_unit_id) do
    from(e in Event,
      join: et in EventType, on: e.event_type_id == et.id,
      where: et.name == "schedule",
      where: fragment("?->>'org_unit_id' = ?", e.properties, ^org_unit_id),
      where: fragment("?->>'release_state' = ?", e.properties, "published"),
      where: e.status == "active",
      order_by: [desc: e.inserted_at],
      limit: 1
    )
    |> Repo.one()
  end
  
  # Validation helpers
  
  defp validate_internal_consistency(schedule) do
    # Check for overlapping shifts within the schedule
    shifts = Mosaic.Shifts.list_shifts_for_employment(schedule.id)
    
    case find_overlaps(shifts) do
      [] -> :ok
      overlaps -> {:error, {:internal_overlaps, overlaps}}
    end
  end
  
  defp validate_worker_availability(schedule) do
    # Check if workers assigned to shifts have overlapping commitments in OTHER schedules
    # NOTE: This assumes list_shifts_for_employment exists. Alternatively, you might
    # need to query shifts that reference this schedule in their properties.

    shifts = Mosaic.Shifts.list_shifts_for_employment(schedule.id)

    conflicts =
      Enum.flat_map(shifts, fn shift ->
        worker_id = Events.get_participant_id(shift, "worker")
        check_worker_conflicts(worker_id, shift)
      end)

    case conflicts do
      [] -> :ok
      conflicts -> {:error, {:worker_conflicts, conflicts}}
    end
  end
  
  defp validate_dependencies(org_unit_id, schedule) do
    # Check dependencies on other org units
    # This could query published schedules from dependent org units
    :ok
  end
  
  defp find_overlaps(shifts) do
    # Implementation to find overlapping shifts
    []
  end
  
  defp check_worker_conflicts(worker_id, shift) do
    # Query other PUBLISHED schedules to find conflicts
    from(e in Event,
      join: et in EventType, on: e.event_type_id == et.id,
      join: p in Participation, on: p.event_id == e.id,
      where: et.name == "shift",
      where: p.participant_id == ^worker_id,
      where: p.participation_type == "worker",
      where: fragment("?->>'release_state' = ?", e.properties, "published"),
      where: e.start_time < ^shift.end_time,
      where: e.end_time > ^shift.start_time,
      where: e.id != ^shift.id
    )
    |> Repo.all()
  end
end
```

---

## Validation Patterns

### Cross-Unit Worker Overlap Detection

**NOTE:** This is internal implementation code for the Releases context. Consider creating a helper in the Shifts context for checking overlaps across org units.

```elixir
# Inside lib/mosaic/releases.ex (or consider adding to lib/mosaic/shifts.ex)

def check_worker_conflicts_across_units(worker_id, proposed_shift, exclude_schedule_id) do
  # Find all published shifts for this worker that would overlap
  # This is a complex cross-cutting query that may warrant being in a
  # dedicated context function like Shifts.check_published_conflicts/3

  conflicting_shifts =
    from(e in Event,
      join: et in EventType, on: e.event_type_id == et.id,
      join: p in Participation, on: p.event_id == e.id,
      where: et.name == "shift",
      where: p.participant_id == ^worker_id,
      where: p.participation_type == "worker",
      where: e.status == "active",
      where: fragment("?->>'release_state' = ?", e.properties, "published"),
      where: e.start_time < ^proposed_shift.end_time,
      where: e.end_time > ^proposed_shift.start_time,
      where: fragment("?->>'org_unit_id' != ?", e.properties, ^exclude_schedule_id)
    )
    |> Repo.all()

  case conflicting_shifts do
    [] -> :ok
    conflicts -> {:error, {:overlapping_assignments, conflicts}}
  end
end

# Better approach: Add to Mosaic.Shifts context
# Application code would then call:
# Mosaic.Shifts.check_published_conflicts(worker_id, proposed_shift, exclude_schedule_id)
```

---

## Testing Strategy

**NOTE:** Tests should use domain context functions. The examples below show proper usage.

```elixir
defmodule Mosaic.ReleasesTest do
  use Mosaic.DataCase

  describe "draft-publish workflow" do
    test "can create and publish schedule without conflicts" do
      # ✅ Use domain contexts to set up test data
      {:ok, org_unit} = Mosaic.Locations.create_location(%{
        "properties" => %{"name" => "Warehouse", "type" => "org_unit"}
      })

      {:ok, worker} = Mosaic.Workers.create_worker(%{
        "properties" => %{"name" => "Jane", "email" => "jane@example.com"}
      })

      {:ok, employment} = Mosaic.Employments.create_employment(worker.id, %{
        "start_time" => ~U[2024-01-01 00:00:00Z],
        "role" => "Warehouse Associate"
      })

      # ✅ Use Releases context (to be implemented)
      {:ok, schedule} = Mosaic.Releases.create_draft_schedule(org_unit.id, %{
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-31 23:59:59Z]
      })

      # ✅ Use Shifts context to add shifts
      {:ok, {shift, _}} = Mosaic.Shifts.create_shift(
        employment.id,
        worker.id,
        %{
          "start_time" => ~U[2024-01-15 09:00:00Z],
          "end_time" => ~U[2024-01-15 17:00:00Z],
          "properties" => %{"parent_schedule" => schedule.id}
        }
      )

      # ✅ Use Releases context to validate and publish
      assert :ok = Mosaic.Releases.validate_schedule(schedule.id)
      assert {:ok, published} = Mosaic.Releases.publish_schedule(schedule.id)
      assert published.properties["release_state"] == "published"
    end

    test "prevents publishing with worker conflicts" do
      # ✅ Set up test data using domain contexts
      {:ok, org_unit1} = Mosaic.Locations.create_location(%{
        "properties" => %{"name" => "Unit 1", "type" => "org_unit"}
      })

      {:ok, org_unit2} = Mosaic.Locations.create_location(%{
        "properties" => %{"name" => "Unit 2", "type" => "org_unit"}
      })

      {:ok, worker} = Mosaic.Workers.create_worker(%{
        "properties" => %{"name" => "John", "email" => "john@example.com"}
      })

      {:ok, employment} = Mosaic.Employments.create_employment(worker.id, %{
        "start_time" => ~U[2024-01-01 00:00:00Z],
        "role" => "Worker"
      })

      # ✅ Create and publish first schedule
      {:ok, schedule1} = Mosaic.Releases.create_draft_schedule(org_unit1.id, %{
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-31 23:59:59Z]
      })

      Mosaic.Shifts.create_shift(employment.id, worker.id, %{
        "start_time" => ~U[2024-01-15 09:00:00Z],
        "end_time" => ~U[2024-01-15 17:00:00Z]
      })

      Mosaic.Releases.validate_schedule(schedule1.id)
      Mosaic.Releases.publish_schedule(schedule1.id)

      # ✅ Try to create overlapping schedule in second unit
      {:ok, schedule2} = Mosaic.Releases.create_draft_schedule(org_unit2.id, %{
        start_time: ~U[2024-01-01 00:00:00Z],
        end_time: ~U[2024-01-31 23:59:59Z]
      })

      Mosaic.Shifts.create_shift(employment.id, worker.id, %{
        "start_time" => ~U[2024-01-15 10:00:00Z],  # Overlaps with schedule1!
        "end_time" => ~U[2024-01-15 18:00:00Z]
      })

      # Validation should fail due to overlap with published schedule
      assert {:error, {:worker_conflicts, _}} = Mosaic.Releases.validate_schedule(schedule2.id)
    end
  end
end
```

---

## Migration Path

To implement this system:

1. **Phase 1: Use Current Schema**
   - Store release state in properties
   - Use "schedule" event type
   - Implement validation in application layer

2. **Phase 2: Add Release Event Type** (optional)
   - Create "schedule_release" event type
   - Track published snapshots separately
   - Link releases to source schedules

3. **Phase 3: Schema Extensions** (future)
   - Add proposed columns if performance requires
   - Create schedule_dependencies table
   - Migrate properties data to columns

## Key Principles

### 0. Always Use Domain Contexts

**From Application Code:**
- ✅ Call `Mosaic.Releases.create_draft_schedule()`, `Mosaic.Releases.publish_schedule()`
- ✅ Call `Mosaic.Shifts.create_shift()` to add shifts
- ✅ Call `Mosaic.Workers.create_worker()`, `Mosaic.Locations.create_location()`
- ❌ Never call `Events.create_event()` or `Entities.create_entity()` directly

**Inside Domain Context Implementation:**
- ✅ Use `Events.get_event_type_by_name()` for type lookup
- ✅ Call `Events.create_event()` with `event_type_id`
- ✅ Use proper joins with EventType table in queries
- ✅ Use string keys in attrs maps: `%{"event_type_id" => id}`

### 1. Validation Before Publication

```elixir
# Always validate before publishing
with :ok <- Releases.validate_schedule(schedule_id) do
  Releases.publish_schedule(schedule_id)
end
```

### 2. Query Published Schedules

```elixir
# When checking conflicts, only consider published schedules
where: fragment("?->>'release_state' = ?", e.properties, "published")
```

### 3. Use Proper Event Creation Pattern

```elixir
# Always use event type lookup
with {:ok, event_type} <- Events.get_event_type_by_name("schedule") do
  Events.create_event(%{"event_type_id" => event_type.id, ...})
end
```

## See Also

- [01-events-and-participations.md](01-events-and-participations.md) - Core patterns
- [04-temporal-modeling.md](04-temporal-modeling.md) - Overlap detection
- [09-scheduling-model.md](09-scheduling-model.md) - Schedule implementation
- [10-configuration-strategy.md](10-configuration-strategy.md) - Configuration patterns
