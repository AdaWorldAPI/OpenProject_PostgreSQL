-- =============================================================================
-- HAL+JSON Helper Functions
-- Replace ROAR decorator patterns with pure PostgreSQL
-- =============================================================================

-- Build a HAL link object: {"href": "/path", "title": "Name"}
CREATE OR REPLACE FUNCTION hal_link(href text, title text DEFAULT NULL)
RETURNS jsonb AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'href', href,
    'title', title
  ));
$$ LANGUAGE sql IMMUTABLE;

-- Build a HAL action link: {"href": "/path", "method": "post", "title": "Name"}
CREATE OR REPLACE FUNCTION hal_action_link(href text, method text, title text DEFAULT NULL)
RETURNS jsonb AS $$
  SELECT jsonb_strip_nulls(jsonb_build_object(
    'href', href,
    'method', method,
    'title', title
  ));
$$ LANGUAGE sql IMMUTABLE;

-- Build a formattable property: {"raw": "text", "html": "<p>text</p>"}
-- NOTE: Full markdown→HTML requires app-level rendering. This provides raw + basic wrap.
CREATE OR REPLACE FUNCTION hal_formattable(raw_text text)
RETURNS jsonb AS $$
  SELECT CASE
    WHEN raw_text IS NULL THEN NULL::jsonb
    ELSE jsonb_build_object(
      'raw', raw_text,
      'html', '<p>' || replace(
        replace(raw_text, '&', '&amp;'),
        '<', '&lt;'
      ) || '</p>'
    )
  END;
$$ LANGUAGE sql IMMUTABLE;

-- Format duration from hours (numeric) to ISO 8601 duration string: "PT2H30M"
CREATE OR REPLACE FUNCTION hal_duration(hours numeric)
RETURNS text AS $$
  SELECT CASE
    WHEN hours IS NULL THEN NULL
    ELSE 'PT' ||
      CASE WHEN floor(hours) > 0
        THEN floor(hours)::int::text || 'H'
        ELSE ''
      END ||
      CASE WHEN (hours - floor(hours)) * 60 > 0
        THEN round((hours - floor(hours)) * 60)::int::text || 'M'
        ELSE ''
      END
  END;
$$ LANGUAGE sql IMMUTABLE;

-- Format timestamp to ISO 8601 string
CREATE OR REPLACE FUNCTION hal_datetime(ts timestamptz)
RETURNS text AS $$
  SELECT CASE
    WHEN ts IS NULL THEN NULL
    ELSE to_char(ts AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS"Z"')
  END;
$$ LANGUAGE sql IMMUTABLE;

-- Format date to ISO date string
CREATE OR REPLACE FUNCTION hal_date(d date)
RETURNS text AS $$
  SELECT CASE
    WHEN d IS NULL THEN NULL
    ELSE to_char(d, 'YYYY-MM-DD')
  END;
$$ LANGUAGE sql IMMUTABLE;

-- Build an API v3 self link for a resource type
CREATE OR REPLACE FUNCTION hal_self_link(resource_path text, resource_id integer, title text DEFAULT NULL)
RETURNS jsonb AS $$
  SELECT hal_link('/api/v3/' || resource_path || '/' || resource_id::text, title);
$$ LANGUAGE sql IMMUTABLE;
