# frozen_string_literal: true

# DragonflyDB connection for HAL+JSON hot cache.
# DragonflyDB is Redis-compatible — uses the standard redis gem.
#
# ENV:
#   DRAGONFLY_URL - connection URL (default: redis://localhost:6379/1)
#   HAL_CACHE_TTL - TTL in seconds for hot cache entries (default: 300)

require "redis"

module HalCache
  DRAGONFLY_URL = ENV.fetch("DRAGONFLY_URL", "redis://localhost:6379/1")
  DEFAULT_TTL   = ENV.fetch("HAL_CACHE_TTL", 300).to_i

  def self.dragonfly
    @dragonfly ||= Redis.new(url: DRAGONFLY_URL)
  end

  def self.reset_connection!
    @dragonfly&.close
    @dragonfly = nil
  end
end
