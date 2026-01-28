# De-JSONification Architecture: Kill the 3-Second Lag

## The Problem

```
Request → ROAR Representer → 3 SECONDS → Response
          ├── Ruby object allocation
          ├── N+1 association loading
          ├── HAL link computation
          ├── Permission checks per link
          └── JSON string serialization
```

Every API call rebuilds the entire HAL+JSON tree from scratch in Ruby.

## The Solution: Two-Tier Pre-computed Cache

```
                    ┌─────────────────────┐
  Request ─────────>│  DragonflyDB (hot)  │──> Response (<1ms)
                    │  TTL: 5 min         │
                    └────────┬────────────┘
                             │ miss
                    ┌────────▼────────────┐
                    │  PostgreSQL JSONB    │──> Response (~5ms)
                    │  (warm, persistent)  │
                    └────────┬────────────┘
                             │ miss (cold start only)
                    ┌────────▼────────────┐
                    │  ROAR Representer    │──> Response (3s, then cache)
                    │  (compute + store)   │
                    └─────────────────────┘
```

### Why Two Tiers?

| Tier | Store | Speed | Survives | Use |
|------|-------|-------|----------|-----|
| HOT | DragonflyDB | <1ms | Restart: no | Read-heavy endpoints |
| WARM | PostgreSQL JSONB | ~5ms | Everything | Persistent cache, audit trail |
| COLD | ROAR Representer | ~3s | N/A | Fallback + cache warming |

### Why DragonflyDB, Not Redis?

- Drop-in Redis compatible (same `redis` gem works)
- Multi-threaded (Redis is single-threaded)
- 25x memory efficiency on large datasets
- Handles the HAL+JSON blobs (avg 2-8KB each) without sweat
- Supports HASH type for partial field access

## Cache Key Design

```
hal:v3:{resource_type}:{id}:{version}

Examples:
  hal:v3:work_package:1234:17     # lock_version = 17
  hal:v3:project:42:1706388000    # updated_at epoch
  hal:v3:version:8:1706388000
  hal:v3:membership:99:1706388000
```

Version suffix ensures stale reads are impossible without
explicit invalidation.

## Invalidation Strategy

```
Model save/destroy
  │
  ├──> after_commit callback
  │      │
  │      ├──> DELETE from DragonflyDB (hot)
  │      ├──> UPDATE PostgreSQL JSONB (warm) → mark stale
  │      └──> Enqueue HalCacheWarmJob (background recompute)
  │
  └──> Associated models (cascade)
         │
         ├──> WorkPackage changes → invalidate parent, children, project
         ├──> Status/Type/Priority changes → invalidate all WPs with that FK
         └──> Member changes → invalidate project membership list
```

## Write Path (Background)

```ruby
# After model save:
HalCacheWarmJob.perform_async(resource_type, resource_id)

# Job:
# 1. Load model + associations (single query with includes)
# 2. Run ROAR representer ONCE
# 3. Store JSON string in DragonflyDB (SET with TTL)
# 4. Store JSONB in PostgreSQL hal_cache table (UPSERT)
```

## Read Path (Request)

```ruby
# Controller:
def show
  json = HalCache.fetch("work_package", params[:id])
  render json: json, status: :ok
end

# HalCache.fetch:
# 1. Try DragonflyDB GET → return if hit
# 2. Try PostgreSQL hal_cache → return if fresh
# 3. Fallback: compute via ROAR, store, return
```

## Data Flow

```
┌──────────┐    write    ┌──────────────┐   async   ┌──────────────┐
│  Rails   │────────────>│  Model Save  │──────────>│ HalCacheWarm │
│  App     │             │  (callback)  │           │   (Sidekiq)  │
└──────────┘             └──────────────┘           └──────┬───────┘
     │                                                      │
     │ read                                          ┌──────▼───────┐
     │                                               │ ROAR compute │
     ▼                                               │ (once, bg)   │
┌──────────┐  <1ms  ┌──────────────┐                └──────┬───────┘
│ Response │<───────│  DragonflyDB │<───────────────────────┤ SET
└──────────┘        └──────────────┘                        │
     ▲                                                      │
     │  ~5ms  ┌──────────────┐                              │
     └───────│  PG JSONB    │<──────────────────────────────┘ UPSERT
              └──────────────┘
```
