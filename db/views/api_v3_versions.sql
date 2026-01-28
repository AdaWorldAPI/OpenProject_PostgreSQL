-- =============================================================================
-- api_v3_versions: PostgreSQL view replacing VersionRepresenter
-- =============================================================================
-- Replaces: lib/api/v3/versions/version_representer.rb
-- Output:   HAL+JSON compatible with OpenProject API v3
-- =============================================================================

CREATE OR REPLACE VIEW api_v3_versions AS
SELECT
  v.id,

  jsonb_build_object(
    '_type',       'Version',
    'id',          v.id,
    'name',        v.name,
    'description', hal_formattable(v.description),
    'startDate',   hal_date(v.start_date),
    'endDate',     hal_date(v.effective_date),
    'status',      v.status,
    'sharing',     v.sharing,
    'createdAt',   hal_datetime(v.created_at),
    'updatedAt',   hal_datetime(v.updated_at),

    '_links', jsonb_strip_nulls(jsonb_build_object(
      'self',              hal_link('/api/v3/versions/' || v.id::text, v.name),
      'schema',            hal_link('/api/v3/versions/schema'),
      'update',            hal_action_link(
                             '/api/v3/versions/' || v.id::text || '/form',
                             'post'
                           ),
      'updateImmediately', hal_action_link(
                             '/api/v3/versions/' || v.id::text,
                             'patch'
                           ),
      'delete',            hal_action_link(
                             '/api/v3/versions/' || v.id::text,
                             'delete'
                           ),
      'definingProject',   hal_link(
                             '/api/v3/projects/' || v.project_id::text,
                             p.name
                           )
    ))
  ) AS hal_json,

  -- Raw columns for SQL-level filtering
  v.project_id,
  v.name,
  v.status,
  v.sharing,
  v.start_date,
  v.effective_date,
  v.created_at,
  v.updated_at

FROM versions v
LEFT JOIN projects p ON p.id = v.project_id;

COMMENT ON VIEW api_v3_versions IS
  'De-JSONified version representation. Replaces VersionRepresenter.
   Returns HAL+JSON directly from PostgreSQL.';
