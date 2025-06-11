module Drecs 
  class World
    include DSL 

    COMPONENT_BITS = {}

    attr_gtk
    attr_reader :entities, :archetypes, :queries

    prop :name

    def initialize
      @queries = []
      @entities = []

      @component_bits = {}
      @next_component_bit = 0
      @component_map = {}
      
      @archetypes = {}

      @debug = debug

      @tmp_query = Query.new

      @query_cache = {}
      @query_cache_key = []
    end

    def register_component(name)
      return @component_bits[name] if @component_bits[name]
      
      bit = @next_component_bit
      @component_bits[name] = 1 << bit
      @component_map[1 << bit] = name
      @next_component_bit += 1
      
      @component_bits[name]
    end

    def notify_component_change(entity, old_mask, new_mask)
      @queries.each do |query|
        query.react_to_mask_change(old_mask, new_mask, entity)
      end
    end

    def with(*components)
      query do 
        with(*components)
      end
    end

    def without(*components)
      query do 
        without(*components)
      end
    end

    def query(name = nil, &blk)
      if name
        @queries.find { _1.name == name }
      else
        @tmp_query.clear
        @tmp_query.world = self
        @tmp_query.instance_eval(&blk) if blk
        
        # Create a hash key from component combinations
        @query_cache_key[0] = @tmp_query.has_archetype
        @query_cache_key[1] = @tmp_query.not_archetype
        
        query_key = [@tmp_query.has_archetype, @tmp_query.not_archetype]

        
        # Check cache first
        cached_query = @query_cache[query_key]
        return cached_query if cached_query
        
        # Commit and cache the query
        query = @tmp_query.commit
        if query != @tmp_query
          return query
        else
          query = query.dup
          @queries << query
          @query_cache[query_key] = query

          define_singleton_method(query.as) { query } if query.as && !respond_to?(query.as)

          return query
        end
      end
    end

    def debug(bool = nil) 
      if bool.nil?
        @debug
      elsif bool
        @debug = true
      else
        @debug = false
      end
    end

    def delete(entity)
      entities = if entity.is_a? Entity 
        [entity]
      elsif entity.is_a? Query 
        entity.to_a 
      else
        entity 
      end
      Array.each(entities) do |entity|
        @entities.delete(entity)
        notify_component_change(entity, entity.component_mask, 0)
        self.singleton_class.undef_method(entity.as) if entity.as && self.respond_to?(entity.as)
      end
    end

    def method_missing(method_name, *args, &blk)
      if respond_to?(method_name)
        send(method_name, *args, &blk)
      else
        nil
      end
    end

    def <<(obj) 
      entity do 
        obj.each do |k, v|
          if k == :draw 
            draw(&v)
          elsif k == :as
            as(v)
          elsif k == :name
            name(v)
          else 
            component(k, v)
          end
        end
      end
    end
    
    # Create or retrieve an entity
    def entity(name = nil, overrides = {}, &blk)
      if name 
        # Find an entity by name
        @entities.find { _1.name == name }
      else 
        # Legacy approach with instance_eval
        entity = Entity.new(world: self)
        entity.tap { _1.instance_eval(&blk) } if blk
        entity._id = GTK.create_uuid
        define_singleton_method(entity.as) { entity } if entity.as          
        @entities << entity

        notify_component_change(entity, 0, entity.component_mask)
        entity
      end
    end

    private 

    def b(label = "", allocations: false, &blk)
      cur = Time.now

      if allocations 
        before = {}
        after = {}

        ObjectSpace.count_objects(before)
        
        blk.call if block_given?
        
        ObjectSpace.count_objects(after)

        time_taken = ((Time.now - cur) / (1/60))
        allocs = after.map do |k,v| 
          diff = v - before[k]
          "#{k}:#{diff}" if diff > 0 
        end.compact
        debug_msg = "#{label}: #{'%0.3f' % time_taken }ms #{allocs.join(', ')}"
      else 
        blk.call if block_given?
        debug_msg = "#{label}: #{'%0.3f' % ((Time.now - cur) / (1/60)) }ms"
      end
      $args.outputs.debug << debug_msg
    end
  end
end