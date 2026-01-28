-- =============================================================================
-- api_v3_work_packages: PostgreSQL view replacing WorkPackageRepresenter
-- =============================================================================
-- Replaces: lib/api/v3/work_packages/work_package_representer.rb (311 lines)
-- Output:   HAL+JSON compatible with OpenProject API v3
-- =============================================================================

CREATE OR REPLACE VIEW api_v3_work_packages AS
SELECT
  wp.id,

  -- Scalar properties (direct columns)
  jsonb_build_object(
    '_type',               'WorkPackage',
    'id',                  wp.id,
    'lockVersion',         wp.lock_version,
    'subject',             wp.subject,
    'description',         hal_formattable(wp.description),
    'scheduleManually',    wp.schedule_manually,
    'startDate',           hal_date(wp.start_date),
    'dueDate',             hal_date(wp.due_date),
    'derivedStartDate',    hal_date(wp.derived_start_date),
    'derivedDueDate',      hal_date(wp.derived_due_date),
    'estimatedTime',       hal_duration(wp.estimated_hours),
    'derivedEstimatedTime', hal_duration(wp.derived_estimated_hours),
    'remainingTime',       hal_duration(wp.remaining_hours),
    'derivedRemainingTime', hal_duration(wp.derived_remaining_hours),
    'duration',            wp.duration,
    'ignoreNonWorkingDays', wp.ignore_non_working_days,
    'percentageDone',      wp.done_ratio,
    'createdAt',           hal_datetime(wp.created_at),
    'updatedAt',           hal_datetime(wp.updated_at),

    -- HAL _links
    '_links', jsonb_strip_nulls(jsonb_build_object(
      'self',              hal_link(
                             '/api/v3/work_packages/' || wp.id::text,
                             wp.subject
                           ),
      'schema',            hal_link(
                             '/api/v3/work_package_schemas/' || wp.project_id::text || '/' || wp.type_id::text
                           ),
      'update',            hal_action_link(
                             '/api/v3/work_packages/' || wp.id::text || '/form',
                             'post'
                           ),
      'updateImmediately', hal_action_link(
                             '/api/v3/work_packages/' || wp.id::text,
                             'patch'
                           ),
      'delete',            hal_action_link(
                             '/api/v3/work_packages/' || wp.id::text,
                             'delete'
                           ),
      'project',           hal_link(
                             '/api/v3/projects/' || wp.project_id::text,
                             p.name
                           ),
      'type',              CASE WHEN wp.type_id IS NOT NULL
                             THEN hal_link('/api/v3/types/' || wp.type_id::text, t.name)
                           END,
      'status',            CASE WHEN wp.status_id IS NOT NULL
                             THEN hal_link('/api/v3/statuses/' || wp.status_id::text, s.name)
                           END,
      'priority',          CASE WHEN wp.priority_id IS NOT NULL
                             THEN hal_link('/api/v3/priorities/' || wp.priority_id::text, pr.name)
                           END,
      'author',            CASE WHEN wp.author_id IS NOT NULL
                             THEN hal_link('/api/v3/users/' || wp.author_id::text, author.login)
                           END,
      'assignee',          CASE WHEN wp.assigned_to_id IS NOT NULL
                             THEN hal_link('/api/v3/principals/' || wp.assigned_to_id::text, assignee.login)
                           END,
      'responsible',       CASE WHEN wp.responsible_id IS NOT NULL
                             THEN hal_link('/api/v3/principals/' || wp.responsible_id::text, responsible.login)
                           END,
      'version',           CASE WHEN wp.version_id IS NOT NULL
                             THEN hal_link('/api/v3/versions/' || wp.version_id::text, v.name)
                           END,
      'parent',            CASE WHEN wp.parent_id IS NOT NULL
                             THEN hal_link('/api/v3/work_packages/' || wp.parent_id::text, parent_wp.subject)
                           END,
      'category',          CASE WHEN wp.category_id IS NOT NULL
                             THEN hal_link('/api/v3/categories/' || wp.category_id::text, cat.name)
                           END,
      'activities',        hal_link('/api/v3/work_packages/' || wp.id::text || '/activities'),
      'relations',         hal_link('/api/v3/work_packages/' || wp.id::text || '/relations'),
      'watchers',          hal_link('/api/v3/work_packages/' || wp.id::text || '/watchers'),
      'revisions',         hal_link('/api/v3/work_packages/' || wp.id::text || '/revisions')
    ))
  ) AS hal_json,

  -- Raw columns for filtering/ordering at SQL level
  wp.project_id,
  wp.type_id,
  wp.status_id,
  wp.priority_id,
  wp.author_id,
  wp.assigned_to_id,
  wp.version_id,
  wp.parent_id,
  wp.created_at,
  wp.updated_at

FROM work_packages wp
LEFT JOIN projects     p          ON p.id = wp.project_id
LEFT JOIN types        t          ON t.id = wp.type_id
LEFT JOIN statuses     s          ON s.id = wp.status_id
LEFT JOIN enumerations pr         ON pr.id = wp.priority_id
LEFT JOIN users        author     ON author.id = wp.author_id
LEFT JOIN users        assignee   ON assignee.id = wp.assigned_to_id
LEFT JOIN users        responsible ON responsible.id = wp.responsible_id
LEFT JOIN versions     v          ON v.id = wp.version_id
LEFT JOIN work_packages parent_wp ON parent_wp.id = wp.parent_id
LEFT JOIN categories   cat        ON cat.id = wp.category_id;

COMMENT ON VIEW api_v3_work_packages IS
  'De-JSONified work package representation. Replaces WorkPackageRepresenter.
   Returns HAL+JSON directly from PostgreSQL, no Ruby decorator needed.';
