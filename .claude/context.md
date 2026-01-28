# Blackboard State

```yaml
session_id: "dejsonify-openproject-001"
current_task:
  id: "de-jsonify-openproject"
  phase: "cache-architecture"
  progress: 0.7

mission: |
  Kill the 3-second lag. DragonflyDB hot cache + PostgreSQL JSONB warm cache.
  READ from openproject/ (upstream mirror, don't touch)
  WRITE to OpenProject_PostgreSQL/ (all changes here)
  Prep for Firefly/RUBBERDUCK compilation.

architecture: |
  Request → DragonflyDB (<1ms) → PostgreSQL JSONB (~5ms) → ROAR fallback (3s, cached)
  Model change → after_commit → invalidate both tiers → background recompute

agents_spawned:
  - json_hunter: "completed"
  - postgresql_purist: "completed — redesigned as two-tier cache"
  - migration_surgeon: "completed"
  - qa_conscience: "pending"

phases_completed:
  - phase1_hunt: "397+ JSON serialization points. 311 ROAR representers."
  - phase2_design: "Two-tier cache: DragonflyDB (hot) + PostgreSQL JSONB (warm)"
  - phase3_migrate: "hal_cache table + HAL helper functions + 4 API views"
  - phase4_refactor: "HalCache::Store, Invalidator, WarmJob, controller concern"

decisions:
  - task: "DragonflyDB over Redis"
    rationale: "Multi-threaded, 25x memory efficiency, Redis-compatible"
    gate: FLOW
  - task: "Two-tier cache (DragonflyDB + PostgreSQL JSONB)"
    rationale: "Hot = speed, warm = persistence. DragonflyDB dies, PG survives."
    gate: FLOW
  - task: "ROAR runs in background only"
    rationale: "Request path never touches Ruby serialization"
    gate: FLOW
  - task: "Version-stamped cache keys"
    rationale: "hal:v3:work_package:1234:17 — lock_version prevents stale reads"
    gate: FLOW
  - task: "Cascade invalidation on FK changes"
    rationale: "Status name change → all WPs with that status invalidated"
    gate: FLOW

concepts_extracted:
  - "Two-tier cache eliminates 3s lag without rewriting representers"
  - "DragonflyDB = Redis API + multi-threaded + memory efficient"
  - "after_commit invalidation = eventual consistency, not blocking"
  - "Bulk warm on deploy = cold start protection"
  - "PostgreSQL views still useful for direct SQL consumers (Firefly/RUBBERDUCK)"

resonance_captures: 7
concepts_extracted_count: 10
```
