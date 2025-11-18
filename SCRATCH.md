I have a newly generated Phoenix LiveView application and I want to implement a flexible event-based workforce management system. This system will handle scheduling, payroll, and HR domains using a unified temporal model.

**Core Data Model:**

Implement the following database schema using Ecto migrations and schemas:

**1. ENTITIES table:**
- Represents people, organizations, locations, and resources
- Fields: id (UUID), entity_type (string), properties (JSONB map), inserted_at, updated_at
- Entity types: "person", "organization", "location", "resource"

**2. EVENT_TYPES table:**
- Defines the types of events in the system
- Fields: id (UUID), name (string, unique), category (string), can_nest (boolean), can_have_children (boolean), requires_participation (boolean), schema (JSONB map for validation rules), rules (JSONB map for business logic), is_active (boolean), inserted_at, updated_at
- Seed with initial types: "employment", "shift", "work_period", "break"

**3. EVENTS table:**
- Represents temporal occurrences (shifts, contracts, breaks, etc)
- Fields: id (UUID), event_type_id (references event_types), parent_id (self-reference for hierarchy), start_time (timestamptz, required), end_time (timestamptz, nullable), status (string), properties (JSONB map), inserted_at, updated_at
- Indexes: (start_time, end_time), (parent_id), (event_type_id, start_time), GIN index on properties
- Add constraint to prevent invalid parent relationships based on event_type rules

**4. PARTICIPATIONS table:**
- Links entities to events with a role
- Fields: id (UUID), participant_id (references entities), event_id (references events), participation_type (string), role (string, nullable), start_time (timestamptz, nullable - can differ from event times), end_time (timestamptz, nullable), properties (JSONB map), inserted_at, updated_at
- Unique constraint on (participant_id, event_id, participation_type)
- Indexes: (participant_id, event_id), (event_id)
- Participation types: "employee", "worker", "location", "resource", "manager", etc

**Implementation Requirements:**

**Phase 1 - Database Setup:**
1. Create all Ecto migrations with proper indexes and constraints
2. Create Ecto schemas with:
   - Proper associations (has_many, belongs_to)
   - Virtual fields for computed values
   - Changesets with validation
3. Add seeds file to populate event_types with the initial types mentioned above

**Phase 2 - Context Layer:**
Create contexts following Phoenix conventions:

1. **Workforce.Entities context:**
   - `list_workers/0` - list all entities where entity_type = "person"
   - `get_entity!/1`
   - `create_worker/1` - creates entity with type "person" and properties like name, email, phone
   - `update_entity/2`
   - `delete_entity/1`

2. **Workforce.Events context:**
   - `list_events/1` with filtering and preloading
   - `get_event!/1` with option to preload children and participations
   - `create_employment_period/2` - creates employment event and participation for a worker
   - `create_shift/2` - creates shift event, links to parent employment, adds worker participation
   - `update_event/2`
   - `delete_event/1`
   - `get_event_hierarchy/1` - returns full tree of parent and children
   - `list_employments_for_worker/1` - all employment periods for a worker
   - `list_shifts_for_employment/1` - all shifts under an employment period

3. **Workforce.Participations context:**
   - `add_participation/3` - links entity to event
   - `remove_participation/1`

**Phase 3 - LiveView UI:**

Create three main interfaces focused on creating workers, employments, and shifts:

**1. WorkersLive.Index** (`/workers`):
- Page header: "Workers"
- Table showing all workers with columns:
  - Name
  - Email (from properties)
  - Phone (from properties)
  - Number of active employments
  - Actions (View, Edit, Delete)
- Prominent "New Worker" button at top right
- Click on worker row navigates to WorkersLive.Show

**WorkersLive.FormComponent** (modal):
- Form fields:
  - Name (required, text input)
  - Email (required, email input)
  - Phone (text input)
  - Additional properties (textarea for JSON, optional)
- Submit creates entity with entity_type "person"
- Cancel button closes modal
- Show validation errors inline

**2. WorkersLive.Show** (`/workers/:id`):
- Breadcrumb: Workers > [Worker Name]
- Worker details card showing name, email, phone
- "Edit Worker" button
- Section: "Employment Periods"
  - List all employment periods for this worker
  - Each employment shows: start date, end date, status, role
  - "New Employment Period" button
  - Click employment navigates to EmploymentLive.Show
- Section: "All Shifts" (across all employments)
  - Upcoming shifts list with date, time, location
  - Filter by date range

**EmploymentFormComponent** (modal, opened from WorkersLive.Show):
- Form fields:
  - Start Date (required, date picker)
  - End Date (optional, date picker)
  - Role (text input, stored in participation properties)
  - Contract Type (text input, stored in event properties)
  - Salary (number input, stored in event properties)
  - Status (select: draft, active, ended)
- On submit:
  - Creates event with event_type "employment"
  - Creates participation linking worker to employment as "employee"
  - Redirects back to worker show page
- Validation:
  - Start date required
  - End date must be after start date if provided
  - Worker cannot have overlapping active employment periods

**3. EmploymentLive.Show** (`/employments/:id`):
- Breadcrumb: Workers > [Worker Name] > Employment Period
- Employment details card:
  - Worker name (link back to worker)
  - Start date, end date
  - Status
  - Role, contract type, salary
  - "Edit Employment" button
- Section: "Shifts"
  - Calendar view or list view toggle
  - List all shifts under this employment
  - Each shift shows: date, start time, end time, location, status
  - Breakdown showing work periods and breaks
  - "New Shift" button
  - Click shift navigates to ShiftLive.Show

**ShiftFormComponent** (modal, opened from EmploymentLive.Show):
- Form fields:
  - Date (required, date picker)
  - Start Time (required, time picker)
  - End Time (required, time picker)
  - Location (select dropdown or text input)
  - Department (text input, stored in properties)
  - Notes (textarea, stored in properties)
  - Auto-generate work periods and break (checkbox, defaults to true)
    - If checked, creates default work_period and break events
    - Break after 4 hours, 30 minutes duration
- On submit:
  - Creates event with event_type "shift", parent_id = employment_id
  - Creates participation linking worker to shift as "worker"
  - If auto-generate checked:
    - Creates work_period before break
    - Creates break event
    - Creates work_period after break
  - Redirects back to employment show page
- Validation:
  - Start time required
  - End time must be after start time
  - Shift must be within employment period dates
  - Worker cannot have overlapping shifts

**4. ShiftLive.Show** (`/shifts/:id`):
- Breadcrumb: Workers > [Worker Name] > Employment > Shift
- Shift details card:
  - Worker name (link)
  - Employment period (link)
  - Date, start time, end time
  - Duration (calculated)
  - Location, department
  - Status
  - "Edit Shift" button
- Section: "Timeline"
  - Visual timeline showing work_periods and breaks
  - Each work_period shows duration in hours
  - Break shows duration and whether paid/unpaid
  - Buttons to:
    - "Add Break"
    - "Add Work Period"
    - Edit/delete individual periods
- Section: "Summary"
  - Total worked hours (sum of work_periods)
  - Break time (sum of breaks)
  - Net working time (worked hours - unpaid breaks)

**Navigation:**
- Top navigation bar with links:
  - Workers (links to WorkersLive.Index)
  - Dashboard (future)
  - Payroll (future)

**Phase 4 - Helper Functions:**

Add these utility functions to Workforce.Events:

1. `auto_generate_shift_periods/1` - takes shift event, calculates work periods and break based on shift duration
2. `calculate_shift_hours/1` - sums work_period durations for a shift
3. `validate_shift_in_employment/2` - checks if shift dates fall within employment period
4. `check_shift_overlap/2` - prevents worker from having overlapping shifts

**Technical Specifications:**
- Use Phoenix 1.7+ conventions
- Use Ecto 3.x with PostgreSQL
- Use Tailwind CSS for styling
- Use Phoenix.Component for reusable components
- Use Phoenix.LiveView.JS for client-side interactions
- All forms should be in modal overlays using live_component
- Implement proper error handling and flash messages
- Use PubSub to broadcast updates (e.g., when shift created, update employment show page)
- Add basic tests for context functions

**Expected File Structure:**
```
lib/
  my_app/
    workforce/
      entity.ex
      event.ex
      event_type.ex
      participation.ex
      entities.ex (context)
      events.ex (context)
      participations.ex (context)
  my_app_web/
    live/
      workers_live/
        index.ex
        show.ex
        form_component.ex
      employment_live/
        show.ex
        form_component.ex
      shift_live/
        show.ex
        form_component.ex
    components/
      core_components.ex (extend with custom components)
priv/
  repo/
    migrations/
      [timestamp]_create_entities.exs
      [timestamp]_create_event_types.exs
      [timestamp]_create_events.exs
      [timestamp]_create_participations.exs
    seeds.exs
```

**UI/UX Specifications:**
- Use Tailwind default color palette
- Cards should have subtle shadows and rounded corners
- Tables should have hover states
- Buttons: primary (indigo), secondary (gray), danger (red)
- Modal overlays should dim background
- Forms should have clear labels and helper text
- Date/time pickers should be user-friendly (consider using a JS library)
- Show loading states during form submission
- Flash messages for success/error at top of page
- Responsive design (mobile-friendly tables collapse to cards)

**Validation Rules:**
- Workers: name required, email format validation
- Employments: start_date required, end_date > start_date, no overlapping active employments
- Shifts: times required, must be within employment dates, no overlapping shifts, end_time > start_time
- Auto-generated breaks: only if shift is 4+ hours

**User Flow Example:**
1. User navigates to /workers
2. Clicks "New Worker" button
3. Modal opens, fills in name, email, phone
4. Submits form, worker created, modal closes
5. Clicks on newly created worker row
6. Navigates to /workers/:id
7. Clicks "New Employment Period"
8. Modal opens, fills in start date, role, salary
9. Submits form, employment created with participation
10. Clicks on employment period
11. Navigates to /employments/:id
12. Clicks "New Shift"
13. Modal opens, fills in date, times, checks auto-generate
14. Submits form, shift created with work_periods and break
15. Clicks on shift
16. Navigates to /shifts/:id, sees timeline breakdown

Please implement this system step by step, starting with migrations and schemas, then contexts, then LiveViews. After each phase, show me the generated code and confirm before proceeding to the next phase.
