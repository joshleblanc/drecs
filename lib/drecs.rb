# frozen_string_literal: true
module Drecs
  VERSION = "0.1.0"

  class Error < StandardError; end

  module DSL
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods 
      def prop(name)
        define_method(name) do |value = nil, &block|
          if block_given?
            instance_variable_set("@#{name}", block)
          elsif !value.nil?
            instance_variable_set("@#{name}", value)
          else
            instance_variable_get("@#{name}")
          end
        end
      end
    end
  end


  class Entity
    include DSL

    attr_reader :components, :relationships
    attr_accessor :world, :_id, :archetypes, :component_mask

    prop :name
    prop :as

    def initialize
      @components = {}
      @archetypes = []
      @component_mask = 0
    end
    
    def [](key)
      @components[key]
    end

    def add(...)
      component(...)
    end

    def component(key, data = nil)
      @components[key] = data
      @component_mask |= world.register_component(key)
      define_singleton_method(key) { @components[key] }
    end

    def has_components?(mask)
      (component_mask & mask) == mask
    end

    def generate_archetypes!
      @archetypes = []
      current_mask = @component_mask
      
      while current_mask != 0
        @archetypes << current_mask
        current_mask = (current_mask - 1) & @component_mask
      end
    end

    def draw(&blk) 
      @draw_block = blk
    end

    def draw_override(ffi_draw)
      @draw_block.call(ffi_draw) if @draw_block
    end
  end
  
  class Query 
    attr_accessor :world
    attr_reader :has_archetype, :not_archetype

    def initialize
      @has = []
      @not = []
      @mask_cache = {}
      @has_archetype = nil
      @not_archetype = nil
      
      @entity_cache = []
      
      @committed = false
    end

    def with(*components)
      return if @committed 

      @has.push *components
      @has_archetype = @mask_cache[@has] ||= Array.map(@has) { |c| world.register_component(c) }.reduce(:|)
    end

    def without(*components)
      return if @committed

      @not.push *components
      @not_archetype = @mask_cache[@not] ||= Array.map(@not) { |c| world.register_component(c) }.reduce(:|)
    end

    def commit 
      existing_query = world.queries.find { _1.has_archetype == @has_archetype && _1.not_archetype == @not_archetype } 
      
      return existing_query if existing_query

      @committed = true

      with = if @has_archetype
        Array.select(world.entities) { |e| e.has_components?(@has_archetype) }
      else 
        []
      end
      
      without = if @not_archetype
        Array.select(world.entities) { |e| e.has_components?(@not_archetype) }
      else 
        []
      end

      @entity_cache = with - without

      self
    end

    def each(&blk)
      Array.each(@entity_cache, &blk)
    end

    def raw(&blk)
      blk.call(@entity_cache)
    end

    def to_a 
      @entity_cache
    end
  end

  class System
    include DSL 

    attr_reader :query, :callback    
    attr_accessor :world

    def initialize(name = nil)
      @name = name 
      @disabled = false
    end

    prop :name
    prop :callback
    prop :query

    def disable!
      @disabled = true
    end

    def enable!
      @disabled = false
    end

    def disabled?
      @disabled
    end
  end

  class World
    include DSL 

    COMPONENT_BITS = {}

    attr_gtk
    attr_reader :entities, :systems, :archetypes, :queries

    prop :name

    def initialize
      @entities = []
      @systems = []
      @queries = []

      @component_bits = {}
      @next_component_bit = 0
      @component_map = {}
      
      @archetypes = {}

      @debug = debug
    end

    def register_component(name)
      return @component_bits[name] if @component_bits[name]
      
      bit = @next_component_bit
      @component_bits[name] = 1 << bit
      @component_map[1 << bit] = name
      @next_component_bit += 1
      
      @component_bits[name]
    end

    def query(name = nil, &blk)
      if name 
        @queries.find { _1.name == name }
      else 
        query = Query.new.tap do
          _1.world = self
          _1.instance_eval(&blk) if blk
        end.commit
        @queries << query
        query
      end
    end

    def _tick(system, args)
      entities = if system.query 
        query(&system.query)
      else
        nil
      end
      if entities.nil?
        system.instance_exec(&system.callback)
      else 
        i = 0 
        c = entities.length
        while i < c do
          system.instance_exec(entities[i], &system.callback)
          i += 1
        end
      end
    end

    def tick(args)
      self.args = args
      i = 0
      sl = @systems.length
      while i < sl do 
        unless @systems[i].disabled?
          if @debug 
            b("System: #{@systems[i].name}") do
              _tick(@systems[i], args)
            end
          else
            _tick(@systems[i], args)
          end
        end
        i += 1
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

    def system(name = nil, &blk)
      if name 
        @systems.find { _1.name == name }
      else 
        system = System.new.tap { _1.instance_eval(&blk) }
        system.world = self
        @systems << system
        system
      end
    end

    def cache_archetypes(entity)
      # Generate all possible component combinations this entity matches
      current_mask = entity.component_mask
      while current_mask != 0
        @archetypes[current_mask] ||= []
        @archetypes[current_mask] << entity
        current_mask = (current_mask - 1) & entity.component_mask
      end
    end
    
    def entity(name = nil, &blk)
      if name 
        @entities.find { _1.name == name }
      else 
        entity = Entity.new
        entity.world = self
        entity.tap { _1.instance_eval(&blk) } if blk
        entity._id = GTK.create_uuid
        define_singleton_method(entity.as) { entity } if entity.as          
        @entities << entity
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

  def self.world(&blk)
    World.new.tap do |world|
      world.instance_eval(&blk) if blk
    end
  end
end
