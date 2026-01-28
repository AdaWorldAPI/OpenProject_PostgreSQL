# frozen_string_literal: true

module HalCache
  # ActiveRecord model backed by the hal_cache table (warm tier).
  class Record < ActiveRecord::Base
    self.table_name = "hal_cache"

    scope :fresh, -> { where(stale: false) }
    scope :stale, -> { where(stale: true) }
    scope :for_resource, ->(type, id) { where(resource_type: type, resource_id: id) }
  end
end

# Alias for convenience in Store
HalCacheRecord = HalCache::Record
