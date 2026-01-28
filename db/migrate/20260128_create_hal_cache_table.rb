# frozen_string_literal: true

# Warm cache: PostgreSQL JSONB table for pre-computed HAL+JSON.
#
# This table stores the fully-rendered HAL+JSON for each API resource,
# eliminating the need to run ROAR representers on every request.
#
# Read path:  DragonflyDB (hot, <1ms) → hal_cache JSONB (warm, ~5ms) → ROAR (cold, ~3s)
# Write path: Model change → background job → recompute → store in both tiers

class CreateHalCacheTable < ActiveRecord::Migration[7.1]
  def change
    create_table :hal_cache do |t|
      t.string  :resource_type,  null: false  # e.g. "WorkPackage", "Project"
      t.integer :resource_id,    null: false  # FK to the source model
      t.string  :cache_key,      null: false  # "hal:v3:work_package:1234:17"
      t.jsonb   :hal_json,       null: false  # The pre-computed HAL+JSON
      t.boolean :stale,          null: false, default: false
      t.timestamps
    end

    add_index :hal_cache, [:resource_type, :resource_id], unique: true, name: "idx_hal_cache_resource"
    add_index :hal_cache, :cache_key, unique: true, name: "idx_hal_cache_key"
    add_index :hal_cache, :stale, name: "idx_hal_cache_stale", where: "stale = true"
  end
end
