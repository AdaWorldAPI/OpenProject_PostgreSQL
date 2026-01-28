-- =============================================================================
-- api_v3_memberships: PostgreSQL view replacing MembershipRepresenter
-- =============================================================================
-- Replaces: lib/api/v3/memberships/membership_representer.rb
-- Output:   HAL+JSON compatible with OpenProject API v3
-- =============================================================================

CREATE OR REPLACE VIEW api_v3_memberships AS
SELECT
  m.id,

  jsonb_build_object(
    '_type',       'Membership',
    'id',          m.id,
    'createdAt',   hal_datetime(m.created_at),
    'updatedAt',   hal_datetime(m.updated_at),

    '_links', jsonb_strip_nulls(jsonb_build_object(
      'self',              hal_link(
                             '/api/v3/memberships/' || m.id::text,
                             u.login
                           ),
      'schema',            hal_link('/api/v3/memberships/schema'),
      'update',            hal_action_link(
                             '/api/v3/memberships/' || m.id::text || '/form',
                             'post'
                           ),
      'updateImmediately', hal_action_link(
                             '/api/v3/memberships/' || m.id::text,
                             'patch'
                           ),
      'project',           CASE WHEN m.project_id IS NOT NULL
                             THEN hal_link(
                               '/api/v3/projects/' || m.project_id::text,
                               p.name
                             )
                           END,
      'principal',         hal_link(
                             '/api/v3/users/' || m.user_id::text,
                             u.login
                           ),
      'roles',             (
                             SELECT jsonb_agg(
                               hal_link(
                                 '/api/v3/roles/' || r.id::text,
                                 r.name
                               )
                             )
                             FROM member_roles mr
                             JOIN roles r ON r.id = mr.role_id
                             WHERE mr.member_id = m.id
                           )
    ))
  ) AS hal_json,

  -- Raw columns for SQL-level filtering
  m.project_id,
  m.user_id,
  m.created_at,
  m.updated_at

FROM members m
LEFT JOIN projects p ON p.id = m.project_id
LEFT JOIN users    u ON u.id = m.user_id;

COMMENT ON VIEW api_v3_memberships IS
  'De-JSONified membership representation. Replaces MembershipRepresenter.
   Returns HAL+JSON directly from PostgreSQL.';
