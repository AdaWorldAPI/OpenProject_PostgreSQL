# frozen_string_literal: true

module HalCache
  # Mixin for ActiveRecord models. Include in any model whose changes
  # should invalidate the HAL cache.
  #
  # Usage:
  #   class WorkPackage < ApplicationRecord
  #     include HalCache::Invalidator
  #
  #     hal_cache_as "WorkPackage"
  #     hal_cache_cascades_to :project,   as: "Project"
  #     hal_cache_cascades_to :parent,    as: "WorkPackage"
  #     hal_cache_cascades_to :children,  as: "WorkPackage"
  #   end
  #
  module Invalidator
    extend ActiveSupport::Concern

    included do
      after_commit :_hal_cache_invalidate_self, on: [:update, :destroy]
      after_commit :_hal_cache_warm_self, on: [:create, :update]

      class_attribute :_hal_cache_resource_type, default: name
      class_attribute :_hal_cache_cascades, default: []
    end

    class_methods do
      def hal_cache_as(resource_type)
        self._hal_cache_resource_type = resource_type
      end

      def hal_cache_cascades_to(association, as:)
        self._hal_cache_cascades += [{ association: association, resource_type: as }]
      end
    end

    private

    def _hal_cache_invalidate_self
      HalCache::Store.invalidate(_hal_cache_resource_type, id)
      _hal_cache_invalidate_cascades
    end

    def _hal_cache_warm_self
      HalCacheWarmJob.perform_async(_hal_cache_resource_type, id)
    end

    def _hal_cache_invalidate_cascades
      _hal_cache_cascades.each do |cascade|
        assoc = cascade[:association]
        type  = cascade[:resource_type]

        related = send(assoc)
        next unless related

        ids = related.respond_to?(:pluck) ? related.pluck(:id) : [related.id]
        HalCache::Store.invalidate_all(type, ids)
        ids.each { |rid| HalCacheWarmJob.perform_async(type, rid) }
      end
    end
  end
end
