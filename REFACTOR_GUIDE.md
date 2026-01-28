# Phase 4: Refactoring Guide — Serializer Removal

## The Pattern

Every API v3 endpoint currently does this:

```ruby
# BEFORE: app/controllers/api/v3/work_packages_controller.rb
def show
  work_package = WorkPackage.find(params[:id])
  representer = API::V3::WorkPackages::WorkPackageRepresenter.new(
    work_package, current_user: current_user, embed_links: true
  )
  render json: representer.to_json
end
```

Replace with:

```ruby
# AFTER: Direct PostgreSQL view query
def show
  result = ActiveRecord::Base.connection.execute(
    "SELECT hal_json FROM api_v3_work_packages WHERE id = #{ActiveRecord::Base.sanitize_sql(params[:id])}"
  ).first
  render json: result['hal_json']
end
```

Or with ActiveRecord:

```ruby
# AFTER: ActiveRecord model backed by view
class API::V3::WorkPackageView < ActiveRecord::Base
  self.table_name = 'api_v3_work_packages'
  self.primary_key = 'id'
end

def show
  wp = API::V3::WorkPackageView.find(params[:id])
  render json: wp.hal_json
end
```

## Conversion Checklist

For each representer being replaced:

- [ ] Verify the PostgreSQL view covers all properties
- [ ] Compare HAL link structure (self, update, delete, associations)
- [ ] Check conditional links (permission-gated actions)
- [ ] Verify collection endpoints (pagination via LIMIT/OFFSET)
- [ ] Test custom field injection (dynamic properties)
- [ ] Validate embedded resources match

## Controller-by-Controller Plan

### 1. Work Packages (highest impact)

| Endpoint | Representer | View |
|----------|-------------|------|
| GET /api/v3/work_packages/:id | WorkPackageRepresenter | api_v3_work_packages |
| GET /api/v3/work_packages | WorkPackageCollectionRepresenter | api_v3_work_packages + pagination |
| GET /api/v3/projects/:id/work_packages | WorkPackageCollectionRepresenter | api_v3_work_packages WHERE project_id = ? |

### 2. Projects

| Endpoint | Representer | View |
|----------|-------------|------|
| GET /api/v3/projects/:id | ProjectRepresenter | api_v3_projects |
| GET /api/v3/projects | ProjectCollectionRepresenter | api_v3_projects + pagination |

### 3. Versions

| Endpoint | Representer | View |
|----------|-------------|------|
| GET /api/v3/versions/:id | VersionRepresenter | api_v3_versions |
| GET /api/v3/projects/:id/versions | VersionCollectionRepresenter | api_v3_versions WHERE project_id = ? |

### 4. Memberships

| Endpoint | Representer | View |
|----------|-------------|------|
| GET /api/v3/memberships/:id | MembershipRepresenter | api_v3_memberships |
| GET /api/v3/memberships | MembershipCollectionRepresenter | api_v3_memberships + filters |

## Known Gaps (requires follow-up)

1. **Permission-gated links**: The views currently include all action links.
   In production, links like `delete` and `update` should only appear when
   the current user has permission. Options:
   - PostgreSQL function that accepts user_id parameter
   - Post-query filtering in Ruby (lightweight)
   - Row-level security policies

2. **Custom fields**: Dynamic `customField{N}` properties are injected by
   `CustomFieldInjector`. These need a separate join to `custom_values` table
   with pivot logic. Next migration target.

3. **Embedded resources**: Full `_embedded` section (nested project, type, etc.)
   requires sub-selects or lateral joins. Views currently provide link-only
   references. Embeds are Phase 5.

4. **Formattable HTML**: The `hal_formattable()` function does basic HTML
   escaping. Full Markdown-to-HTML rendering (textile/commonmark) still
   needs app-level processing or a PostgreSQL extension.

5. **Collection wrapping**: Collection endpoints need HAL collection wrapper:
   ```json
   {
     "_type": "WorkPackageCollection",
     "total": 142,
     "count": 20,
     "pageSize": 20,
     "offset": 1,
     "_embedded": { "elements": [...] }
   }
   ```
   This can be a PostgreSQL function wrapping the view query.

## Validation Strategy (QA-Conscience)

For each converted endpoint:

```bash
# 1. Capture current response
curl -s "http://localhost:3000/api/v3/work_packages/1" \
  -H "Authorization: Basic ..." | jq . > before.json

# 2. Deploy view-backed version
# 3. Capture new response
curl -s "http://localhost:3000/api/v3/work_packages/1" \
  -H "Authorization: Basic ..." | jq . > after.json

# 4. Diff (ignoring _embedded which is Phase 5)
diff <(jq 'del(._embedded)' before.json) \
     <(jq 'del(._embedded)' after.json)
```

Zero diff = safe to ship.
