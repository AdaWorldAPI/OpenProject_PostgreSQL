# frozen_string_literal: true

module HalCache
  # Two-tier cache store: DragonflyDB (hot) + PostgreSQL JSONB (warm).
  #
  # Usage:
  #   HalCache::Store.fetch("WorkPackage", 1234) → HAL+JSON string
  #   HalCache::Store.write("WorkPackage", 1234, json_string)
  #   HalCache::Store.invalidate("WorkPackage", 1234)
  #
  class Store
    class << self
      # Read path: Dragonfly → PostgreSQL → nil (caller must compute)
      def fetch(resource_type, resource_id)
        key = cache_key(resource_type, resource_id)

        # Tier 1: DragonflyDB (hot, <1ms)
        json = dragonfly_get(key)
        return json if json

        # Tier 2: PostgreSQL JSONB (warm, ~5ms)
        record = pg_get(resource_type, resource_id)
        if record && !record.stale?
          json = record.hal_json.to_json
          dragonfly_set(key, json)  # promote to hot
          return json
        end

        nil  # cache miss — caller falls back to ROAR
      end

      # Write both tiers after computing HAL+JSON
      def write(resource_type, resource_id, hal_json_string, version: nil)
        key = cache_key(resource_type, resource_id, version: version)

        # Tier 1: DragonflyDB
        dragonfly_set(key, hal_json_string)

        # Tier 2: PostgreSQL JSONB (upsert)
        pg_upsert(resource_type, resource_id, key, hal_json_string)
      end

      # Invalidate: delete hot, mark warm as stale
      def invalidate(resource_type, resource_id)
        # Delete all version variants from Dragonfly
        pattern = "hal:v3:#{resource_type.underscore}:#{resource_id}:*"
        keys = HalCache.dragonfly.keys(pattern)
        HalCache.dragonfly.del(*keys) if keys.any?

        # Mark PostgreSQL record as stale
        HalCacheRecord.where(resource_type: resource_type, resource_id: resource_id)
                      .update_all(stale: true)
      end

      # Bulk invalidate (e.g., when a Status name changes, all WPs with that status)
      def invalidate_all(resource_type, resource_ids)
        resource_ids.each { |id| invalidate(resource_type, id) }
      end

      private

      def cache_key(resource_type, resource_id, version: nil)
        base = "hal:v3:#{resource_type.underscore}:#{resource_id}"
        version ? "#{base}:#{version}" : base
      end

      def dragonfly_get(key)
        HalCache.dragonfly.get(key)
      rescue Redis::BaseError => e
        Rails.logger.warn("HalCache DragonflyDB read failed: #{e.message}")
        nil  # degrade gracefully to PostgreSQL tier
      end

      def dragonfly_set(key, json)
        HalCache.dragonfly.setex(key, HalCache::DEFAULT_TTL, json)
      rescue Redis::BaseError => e
        Rails.logger.warn("HalCache DragonflyDB write failed: #{e.message}")
      end

      def pg_get(resource_type, resource_id)
        HalCacheRecord.find_by(resource_type: resource_type, resource_id: resource_id)
      end

      def pg_upsert(resource_type, resource_id, key, json_string)
        parsed = JSON.parse(json_string)
        HalCacheRecord.upsert(
          {
            resource_type: resource_type,
            resource_id: resource_id,
            cache_key: key,
            hal_json: parsed,
            stale: false,
            updated_at: Time.current
          },
          unique_by: [:resource_type, :resource_id]
        )
      end
    end
  end
end
