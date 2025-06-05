module Drecs
  class Query 
    include DSL 

    attr_accessor :world
    attr_reader :has_archetype, :not_archetype

    prop :as
    prop :name

    def initialize
      clear
    end

    def clear 
      @has = []
      @not = []
      @mask_cache = {}
      @has_archetype = nil
      @not_archetype = nil
      
      @entity_cache = []
      
      @committed = false
    end

    def length 
      @entity_cache.length
    end

    def count 
      @entity_cache.count
    end

    def react_to_mask_change(old_mask, new_mask, entity)
      if (@has_archetype & new_mask) == @has_archetype && (@has_archetype & old_mask) != @has_archetype
        @entity_cache << entity unless @entity_cache.include?(entity)
      elsif (@has_archetype & old_mask) == @has_archetype && (@has_archetype & new_mask) != @has_archetype
        @entity_cache.delete(entity)
      end

      if @not_archetype
        if (@not_archetype & new_mask) == @not_archetype
          @entity_cache.delete(entity)
        elsif (@not_archetype & old_mask) == @not_archetype && (@not_archetype & new_mask) != @not_archetype
          @entity_cache << entity unless @entity_cache.include?(entity)
        end
      end
    end

    def affected_by_mask_change?(old_mask, new_mask)
      if @has_archetype
        return true if (old_mask & new_mask) != (old_mask & @has_archetype)
      end

      if @not_archetype
        return true if (old_mask & new_mask) != (old_mask & @not_archetype)
      end

      false
    end

    def with(*components)
      return if @committed 
      
      # Handle both symbol/string components and class-based components
      processed_components = components.map do |comp|
        if comp.is_a?(Class) && comp < Component
          comp.component_name
        else
          comp
        end
      end
      
      @has.push *processed_components
      @has_archetype = @mask_cache[@has] ||= Array.map(@has) { |c| world.register_component(c) }.reduce(:|)

      @has_archetype
    end

    def without(*components)
      return if @committed
      
      # Handle both symbol/string components and class-based components
      processed_components = components.map do |comp|
        if comp.is_a?(Class) && comp < Component
          comp.component_name
        else
          comp
        end
      end

      @not.push *processed_components
      @not_archetype = @mask_cache[@not] ||= Array.map(@not) { |c| world.register_component(c) }.reduce(:|)
    end

    def commit 
      return self if @committed

      @committed = true

      with = if @has_archetype
        world.entities.select { |e| e.has_components?(@has_archetype) }
      else 
        []
      end
      
      without = if @not_archetype
        world.entities.select { |e| e.has_components?(@not_archetype) }
      else 
        []
      end

      @entity_cache = with - without

      self
    end

    def invalidate_cache 
      @committed = false
    end

    def each(&blk)
      Array.each(@entity_cache, &blk)
    end

    def find(&blk)
      @entity_cache.find(&blk)
    end

    def raw(&blk)
      blk.call(@entity_cache)
    end

    def to_a 
      @entity_cache
    end

    # Process entities in concurrent groups of specified size
    # Each entity is processed in a separate thread
    # @param batch_size [Integer] Number of entities to process concurrently (default: 4)
    # @param &blk [Block] The block to execute for each entity
    # @return [self]
    def job(batch_size = 4, &blk)
      return unless block_given?
      
      # Process entities in batches
      i = 0
      while i < @entity_cache.length
        # Process a batch of up to batch_size entities
        j = 0
        
        # Start worker threads for each entity in the batch
        while j < batch_size
          Worker.run(@entity_cache[i + j], &blk)
          j += 1
        end
        
        Worker.wait_all
        
        # Move to the next batch
        i += batch_size
      end
      
      self
    end
  end
end