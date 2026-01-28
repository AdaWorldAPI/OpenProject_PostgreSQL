# frozen_string_literal: true

# Controller concern: serve HAL+JSON from cache instead of ROAR representers.
#
# BEFORE (3s):
#   representer = WorkPackageRepresenter.new(wp, current_user: current_user)
#   render json: representer.to_json
#
# AFTER (<1ms from DragonflyDB, ~5ms from PostgreSQL):
#   render_hal "WorkPackage", params[:id]
#
module HalCachedResponse
  extend ActiveSupport::Concern

  private

  # Serve pre-computed HAL+JSON from the two-tier cache.
  # Falls back to ROAR representer on cold cache (and warms it).
  def render_hal(resource_type, resource_id, status: :ok)
    json = HalCache::Store.fetch(resource_type, resource_id)

    if json
      render json: json, status: status
    else
      # Cold miss: compute synchronously this one time, cache for next
      record = resource_type.constantize.find(resource_id)
      representer = hal_representer_for(resource_type, record)
      json = representer.to_json

      HalCache::Store.write(resource_type, resource_id, json)
      render json: json, status: status
    end
  end

  # Serve a collection from cache (each element fetched individually).
  def render_hal_collection(resource_type, scope, page:, per_page:)
    total = scope.count
    records = scope.offset((page - 1) * per_page).limit(per_page)

    elements = records.map do |record|
      cached = HalCache::Store.fetch(resource_type, record.id)
      if cached
        JSON.parse(cached)
      else
        representer = hal_representer_for(resource_type, record)
        json = representer.to_json
        HalCache::Store.write(resource_type, record.id, json)
        JSON.parse(json)
      end
    end

    collection = {
      _type: "#{resource_type}Collection",
      total: total,
      count: elements.size,
      pageSize: per_page,
      offset: page,
      _embedded: { elements: elements }
    }

    render json: collection.to_json, status: :ok
  end

  def hal_representer_for(resource_type, record)
    HalCacheWarmJob::REPRESENTER_MAP[resource_type]
      .constantize
      .new(record, current_user: current_user, embed_links: true)
  end
end
