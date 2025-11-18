# Entities

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

```elixir
defmodule Mosaic.Entities.Entity do
  use Ecto.Schema
  import Ecto.Changeset

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

Represents people who perform work.

**Properties:**
- `name` (string, required) - Full name
- `email` (string, required) - Contact email
- `phone` (string, optional) - Contact phone number

**Implementation:**
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
        |> validate_email_format(props)
      _ ->
        add_error(changeset, :properties, "must be a map")
    end
  end
end
```

**Usage:**
- Participates in employments as "employee"
- Participates in shifts as "worker"
- Participates in work periods and breaks as "worker"

**Context Functions:**
- `Mosaic.Workers.list_workers/0`
- `Mosaic.Workers.get_worker!/1`
- `Mosaic.Workers.create_worker/1`
- `Mosaic.Workers.update_worker/2`
- `Mosaic.Workers.delete_worker/1`
- `Mosaic.Workers.search_workers/1`

**Example:**
```elixir
# Creating via context
{:ok, worker} = Mosaic.Workers.create_worker(%{
  properties: %{
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
  import Ecto.Changeset
  alias Mosaic.Entities.Entity

  def changeset(%Entity{} = entity, attrs) do
    entity
    |> Entity.changeset(Map.put(attrs, "entity_type", "location"))
    |> validate_location_properties()
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
end
```

**Usage:**
- Can participate in shifts to indicate work location
- Can have capacity constraints for scheduling

**Context Functions:**
- `Mosaic.Locations.list_locations/0`
- `Mosaic.Locations.get_location!/1`
- `Mosaic.Locations.create_location/1`
- `Mosaic.Locations.update_location/2`
- `Mosaic.Locations.delete_location/1`
- `Mosaic.Locations.search_locations/1`
- `Mosaic.Locations.get_locations_with_capacity/1`

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
  where: e.entity_type == "worker"
```

### Querying Properties
```elixir
from e in Entity,
  where: e.entity_type == "worker",
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
        |> validate_email_format(props)
      _ ->
        add_error(changeset, :properties, "must be a map")
    end
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

## Context Modules

Each entity type wrapper has a corresponding context module that provides business operations:

### Workers Context

**Module:** `Mosaic.Workers`
**Implementation:** `lib/mosaic/workers.ex`

The Workers context manages worker (person) entities:

**Functions:**
- `list_workers/0` - Get all workers
- `get_worker!/1` - Get worker by ID (raises if not found or wrong type)
- `create_worker/1` - Create new worker with validation
- `update_worker/2` - Update worker properties
- `delete_worker/1` - Delete worker
- `change_worker/2` - Get changeset for forms
- `search_workers/1` - Search by name or email
- `worker_exists_with_email?/1` - Check for duplicate email

**Example Usage:**
```elixir
# List all workers
workers = Mosaic.Workers.list_workers()

# Create a worker
{:ok, worker} = Mosaic.Workers.create_worker(%{
  properties: %{
    "name" => "Jane Smith",
    "email" => "jane@example.com",
    "phone" => "555-9876"
  }
})

# Search for workers
results = Mosaic.Workers.search_workers("jane")
```

### Locations Context

**Module:** `Mosaic.Locations`
**Implementation:** `lib/mosaic/locations.ex`

The Locations context manages location entities:

**Functions:**
- `list_locations/0` - Get all locations
- `get_location!/1` - Get location by ID (raises if not found or wrong type)
- `create_location/1` - Create new location with validation
- `update_location/2` - Update location properties
- `delete_location/1` - Delete location
- `change_location/2` - Get changeset for forms
- `search_locations/1` - Search by name or address
- `get_locations_by_ids/1` - Batch fetch by IDs
- `get_locations_with_capacity/1` - Find locations with minimum capacity

**Example Usage:**
```elixir
# List all locations
locations = Mosaic.Locations.list_locations()

# Create a location
{:ok, location} = Mosaic.Locations.create_location(%{
  properties: %{
    "name" => "Downtown Office",
    "address" => "123 Main St",
    "capacity" => 50
  }
})

# Find locations with capacity for 25+ people
large_locations = Mosaic.Locations.get_locations_with_capacity(25)
```

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
        # Add more validations as needed
      _ ->
        add_error(changeset, :properties, "must be a map")
    end
  end

  # Helper functions
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

  def get_organization!(id) do
    entity = Repo.get!(Entity, id)
    if entity.entity_type != "organization" do
      raise Ecto.NoResultsError, queryable: Entity
    end
    entity
  end

  def create_organization(attrs \\ %{}) do
    %Entity{}
    |> Organization.changeset(attrs)
    |> Repo.insert()
  end

  def update_organization(%Entity{} = organization, attrs) do
    organization
    |> Organization.changeset(attrs)
    |> Repo.update()
  end

  def delete_organization(%Entity{} = organization) do
    Repo.delete(organization)
  end

  def change_organization(%Entity{} = organization, attrs \\ %{}) do
    Organization.changeset(organization, attrs)
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
- **Core schemas have zero domain knowledge** - Entity schema doesn't know about workers, locations, etc.
- **Easy to maintain** - Core logic never changes when adding new domains
- **Clear separation** - Business logic lives in wrappers, not core schemas
- **Testable** - Core and domain layers can be tested independently

### Flexibility
- **No schema migrations** for new entity types
- **Type-specific properties** via JSONB
- **Extensible without modification** - Add new types by creating wrappers
- **Properties indexed** with GIN for efficient querying

### Consistency
- **Single entities table** maintains referential integrity
- **Uniform participation** mechanism across all entity types
- **Standardized patterns** - All entity types follow same wrapper pattern
- **Centralized storage** - All entities in one table with consistent schema

### Type Safety
- **Wrapper contexts provide type-specific interfaces**
- **Domain validation** happens at wrapper layer
- **Context functions** enforce correct entity types
- **Compile-time safety** - Wrong entity type usage caught early

### Scalability
- **Support diverse entity types** without database changes
- **Properties grow independently** per type
- **Cross-domain queries remain efficient** (all in one table)
- **Parallel development** - Teams can add entity types independently

### Database Integrity
- **Foreign key constraints work** - participations.participant_id references entities.id
- **Cross-type queries possible** - "All events for any participant"
- **Efficient joins** - No need for polymorphic associations
- **Single source of truth** - One entities table, not separate tables per type

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

- [01-events-and-participations.md](01-events-and-participations.md) - How entities participate in events and the domain-agnostic architecture
- [03-event-types.md](03-event-types.md) - Event type wrapper pattern (parallel to entity wrappers)
- [08-properties-pattern.md](08-properties-pattern.md) - How JSONB properties enable flexibility
