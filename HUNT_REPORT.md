# Phase 1: HUNT Report - JSON Serialization Patterns

## Executive Summary

OpenProject's JSON layer is dominated by **ROAR Representers** (311 files).
This is not typical Rails `as_json` bloat — it's a full decorator architecture
using HAL+JSON hypermedia format.

## Kill Targets

| Pattern | Count | Priority | Strategy |
|---------|-------|----------|----------|
| ROAR Representers | 311 | CRITICAL | PostgreSQL views + `row_to_json` |
| `to_json` calls | 25 | HIGH | Eliminate via view-backed responses |
| `render json:` | 20 | HIGH | Point to views instead of hashes |
| `JSON.parse/dump` | 14 | MEDIUM | PostgreSQL `jsonb` functions |
| `to_hash` (JSON prep) | 10 | MEDIUM | Eliminate intermediate step |
| `from_json` / SCIM | 10 | LOW | Keep (external protocol) |
| `as_json` | 6 | LOW | Replace with scopes |
| Serializer classes | 1 | LOW | Remove |

**Total serialization points: 397+**

## Architecture: What We're Replacing

```
CURRENT (ROAR Decorator Pattern):
  Model → Representer (Ruby object) → HAL+JSON → Response

  - 311 representer files in lib/api/v3/
  - Each defines: links, properties, collections
  - Decorator wraps model, adds hypermedia
  - Heavy Ruby object allocation per request

TARGET (PostgreSQL View Pattern):
  PostgreSQL View → row_to_json / jsonb_build_object → Response

  - Views encode the same shape as representers
  - No Ruby object intermediary
  - Database does the serialization
  - HAL links generated via pg functions
```

## Top 20 Representer Targets (by impact)

1. `work_packages/work_package_representer.rb` — Core entity, highest traffic
2. `work_packages/work_package_payload_representer.rb` — PATCH/POST payloads
3. `projects/project_representer.rb` — Project listing/detail
4. `queries/query_representer.rb` — Saved filters
5. `memberships/membership_representer.rb` — Team members
6. `activities/activity_representer.rb` — Changelog
7. `attachments/attachment_representer.rb` — Files
8. `notifications/notification_representer.rb` — User notifications
9. `relations/relation_representer.rb` — WP relationships
10. `versions/version_representer.rb` — Milestones
11. `custom_fields/custom_field_representer.rb` — Dynamic fields
12. `principals/principal_representer.rb` — Users/groups
13. `time_entries/time_entry_representer.rb` — Time tracking
14. `categories/category_representer.rb` — WP categories
15. `root_representer.rb` — API entrypoint
16. `storages/file_link_representer.rb` — File storage
17. `costs/cost_entry_representer.rb` — Cost tracking
18. `gitlab_integration/gitlab_merge_request_representer.rb` — GitLab
19. `placeholder_users/placeholder_user_representer.rb` — Bot users
20. `work_packages/work_package_schema_representer.rb` — Schema definition

## ROAR Base Decorators (26 in lib/api/decorators/)

These define the patterns all representers inherit:
- `Single` — single resource
- `Collection` — generic collection wrapper
- `OffsetPaginatedCollection` — paginated
- `SqlCollectionRepresenter` — SQL-optimized (already close to views)
- `SqlHal` — SQL HAL format (CLOSEST to our target)
- `SchemaRepresenter` — JSON schema for properties
- `CreateForm` / `UpdateForm` — form validation schemas
- `LinkedResource` — HAL link handling
- `SelfLink` — self-referential links

## Key Insight: SqlHal Already Exists

OpenProject already has `SqlHal` and `SqlCollectionRepresenter` decorators
that generate SQL-optimized responses. This means:

1. They already know the decorator pattern is slow
2. There's precedent for SQL-level JSON generation
3. Our PostgreSQL views extend this existing pattern to its logical conclusion

## Modules with JSON (secondary targets)

- Costs: 13 representers
- Storages: 8 representers
- BIM: 5+ representers
- GitLab Integration: 6+ representers
- Boards: board widget representers

## Non-Targets (keep as-is)

- SCIM integration (`from_scim!`) — external protocol, keep
- OAuth metadata controller — spec-mandated JSON
- JSON validator — validation logic, not serialization
- `IndifferentHashSerializer` — ActiveRecord column type, orthogonal

## Next: Phase 2 DESIGN

Priority order for PostgreSQL view design:
1. Work Packages (highest traffic, most complex)
2. Projects (second most accessed)
3. Memberships (team operations)
4. Queries (filter/view persistence)
5. Everything else by module
