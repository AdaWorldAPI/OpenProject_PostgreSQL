# frozen_string_literal: true

# Background job: recompute HAL+JSON for a single resource and store
# in both cache tiers (DragonflyDB + PostgreSQL JSONB).
#
# This is the ONLY place where ROAR representers run after warm-up.
# Request path never touches ROAR — it reads from cache.
#
# Enqueued by:
#   - HalCache::Invalidator (after_commit on model changes)
#   - HalCache::BulkWarmJob (initial cache population)
#   - Manual: HalCacheWarmJob.perform_async("WorkPackage", 42)

class HalCacheWarmJob
  include Sidekiq::Job

  sidekiq_options queue: :hal_cache, retry: 3, dead: false

  REPRESENTER_MAP = {
    "WorkPackage" => "API::V3::WorkPackages::WorkPackageRepresenter",
    "Project"     => "API::V3::Projects::ProjectRepresenter",
    "Version"     => "API::V3::Versions::VersionRepresenter",
    "Membership"  => "API::V3::Memberships::MembershipRepresenter"
  }.freeze

  def perform(resource_type, resource_id)
    model_class = resource_type.constantize
    record = model_class.find_by(id: resource_id)
    return unless record  # deleted between enqueue and execution

    representer_class = REPRESENTER_MAP[resource_type]&.constantize
    return unless representer_class

    # Compute HAL+JSON via ROAR (the expensive part — but background only)
    representer = representer_class.new(record, current_user: system_user, embed_links: true)
    json = representer.to_json

    # Store in both tiers
    version = record.respond_to?(:lock_version) ? record.lock_version : record.updated_at.to_i
    HalCache::Store.write(resource_type, resource_id, json, version: version)
  end

  private

  def system_user
    # Use the system user for background cache computation.
    # Permission-gated links are handled separately at read time.
    @system_user ||= User.system
  end
end
