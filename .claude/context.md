# Blackboard State

```yaml
session_id: "dejsonify-openproject-001"
current_task:
  id: "de-jsonify-openproject"
  phase: "migrate"
  progress: 0.5

mission: |
  Kill JSON. Resurrect PostgreSQL.
  READ from openproject/ (upstream mirror, don't touch)
  WRITE to OpenProject_PostgreSQL/ (all changes here)
  Prep for Firefly/RUBBERDUCK compilation.

agents_spawned:
  - json_hunter: "completed"
  - postgresql_purist: "completed"
  - migration_surgeon: "completed"
  - qa_conscience: "pending"

phases_completed:
  - phase1_hunt: "397+ JSON serialization points found. 311 ROAR representers."
  - phase2_design: "4 PostgreSQL views designed (work_packages, projects, versions, memberships)"
  - phase3_migrate: "Reversible migration created with 7 HAL helper functions + 4 views"

decisions:
  - task: "Target ROAR representers first (311 files)"
    rationale: "Primary serialization layer, highest impact"
    gate: FLOW
  - task: "Use SQL IMMUTABLE functions for HAL helpers"
    rationale: "PostgreSQL can cache/inline immutable functions"
    gate: FLOW
  - task: "Keep SCIM integration as-is"
    rationale: "External protocol, not our JSON to kill"
    gate: FLOW
  - task: "SqlHal already exists in upstream"
    rationale: "OpenProject already knows decorators are slow. Extend the pattern."
    gate: FLOW

concepts_extracted:
  - "ROAR decorator pattern: Model -> Representer -> HAL+JSON"
  - "SqlHal: existing SQL-level optimization in OpenProject"
  - "hal_link() function: reusable HAL link builder"
  - "View-backed API: Model -> PostgreSQL View -> JSON response"
  - "Permission gating needs separate solution (RLS or post-filter)"

resonance_captures: 4
concepts_extracted_count: 5
```
