# Entities

> **Navigation:** [📚 Index](index.md) | [🎯 Start Here](00-start-here.md) | [🔴 Architecture](architecture.md)

## Overview

Entities represent the actors and objects in the system that can participate in events. The entity model uses a polymorphic approach with type-specific properties stored as JSONB.

**IMPORTANT:** The core `Entity` schema (`Mosaic.Entities.Entity`) is completely **domain-agnostic**. It has zero knowledge of specific entity types like workers, locations, or organizations. Domain-specific logic lives in **wrapper contexts** that build on top of the generic Entity schema.

## Database Schema

```sql
CREATE TABLE entities (
  id UUID PRIMARY KEY,
  entity_type VARCHAR(50) NOT NULL,
  properties JSONB DEFAULT '{}',
  inserted_at TIMESTAMP WITH TIME ZONE NOT NULL,
  updated_at TIMESTAMP WITH TIME ZONE NOT NULL
);

CREATE INDEX idx_entities_entity_type ON entities(entity_type);
CREATE INDEX idx_entities_properties ON entities USING GIN(properties);
```

## Core Entity Schema

The `Mosaic.Entities.Entity` schema is intentionally minimal and domain-agnostic:

**Location:** `/mnt/project/entity.ex`

```elixir
defmodule Mosaic.Entities.Entity do
  use Ecto.Schema
  import Ecto.Changeset
  alias Mosaic.Participations.Participation

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "entities" do
    field :entity_type, :string
    field :properties, :map, default: %{}

    has_many :participations, Participation, foreign_key: :participant_id

    timestamps(type: :utc_datetime)
  end

  def changeset(entity, attrs) do
    entity
    |> cast(attrs, [:entity_type, :properties])
    |> validate_required([:entity_type])
    |> validate_format(:entity_type, ~r/^[a-z_]+$/,
      message: "must be lowercase letters and underscores only"
    )
  end
end
```

**Key Points:**
- No hardcoded list of entity types
- Only validates format (lowercase letters and underscores)
- No domain-specific validation
- Properties stored as JSONB for flexibility

## Entity Type Wrapper Pattern

Domain-specific entity types are implemented as **wrapper modules** that add validation and business logic on top of the generic Entity schema.

### Implemented Entity Types

#### Worker (Person)

**Wrapper Module:** `Mosaic.Workers.Worker`
**Context Module:** `Mosaic.Workers`
**Entity Type:** `"person"`
**Locations:** `/mnt/project/worker.ex` (wrapper), `/mnt/project/workers.ex` (context)

Represents people who perform work.

**Properties:**
- `name` (string, required) - Full name
- `email` (string, required) - Contact email
- `phone` (string, optional) - Contact phone number
- `address` (string, optional) - Physical address
- `emergency_contact` (map, optional) - Emergency contact information

**Implementation:**
```elixir
defmodule Mosaic.Workers.Worker do
  @moduledoc """
  Domain-specific module for Worker entities.
  """

  import Ecto.Changeset
  alias Mosaic.Entities.Entity

  def changeset(%Entity{} = entity, attrs) do
    entity
    |> Entity.changeset(Map.put(attrs, "entity_type", "person"))
    |> validate_worker_properties()
  end

  def new(attrs \\ %{}) do
    %Entity{entity_type: "person", properties: %{}}
    |> changeset(attrs)
  end

  defp validate_worker_properties(changeset) do
    case get_field(changeset, :properties) do
      %{} = props ->
        changeset
        |> validate_property_present(props, "name", "Name is required")
        |> validate_property_present(props, "email", "Email is required")
        |> validate_email_format(props)
      _ ->
        add_error(changeset, :properties, "must be a map")
    end
  end

  defp validate_property_present(changeset, props, key, message) do
    value = Map.get(props, key)

    if is_nil(value) or value == "" do
      add_error(changeset, :properties, message, field: key)
    else
      changeset
    end
  end

  defp validate_email_format(changeset, props) do
    email = Map.get(props, "email")

    if email && !String.match?(email, ~r/@/) do
      add_error(changeset, :properties, "Email must be valid", field: "email")
    else
      changeset
    end
  end

  # Helper functions
  def name(%Entity{properties: properties}), do: Map.get(properties, "name")
  def email(%Entity{properties: properties}), do: Map.get(properties, "email")
end
```

**Usage:**
- Participates in employments as "employee"
- Participates in shifts as "worker"
- Participates in work periods and breaks as "worker"

**Context Functions:**
```elixir
defmodule Mosaic.Workers do
  import Ecto.Query
  alias Mosaic.Repo
  alias Mosaic.Entities.Entity
  alias Mosaic.Workers.Worker

  def list_workers do
    from(e in Entity,
      where: e.entity_type == "person",
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  def get_worker!(id) do
    entity = Repo.get!(Entity, id) |> Repo.preload(participations: [:event])

    if entity.entity_type != "person" do
      raise Ecto.NoResultsError, queryable: Entity
    end

    entity
  end

  def create_worker(attrs \\ %{}) do
    %Entity{}
    |> Worker.changeset(attrs)
    |> Repo.insert()
  end

  def update_worker(%Entity{} = worker, attrs) do
    worker
    |> Worker.changeset(attrs)
    |> Repo.update()
  end

  def search_workers(query_string) when is_binary(query_string) do
    search_pattern = "%#{query_string}%"

    from(e in Entity,
      where: e.entity_type == "person",
      where:
        ilike(fragment("?->>'name'", e.properties), ^search_pattern) or
        ilike(fragment("?->>'email'", e.properties), ^search_pattern),
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end
end
```

**Example:**
```elixir
# Creating via context
{:ok, worker} = Mosaic.Workers.create_worker(%{
  "properties" => %{
    "name" => "John Doe",
    "email" => "john@example.com",
    "phone" => "555-0123"
  }
})

# Results in Entity with:
%Entity{
  entity_type: "person",
  properties: %{
    "name" => "John Doe",
    "email" => "john@example.com",
    "phone" => "555-0123"
  }
}
```

#### Location

**Wrapper Module:** `Mosaic.Locations.Location`
**Context Module:** `Mosaic.Locations`
**Entity Type:** `"location"`
**Locations:** `/mnt/project/location.ex` (wrapper), `/mnt/project/locations.ex` (context)

Represents physical work locations.

**Properties:**
- `name` (string, required) - Location name
- `address` (string, required) - Physical address
- `capacity` (integer, optional) - Maximum occupancy
- `facilities` (list, optional) - Available facilities
- `operating_hours` (string, optional) - Operating hours information

**Implementation:**
```elixir
defmodule Mosaic.Locations.Location do
  @moduledoc """
  Domain-specific module for Location entities.
  """

  import Ecto.Changeset
  alias Mosaic.Entities.Entity

  def changeset(%Entity{} = entity, attrs) do
    entity
    |> Entity.changeset(Map.put(attrs, "entity_type", "location"))
    |> validate_location_properties()
  end

  def new(attrs \\ %{}) do
    %Entity{entity_type: "location", properties: %{}}
    |> changeset(attrs)
  end

  defp validate_location_properties(changeset) do
    case get_field(changeset, :properties) do
      %{} = props ->
        changeset
        |> validate_property_present(props, "name", "Name is required")
        |> validate_property_present(props, "address", "Address is required")
        |> validate_capacity(props)
      _ ->
        add_error(changeset, :properties, "must be a map")
    end
  end

  defp validate_property_present(changeset, props, key, message) do
    value = Map.get(props, key)

    if is_nil(value) or value == "" do
      add_error(changeset, :properties, message, field: key)
    else
      changeset
    end
  end

  defp validate_capacity(changeset, props) do
    capacity = Map.get(props, "capacity")

    if capacity && (!is_integer(capacity) || capacity < 0) do
      add_error(changeset, :properties, "Capacity must be a positive integer", field: "capacity")
    else
      changeset
    end
  end

  # Helper functions
  def name(%Entity{properties: properties}), do: Map.get(properties, "name")
  def address(%Entity{properties: properties}), do: Map.get(properties, "address")
end
```

**Usage:**
- Can participate in shifts to indicate work location
- Can have capacity constraints for scheduling

**Context Functions:**
```elixir
defmodule Mosaic.Locations do
  import Ecto.Query
  alias Mosaic.Repo
  alias Mosaic.Entities.Entity
  alias Mosaic.Locations.Location

  def list_locations do
    from(e in Entity,
      where: e.entity_type == "location",
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  def create_location(attrs \\ %{}) do
    %Entity{}
    |> Location.changeset(attrs)
    |> Repo.insert()
  end

  def search_locations(query_string) when is_binary(query_string) do
    search_pattern = "%#{query_string}%"

    from(e in Entity,
      where: e.entity_type == "location",
      where:
        ilike(fragment("?->>'name'", e.properties), ^search_pattern) or
        ilike(fragment("?->>'address'", e.properties), ^search_pattern),
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  def get_locations_with_capacity(min_capacity) when is_integer(min_capacity) do
    from(e in Entity,
      where: e.entity_type == "location",
      where: fragment("(?->>'capacity')::integer >= ?", e.properties, ^min_capacity),
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end
end
```

### Future Entity Types

The wrapper pattern makes it easy to add new entity types without modifying core schemas:

**Organization**
- Entity Type: `"organization"`
- Companies, departments, clients
- Properties: name, tax_id, contact_info
- Participates in employments as "employer"

**Equipment**
- Entity Type: `"equipment"`
- Tools, vehicles, machinery
- Properties: serial_number, type, status
- Participates in events as "equipment"

**Project**
- Entity Type: `"project"`
- Work projects or initiatives
- Properties: name, code, budget, deadline
- Participates in shifts to track project work

## Data Access Patterns

### Finding Entities by Type
```elixir
from e in Entity,
  where: e.entity_type == "person"
```

### Querying Properties
```elixir
from e in Entity,
  where: e.entity_type == "person",
  where: fragment("?->>'name' ILIKE ?", e.properties, ^"%#{name}%")
```

### Getting Entity with Participations
```elixir
from e in Entity,
  where: e.id == ^id,
  preload: [:participations]
```

## Validation Strategy

### Core Schema Validation

The `Entity` schema only validates:
- `entity_type` is required
- `entity_type` follows format: lowercase letters and underscores only

**No domain-specific validation happens in the Entity schema.**

### Wrapper Module Validation

Each wrapper module implements domain-specific validation:

```elixir
defmodule Mosaic.Workers.Worker do
  import Ecto.Changeset
  alias Mosaic.Entities.Entity

  def changeset(%Entity{} = entity, attrs) do
    entity
    |> Entity.changeset(Map.put(attrs, "entity_type", "person"))
    |> validate_worker_properties()
  end

  defp validate_worker_properties(changeset) do
    case get_field(changeset, :properties) do
      %{} = props ->
        changeset
        |> validate_property_present(props, "name", "Name is required")
        |> validate_property_present(props, "email", "Email is required")
      _ ->
        add_error(changeset, :properties, "must be a map")
    end
  end

  defp validate_property_present(changeset, props, key, message) do
    value = Map.get(props, key)
    if is_nil(value) or value == "", do: add_error(changeset, :properties, message, field: key), else: changeset
  end
end
```

**Key Points:**
- Wrapper changesets call `Entity.changeset/2` first (core validation)
- Then add domain-specific property validation
- Each wrapper enforces its own required fields
- Core Entity schema remains unaware of domain requirements
- **IMPORTANT**: Use string keys (e.g., `"entity_type"`) not atom keys to avoid Ecto mixed key errors

## Relationship to Events

Entities participate in events through the `participations` table:

```
Entity (Worker) --< Participation >-- Event (Employment)
Entity (Worker) --< Participation >-- Event (Shift)
Entity (Worker) --< Participation >-- Event (Work Period)
```

A single entity can have multiple participations across different events, each with its own:
- Role
- Temporal bounds
- Participation-specific properties

## Extension Points

### Adding New Entity Types

To add a new entity type (e.g., Organizations), follow these steps:

**1. Create Wrapper Module** (`lib/mosaic/organizations/organization.ex`):
```elixir
defmodule Mosaic.Organizations.Organization do
  import Ecto.Changeset
  alias Mosaic.Entities.Entity

  def changeset(%Entity{} = entity, attrs) do
    entity
    |> Entity.changeset(Map.put(attrs, "entity_type", "organization"))
    |> validate_organization_properties()
  end

  defp validate_organization_properties(changeset) do
    case get_field(changeset, :properties) do
      %{} = props ->
        changeset
        |> validate_property_present(props, "name", "Name is required")
        |> validate_property_present(props, "tax_id", "Tax ID is required")
      _ ->
        add_error(changeset, :properties, "must be a map")
    end
  end

  def name(%Entity{properties: properties}), do: Map.get(properties, "name")
  def tax_id(%Entity{properties: properties}), do: Map.get(properties, "tax_id")
end
```

**2. Create Context Module** (`lib/mosaic/organizations.ex`):
```elixir
defmodule Mosaic.Organizations do
  import Ecto.Query
  alias Mosaic.Repo
  alias Mosaic.Entities.Entity
  alias Mosaic.Organizations.Organization

  def list_organizations do
    from(e in Entity,
      where: e.entity_type == "organization",
      order_by: [asc: fragment("?->>'name'", e.properties)]
    )
    |> Repo.all()
  end

  def create_organization(attrs \\ %{}) do
    %Entity{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end
end
```

**3. Create LiveView Interface** for CRUD operations (optional)

**4. No Changes to Core Schemas** - The Entity schema remains completely unaware of organizations

**Key Points:**
- No migrations needed to add new entity types
- No changes to core Entity schema
- Domain logic isolated in wrapper modules
- Type-safe interfaces through context modules

## Benefits

### Domain-Agnostic Core
- Core schemas have zero domain knowledge
- Easy to maintain - core logic never changes
- Clear separation of concerns
- Testable independently

### Flexibility
- No schema migrations for new entity types
- Type-specific properties via JSONB
- Extensible without modification
- Properties indexed with GIN for efficient querying

### Consistency
- Single entities table maintains referential integrity
- Uniform participation mechanism
- Standardized patterns
- Centralized storage

### Type Safety
- Wrapper contexts provide type-specific interfaces
- Domain validation at wrapper layer
- Context functions enforce correct types
- Compile-time safety

### Scalability
- Support diverse entity types without database changes
- Properties grow independently per type
- Cross-domain queries remain efficient
- Parallel development possible

### Database Integrity
- Foreign key constraints work properly
- Cross-type queries possible
- Efficient joins
- Single source of truth

## Architecture Summary

```
┌─────────────────────────────────────────────────────┐
│              APPLICATION LAYER                       │
│  (LiveViews, Controllers, Forms)                    │
└────────────────┬────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────────────┐
│              DOMAIN LAYER                            │
│  (Business Logic & Type-Specific Validation)        │
├─────────────────────────────────────────────────────┤
│  Wrapper Modules:                                   │
│  • Workers.Worker      (validates person entities)  │
│  • Locations.Location  (validates location entities)│
│                                                      │
│  Context Modules:                                   │
│  • Mosaic.Workers      (business operations)        │
│  • Mosaic.Locations    (business operations)        │
└────────────────┬────────────────────────────────────┘
                 ↓
┌─────────────────────────────────────────────────────┐
│              CORE LAYER                              │
│  (Domain-Agnostic Storage)                          │
├─────────────────────────────────────────────────────┤
│  Mosaic.Entities.Entity                             │
│  • entity_type: string                              │
│  • properties: jsonb                                │
│  • NO domain knowledge                              │
└─────────────────────────────────────────────────────┘
```

## See Also

- [01-events-and-participations.md](01-events-and-participations.md) - How entities participate in events
- [03-event-types.md](03-event-types.md) - Event type wrapper pattern (parallel to entity wrappers)
- [08-properties-pattern.md](08-properties-pattern.md) - How JSONB properties enable flexibility
