# frozen_string_literal: true

# De-JSONification Migration: Replace ROAR representers with PostgreSQL views
#
# BEFORE: Model → Representer (Ruby) → HAL+JSON → Response
# AFTER:  Model → PostgreSQL View (SQL) → HAL+JSON → Response
#
# This migration creates:
# 1. HAL helper functions (link builders, formatters)
# 2. API v3 views for: work_packages, projects, versions, memberships
#
# Reversible: DROP VIEW / DROP FUNCTION to roll back.

class CreateHalViews < ActiveRecord::Migration[7.1]
  def up
    # =========================================================================
    # 1. HAL Helper Functions
    # =========================================================================

    execute <<~SQL
      -- HAL link: {"href": "/path", "title": "Name"}
      CREATE OR REPLACE FUNCTION hal_link(href text, title text DEFAULT NULL)
      RETURNS jsonb AS $$
        SELECT jsonb_strip_nulls(jsonb_build_object('href', href, 'title', title));
      $$ LANGUAGE sql IMMUTABLE;

      -- HAL action link: {"href": "/path", "method": "post", "title": "Name"}
      CREATE OR REPLACE FUNCTION hal_action_link(href text, method text, title text DEFAULT NULL)
      RETURNS jsonb AS $$
        SELECT jsonb_strip_nulls(jsonb_build_object('href', href, 'method', method, 'title', title));
      $$ LANGUAGE sql IMMUTABLE;

      -- Formattable property: {"raw": "text", "html": "<p>text</p>"}
      CREATE OR REPLACE FUNCTION hal_formattable(raw_text text)
      RETURNS jsonb AS $$
        SELECT CASE
          WHEN raw_text IS NULL THEN NULL::jsonb
          ELSE jsonb_build_object(
            'raw', raw_text,
            'html', '<p>' || replace(replace(raw_text, '&', '&amp;'), '<', '&lt;') || '</p>'
          )
        END;
      $$ LANGUAGE sql IMMUTABLE;

      -- Duration from hours to ISO 8601: "PT2H30M"
      CREATE OR REPLACE FUNCTION hal_duration(hours numeric)
      RETURNS text AS $$
        SELECT CASE
          WHEN hours IS NULL THEN NULL
          ELSE 'PT' ||
            CASE WHEN floor(hours) > 0 THEN floor(hours)::int::text || 'H' ELSE '' END ||
            CASE WHEN (hours - floor(hours)) * 60 > 0 THEN round((hours - floor(hours)) * 60)::int::text || 'M' ELSE '' END
        END;
      $$ LANGUAGE sql IMMUTABLE;

      -- Timestamp to ISO 8601
      CREATE OR REPLACE FUNCTION hal_datetime(ts timestamptz)
      RETURNS text AS $$
        SELECT CASE
          WHEN ts IS NULL THEN NULL
          ELSE to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
        END;
      $$ LANGUAGE sql IMMUTABLE;

      -- Date to ISO string
      CREATE OR REPLACE FUNCTION hal_date(d date)
      RETURNS text AS $$
        SELECT CASE WHEN d IS NULL THEN NULL ELSE to_char(d, 'YYYY-MM-DD') END;
      $$ LANGUAGE sql IMMUTABLE;

      -- Self link helper
      CREATE OR REPLACE FUNCTION hal_self_link(resource_path text, resource_id integer, title text DEFAULT NULL)
      RETURNS jsonb AS $$
        SELECT hal_link('/api/v3/' || resource_path || '/' || resource_id::text, title);
      $$ LANGUAGE sql IMMUTABLE;
    SQL

    # =========================================================================
    # 2. API v3 Work Packages View
    # =========================================================================

    execute <<~SQL
      CREATE OR REPLACE VIEW api_v3_work_packages AS
      SELECT
        wp.id,
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
          '_links', jsonb_strip_nulls(jsonb_build_object(
            'self',              hal_link('/api/v3/work_packages/' || wp.id::text, wp.subject),
            'schema',            hal_link('/api/v3/work_package_schemas/' || wp.project_id::text || '/' || wp.type_id::text),
            'update',            hal_action_link('/api/v3/work_packages/' || wp.id::text || '/form', 'post'),
            'updateImmediately', hal_action_link('/api/v3/work_packages/' || wp.id::text, 'patch'),
            'delete',            hal_action_link('/api/v3/work_packages/' || wp.id::text, 'delete'),
            'project',           hal_link('/api/v3/projects/' || wp.project_id::text, p.name),
            'type',              CASE WHEN wp.type_id IS NOT NULL THEN hal_link('/api/v3/types/' || wp.type_id::text, t.name) END,
            'status',            CASE WHEN wp.status_id IS NOT NULL THEN hal_link('/api/v3/statuses/' || wp.status_id::text, s.name) END,
            'priority',          CASE WHEN wp.priority_id IS NOT NULL THEN hal_link('/api/v3/priorities/' || wp.priority_id::text, pr.name) END,
            'author',            CASE WHEN wp.author_id IS NOT NULL THEN hal_link('/api/v3/users/' || wp.author_id::text, author.login) END,
            'assignee',          CASE WHEN wp.assigned_to_id IS NOT NULL THEN hal_link('/api/v3/principals/' || wp.assigned_to_id::text, assignee.login) END,
            'responsible',       CASE WHEN wp.responsible_id IS NOT NULL THEN hal_link('/api/v3/principals/' || wp.responsible_id::text, responsible.login) END,
            'version',           CASE WHEN wp.version_id IS NOT NULL THEN hal_link('/api/v3/versions/' || wp.version_id::text, v.name) END,
            'parent',            CASE WHEN wp.parent_id IS NOT NULL THEN hal_link('/api/v3/work_packages/' || wp.parent_id::text, parent_wp.subject) END,
            'category',          CASE WHEN wp.category_id IS NOT NULL THEN hal_link('/api/v3/categories/' || wp.category_id::text, cat.name) END,
            'activities',        hal_link('/api/v3/work_packages/' || wp.id::text || '/activities'),
            'relations',         hal_link('/api/v3/work_packages/' || wp.id::text || '/relations'),
            'watchers',          hal_link('/api/v3/work_packages/' || wp.id::text || '/watchers'),
            'revisions',         hal_link('/api/v3/work_packages/' || wp.id::text || '/revisions')
          ))
        ) AS hal_json,
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
      LEFT JOIN projects     p           ON p.id = wp.project_id
      LEFT JOIN types        t           ON t.id = wp.type_id
      LEFT JOIN statuses     s           ON s.id = wp.status_id
      LEFT JOIN enumerations pr          ON pr.id = wp.priority_id
      LEFT JOIN users        author      ON author.id = wp.author_id
      LEFT JOIN users        assignee    ON assignee.id = wp.assigned_to_id
      LEFT JOIN users        responsible ON responsible.id = wp.responsible_id
      LEFT JOIN versions     v           ON v.id = wp.version_id
      LEFT JOIN work_packages parent_wp  ON parent_wp.id = wp.parent_id
      LEFT JOIN categories   cat         ON cat.id = wp.category_id;
    SQL

    # =========================================================================
    # 3. API v3 Projects View
    # =========================================================================

    execute <<~SQL
      CREATE OR REPLACE VIEW api_v3_projects AS
      SELECT
        p.id,
        jsonb_build_object(
          '_type',       CASE WHEN p.templated THEN 'ProjectTemplate' ELSE 'Project' END,
          'id',          p.id,
          'identifier',  p.identifier,
          'name',        p.name,
          'active',      p.active,
          'public',      p.public,
          'description', hal_formattable(p.description),
          'createdAt',   hal_datetime(p.created_at),
          'updatedAt',   hal_datetime(p.updated_at),
          'status',      CASE WHEN p.status_code IS NOT NULL
                           THEN jsonb_build_object('code', p.status_code, 'explanation', hal_formattable(p.status_explanation))
                         END,
          '_links', jsonb_strip_nulls(jsonb_build_object(
            'self',                        hal_link('/api/v3/projects/' || p.id::text, p.name),
            'schema',                      hal_link('/api/v3/projects/schema'),
            'createWorkPackage',           hal_action_link('/api/v3/projects/' || p.id::text || '/work_packages/form', 'post'),
            'createWorkPackageImmediately', hal_action_link('/api/v3/projects/' || p.id::text || '/work_packages', 'post'),
            'workPackages',                hal_link('/api/v3/projects/' || p.id::text || '/work_packages'),
            'categories',                  hal_link('/api/v3/projects/' || p.id::text || '/categories'),
            'versions',                    hal_link('/api/v3/projects/' || p.id::text || '/versions'),
            'types',                       hal_link('/api/v3/projects/' || p.id::text || '/types'),
            'update',                      hal_action_link('/api/v3/projects/' || p.id::text || '/form', 'post'),
            'updateImmediately',           hal_action_link('/api/v3/projects/' || p.id::text, 'patch'),
            'delete',                      hal_action_link('/api/v3/projects/' || p.id::text, 'delete'),
            'parent',                      CASE WHEN p.parent_id IS NOT NULL
                                             THEN hal_link('/api/v3/projects/' || p.parent_id::text, parent_p.name)
                                           END
          ))
        ) AS hal_json,
        p.identifier,
        p.name,
        p.active,
        p.public,
        p.parent_id,
        p.created_at,
        p.updated_at
      FROM projects p
      LEFT JOIN projects parent_p ON parent_p.id = p.parent_id;
    SQL

    # =========================================================================
    # 4. API v3 Versions View
    # =========================================================================

    execute <<~SQL
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
            'update',            hal_action_link('/api/v3/versions/' || v.id::text || '/form', 'post'),
            'updateImmediately', hal_action_link('/api/v3/versions/' || v.id::text, 'patch'),
            'delete',            hal_action_link('/api/v3/versions/' || v.id::text, 'delete'),
            'definingProject',   hal_link('/api/v3/projects/' || v.project_id::text, p.name)
          ))
        ) AS hal_json,
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
    SQL

    # =========================================================================
    # 5. API v3 Memberships View
    # =========================================================================

    execute <<~SQL
      CREATE OR REPLACE VIEW api_v3_memberships AS
      SELECT
        m.id,
        jsonb_build_object(
          '_type',     'Membership',
          'id',        m.id,
          'createdAt', hal_datetime(m.created_at),
          'updatedAt', hal_datetime(m.updated_at),
          '_links', jsonb_strip_nulls(jsonb_build_object(
            'self',              hal_link('/api/v3/memberships/' || m.id::text, u.login),
            'schema',            hal_link('/api/v3/memberships/schema'),
            'update',            hal_action_link('/api/v3/memberships/' || m.id::text || '/form', 'post'),
            'updateImmediately', hal_action_link('/api/v3/memberships/' || m.id::text, 'patch'),
            'project',           CASE WHEN m.project_id IS NOT NULL
                                   THEN hal_link('/api/v3/projects/' || m.project_id::text, p.name)
                                 END,
            'principal',         hal_link('/api/v3/users/' || m.user_id::text, u.login),
            'roles',             (
                                   SELECT jsonb_agg(hal_link('/api/v3/roles/' || r.id::text, r.name))
                                   FROM member_roles mr
                                   JOIN roles r ON r.id = mr.role_id
                                   WHERE mr.member_id = m.id
                                 )
          ))
        ) AS hal_json,
        m.project_id,
        m.user_id,
        m.created_at,
        m.updated_at
      FROM members m
      LEFT JOIN projects p ON p.id = m.project_id
      LEFT JOIN users    u ON u.id = m.user_id;
    SQL
  end

  def down
    execute "DROP VIEW IF EXISTS api_v3_memberships;"
    execute "DROP VIEW IF EXISTS api_v3_versions;"
    execute "DROP VIEW IF EXISTS api_v3_projects;"
    execute "DROP VIEW IF EXISTS api_v3_work_packages;"
    execute "DROP FUNCTION IF EXISTS hal_self_link(text, integer, text);"
    execute "DROP FUNCTION IF EXISTS hal_date(date);"
    execute "DROP FUNCTION IF EXISTS hal_datetime(timestamptz);"
    execute "DROP FUNCTION IF EXISTS hal_duration(numeric);"
    execute "DROP FUNCTION IF EXISTS hal_formattable(text);"
    execute "DROP FUNCTION IF EXISTS hal_action_link(text, text, text);"
    execute "DROP FUNCTION IF EXISTS hal_link(text, text);"
  end
end
