# frozen_string_literal: true

# Bulk warm the cache on deployment or cold start.
# Iterates all resources of a given type and enqueues individual warm jobs.
#
# Usage:
#   HalCacheBulkWarmJob.perform_async("WorkPackage")
#   HalCacheBulkWarmJob.perform_async("all")

class HalCacheBulkWarmJob
  include Sidekiq::Job

  sidekiq_options queue: :hal_cache, retry: 1

  RESOURCE_TYPES = %w[WorkPackage Project Version Membership].freeze

  def perform(resource_type)
    types = resource_type == "all" ? RESOURCE_TYPES : [resource_type]

    types.each do |type|
      type.constantize.find_in_batches(batch_size: 500) do |batch|
        batch.each do |record|
          HalCacheWarmJob.perform_async(type, record.id)
        end
      end
    end
  end
end
