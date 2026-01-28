-- =============================================================================
-- api_v3_projects: PostgreSQL view replacing ProjectRepresenter
-- =============================================================================
-- Replaces: lib/api/v3/projects/project_representer.rb
-- Output:   HAL+JSON compatible with OpenProject API v3
-- =============================================================================

CREATE OR REPLACE VIEW api_v3_projects AS
SELECT
  p.id,

  jsonb_build_object(
    '_type',          CASE
                        WHEN p.templated THEN 'ProjectTemplate'
                        ELSE 'Project'
                      END,
    'id',             p.id,
    'identifier',     p.identifier,
    'name',           p.name,
    'active',         p.active,
    'public',         p.public,
    'description',    hal_formattable(p.description),
    'createdAt',      hal_datetime(p.created_at),
    'updatedAt',      hal_datetime(p.updated_at),

    'status', CASE WHEN p.status_code IS NOT NULL
      THEN jsonb_build_object(
        'code', p.status_code,
        'explanation', hal_formattable(p.status_explanation)
      )
      ELSE NULL
    END,

    '_links', jsonb_strip_nulls(jsonb_build_object(
      'self',                       hal_link('/api/v3/projects/' || p.id::text, p.name),
      'schema',                     hal_link('/api/v3/projects/schema'),
      'createWorkPackage',          hal_action_link(
                                      '/api/v3/projects/' || p.id::text || '/work_packages/form',
                                      'post'
                                    ),
      'createWorkPackageImmediately', hal_action_link(
                                      '/api/v3/projects/' || p.id::text || '/work_packages',
                                      'post'
                                    ),
      'workPackages',               hal_link('/api/v3/projects/' || p.id::text || '/work_packages'),
      'categories',                 hal_link('/api/v3/projects/' || p.id::text || '/categories'),
      'versions',                   hal_link('/api/v3/projects/' || p.id::text || '/versions'),
      'types',                      hal_link('/api/v3/projects/' || p.id::text || '/types'),
      'update',                     hal_action_link(
                                      '/api/v3/projects/' || p.id::text || '/form',
                                      'post'
                                    ),
      'updateImmediately',          hal_action_link(
                                      '/api/v3/projects/' || p.id::text,
                                      'patch'
                                    ),
      'delete',                     hal_action_link(
                                      '/api/v3/projects/' || p.id::text,
                                      'delete'
                                    ),
      'parent',                     CASE WHEN p.parent_id IS NOT NULL
                                      THEN hal_link(
                                        '/api/v3/projects/' || p.parent_id::text,
                                        parent_p.name
                                      )
                                    END,
      'status',                     CASE WHEN p.status_code IS NOT NULL
                                      THEN hal_link('/api/v3/project_statuses/' || p.status_code)
                                    END
    ))
  ) AS hal_json,

  -- Raw columns for SQL-level filtering
  p.identifier,
  p.name,
  p.active,
  p.public,
  p.parent_id,
  p.created_at,
  p.updated_at

FROM projects p
LEFT JOIN projects parent_p ON parent_p.id = p.parent_id;

COMMENT ON VIEW api_v3_projects IS
  'De-JSONified project representation. Replaces ProjectRepresenter.
   Returns HAL+JSON directly from PostgreSQL.';
