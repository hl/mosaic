# Configuration Implementation Strategy

> **Navigation:** [📚 Index](index.md) | [🎯 Start Here](00-start-here.md) | [🔴 Architecture](architecture.md)

## Purpose
Practical guide for implementing configurable, multi-tenant features in Mosaic without writing one-off code for each customer or jurisdiction.

## Current State Assessment

**What we have:**
- Event/participation spine (flexible data model)
- JSONB properties for type-specific data
- Event types system with schemas
- Contexts: Events, Participations, Entities, Shifts, Employments
- Protocol-based dispatch system (see `event_type_behaviour.ex`)

**What this guide addresses:**
- Configuration-driven features vs hardcoded logic
- Blueprint system for fast tenant provisioning
- Multi-country support through configuration
- Reusable rule primitives

---

## Key Pattern: Event Type Lookup

Throughout all configuration examples, event creation follows this pattern:

```elixir
# ALWAYS use this pattern
with {:ok, event_type} <- Events.get_event_type_by_name("shift"),
     attrs <- Map.put(attrs, "event_type_id", event_type.id),
     {:ok, event} <- Events.create_event(attrs) do
  # success
end
```

**Never** pass event types as strings directly to `create_event/1`.

---

## Implementation 1: Blueprint System

### Problem
Creating a new tenant requires setting up dozens of event types, property schemas, participation roles and business rules. Currently this means manual database seeding or one-off migrations.

### Solution: Configuration Bundles

**Module**: `lib/mosaic/configuration/blueprints.ex`

```elixir
defmodule Mosaic.Configuration.Blueprints do
  @moduledoc """
  Manages configuration bundles for fast tenant provisioning.
  """
  
  alias Mosaic.Repo
  alias Mosaic.Events
  alias Mosaic.Events.EventType
  
  @doc """
  Loads a blueprint from JSON and applies it to a tenant.
  """
  def apply_blueprint(tenant_id, blueprint_name) do
    blueprint = load_blueprint(blueprint_name)
    
    Repo.transaction(fn ->
      # 1. Create event types
      Enum.each(blueprint.event_types, fn et_config ->
        create_event_type_for_tenant(tenant_id, et_config)
      end)
      
      # 2. Set up participation types (stored as documentation/config)
      Enum.each(blueprint.participation_types, fn pt_config ->
        store_participation_type_config(tenant_id, pt_config)
      end)
      
      # 3. Install rules (if using rules engine)
      Enum.each(blueprint.rules || [], fn rule_config ->
        create_rule(tenant_id, rule_config)
      end)
      
      # 4. Create default entities (if any)
      Enum.each(blueprint.default_entities || [], fn entity_config ->
        create_entity(tenant_id, entity_config)
      end)
    end)
  end
  
  defp load_blueprint(name) do
    path = Path.join(:code.priv_dir(:mosaic), "blueprints/#{name}.json")
    File.read!(path) |> Jason.decode!(keys: :atoms)
  end
  
  defp create_event_type_for_tenant(tenant_id, config) do
    # NOTE: This is system-level setup code - directly creates EventType records
    # This is an exception to the "always use domain contexts" rule because
    # this is infrastructure/configuration code, not application logic

    %EventType{}
    |> EventType.changeset(%{
      name: config.name,
      category: config.category,
      can_nest: config[:can_nest] || false,
      can_have_children: config[:can_have_children] || false,
      requires_participation: config[:requires_participation] || true,
      schema: config[:schema] || %{},
      rules: config[:rules] || %{}
    })
    |> Repo.insert()
  end
  
  defp store_participation_type_config(tenant_id, config) do
    # Store configuration about expected participation types
    # This could be in a configuration table or in tenant properties
    :ok
  end
  
  defp create_rule(tenant_id, rule_config) do
    # If using a rules engine, create rule records
    :ok
  end
  
  defp create_entity(tenant_id, entity_config) do
    # Create default entities like default locations, departments, etc.
    :ok
  end
end
```

**Blueprint Example**: `priv/blueprints/uk_distribution_centre.json`

```json
{
  "name": "uk_distribution_centre",
  "version": "1.0.0",
  "description": "UK distribution centre with shift scheduling and payroll",
  
  "event_types": [
    {
      "name": "shift",
      "category": "work",
      "can_nest": true,
      "can_have_children": true,
      "schema": {
        "properties": ["location", "department", "notes", "break_minutes"]
      }
    },
    {
      "name": "break",
      "category": "work",
      "schema": {
        "properties": ["is_paid", "break_type"]
      }
    }
  ],
  
  "participation_types": [
    {
      "name": "worker",
      "description": "Worker performing shift",
      "applies_to_events": ["shift", "work_period", "break"]
    },
    {
      "name": "supervisor",
      "description": "Shift supervisor",
      "applies_to_events": ["shift"]
    }
  ],
  
  "default_entities": [
    {
      "entity_type": "location",
      "properties": {
        "name": "Main Warehouse",
        "address": "Default location"
      }
    }
  ]
}
```

**Usage:**

```elixir
# During tenant onboarding
Mosaic.Configuration.Blueprints.apply_blueprint(tenant_id, "uk_distribution_centre")
```

---

## Implementation 2: Jurisdiction-Specific Config

### Problem
Business rules vary by country (UK vs US minimum wage, break rules, holiday entitlements). Hardcoding these in application logic requires code changes for each jurisdiction.

### Solution: Jurisdiction Configuration Files

**Module**: `lib/mosaic/configuration/jurisdictions.ex`

```elixir
defmodule Mosaic.Configuration.Jurisdictions do
  @moduledoc """
  Loads and manages jurisdiction-specific configuration.
  """
  
  def get_jurisdiction_config(country_code) do
    path = Path.join(:code.priv_dir(:mosaic), "config/countries/#{country_code}.json")
    
    case File.read(path) do
      {:ok, content} -> Jason.decode!(content, keys: :atoms)
      {:error, _} -> get_default_config()
    end
  end
  
  def get_pay_rules(org_unit_id) do
    org_unit = Mosaic.Entities.get_entity!(org_unit_id)
    jurisdiction = org_unit.properties["jurisdiction_config"]["country_code"]
    
    config = get_jurisdiction_config(jurisdiction)
    config.pay_rules
  end
  
  def get_work_time_rules(org_unit_id) do
    org_unit = Mosaic.Entities.get_entity!(org_unit_id)
    jurisdiction = org_unit.properties["jurisdiction_config"]["country_code"]
    
    config = get_jurisdiction_config(jurisdiction)
    config.work_time_rules
  end
  
  defp get_default_config do
    %{
      country_code: "DEFAULT",
      pay_rules: %{},
      work_time_rules: %{}
    }
  end
end
```

**Example**: `priv/config/countries/GB.json`

```json
{
  "country_code": "GB",
  "country_name": "United Kingdom",
  "currency": "GBP",
  "timezone_default": "Europe/London",
  
  "pay_rules": {
    "minimum_wage": {
      "23_and_over": 11.44,
      "21_22": 11.44,
      "18_20": 8.60,
      "under_18": 6.40,
      "apprentice": 6.40,
      "effective_from": "2024-04-01"
    }
  },
  
  "work_time_rules": {
    "max_hours_per_week": 48,
    "averaging_period_weeks": 17,
    "minimum_daily_rest_hours": 11,
    "minimum_weekly_rest_hours": 24
  },
  
  "leave_rules": {
    "statutory_annual_leave_days": 28,
    "accrual_method": "monthly"
  }
}
```

---

## Implementation 3: Event Creation Helpers

To ensure consistent event creation across the system:

**Module**: `lib/mosaic/events/helpers.ex`

```elixir
defmodule Mosaic.Events.Helpers do
  @moduledoc """
  Helper functions for event creation following best practices.
  """
  
  alias Mosaic.Repo
  alias Mosaic.Events
  alias Mosaic.Participations.Participation
  
  @doc """
  Creates an event with a single participant.
  Follows the proper event type lookup pattern.
  """
  def create_event_with_participant(event_type_name, participant_id, participation_type, attrs) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name(event_type_name),
           event_attrs <- Map.put(attrs, "event_type_id", event_type.id),
           {:ok, event} <- Events.create_event(event_attrs),
           participation_attrs <- %{
             "participant_id" => participant_id,
             "event_id" => event.id,
             "participation_type" => participation_type
           },
           {:ok, participation} <-
             %Participation{}
             |> Participation.changeset(participation_attrs)
             |> Repo.insert() do
        {event, participation}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
  
  @doc """
  Creates an event with multiple participants.
  """
  def create_event_with_participants(event_type_name, participants, attrs) do
    Repo.transaction(fn ->
      with {:ok, event_type} <- Events.get_event_type_by_name(event_type_name),
           event_attrs <- Map.put(attrs, "event_type_id", event_type.id),
           {:ok, event} <- Events.create_event(event_attrs) do
        
        # Create all participations
        participations =
          Enum.map(participants, fn %{participant_id: pid, participation_type: ptype} ->
            participation_attrs = %{
              "participant_id" => pid,
              "event_id" => event.id,
              "participation_type" => ptype
            }
            
            {:ok, participation} =
              %Participation{}
              |> Participation.changeset(participation_attrs)
              |> Repo.insert()
            
            participation
          end)
        
        {event, participations}
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end
end
```

**Usage (Internal - for Domain Context implementations):**

**IMPORTANT:** These helpers are for implementing domain contexts, not for direct application use.

```elixir
# ❌ DON'T call these helpers directly from application code
Mosaic.Events.Helpers.create_event_with_participant(...)

# ✅ DO use domain contexts instead:
Mosaic.Shifts.create_shift(employment_id, worker_id, attrs)
Mosaic.Locations.create_location(attrs)
Mosaic.Workers.create_worker(attrs)
```

**Example: Using helper inside a domain context implementation:**

```elixir
# Inside lib/mosaic/schedules.ex (implementation code)
defmodule Mosaic.Schedules do
  alias Mosaic.Events.Helpers

  def create_schedule(location_id, attrs) do
    # This context can use the helper internally
    Helpers.create_event_with_participant(
      "schedule",
      location_id,
      "location_scope",
      %{
        "start_time" => attrs.start_time,
        "end_time" => attrs.end_time,
        "status" => "draft",
        "properties" => %{"timezone" => attrs[:timezone] || "UTC"}
      }
    )
  end
end

# Application code should call:
# Mosaic.Schedules.create_schedule(location_id, attrs)
```

---

## Key Principles

### 0. Two-Layer Architecture

**Application Layer (Your Code):**
- ✅ Always use domain contexts: `Shifts`, `Workers`, `Locations`, `Employments`
- ❌ Never call `Events.create_event()` or `Entities.create_entity()` directly

**Implementation Layer (Domain Context Code):**
- ✅ Domain contexts call `Events.create_event()` internally
- ✅ Use `Events.get_event_type_by_name()` for type lookup
- ✅ Can use `Mosaic.Events.Helpers` for common patterns

### 1. Always Use Event Type Lookup

```elixir
# ✓ CORRECT
with {:ok, event_type} <- Events.get_event_type_by_name("shift") do
  Events.create_event(%{"event_type_id" => event_type.id, ...})
end

# ✗ WRONG - events table has no event_type field
Events.create_event(%{"event_type" => "shift", ...})
```

### 2. Use String Keys in Attrs

```elixir
# ✓ CORRECT
%{"event_type_id" => id, "properties" => %{"location" => "A"}}

# ✗ WRONG - mixing atom and string keys
%{event_type_id: id, "properties" => %{"location" => "A"}}
```

### 3. Query With Proper Joins

```elixir
# ✓ CORRECT
from e in Event,
  join: et in EventType, on: e.event_type_id == et.id,
  where: et.name == "shift"

# ✗ WRONG - events table has no event_type field
from e in Event,
  where: e.event_type == "shift"
```

---

## Benefits

### Configuration-Driven
- Blueprint system enables fast tenant provisioning
- Jurisdiction configs support multi-country deployments
- No code changes needed for new regions

### Maintainable
- Clear separation between code and configuration
- Helper functions ensure consistent patterns
- Centralized configuration management

### Extensible
- Easy to add new blueprints
- Jurisdiction configs are just JSON files
- Event creation helpers work for any event type

## See Also

- [01-events-and-participations.md](01-events-and-participations.md) - Core patterns
- [03-event-types.md](03-event-types.md) - Event type system
- [09-scheduling-model.md](09-scheduling-model.md) - Complex event creation examples
