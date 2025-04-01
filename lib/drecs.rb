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

  # Base class for all components
  class Component
    # Class methods for Component subclasses
    class << self
      attr_reader :attributes, :component_name
      
      def inherited(subclass)
        subclass.instance_variable_set(:@attributes, [])
        subclass.instance_variable_set(:@component_name, subclass.name.split('::').last.to_sym)
      end
      
      # Define attributes for the component
      def attr(*names)
        names.each do |name|
          @attributes ||= []
          @attributes << name
          
          # Define getter and setter methods
          define_method(name) do
            @data[name]
          end
          
          define_method("#{name}=") do |value|
            @data[name] = value
          end
        end
      end
    end
    
    attr_reader :data, :entity
    
    def initialize(entity, **attributes)
      @entity = entity
      @data = {}
      
      # Set initial values for attributes
      attributes.each do |key, value|
        if self.class.attributes&.include?(key)
          @data[key] = value
        end
      end
    end
    
    # Allow direct access to data
    def [](key)
      @data[key]
    end
    
    def []=(key, value)
      @data[key] = value
    end
  end

  class Entity
    include DSL

    # Component class storage at the class level
    class << self
      attr_reader :component_classes
      
      def inherited(subclass)
        subclass.instance_variable_set(:@component_classes, {})
      end
      
      # Define component declarations at the class level
      def component(component_class, **defaults)
        @component_classes ||= {}
        @component_classes[component_class.component_name] = {
          class: component_class,
          defaults: defaults
        }
        
        # Define a component accessor method
        define_method(component_class.component_name) do
          @components[component_class.component_name]
        end
      end
    end

    attr_reader :components, :relationships
    attr_accessor :world, :_id, :archetypes, :component_mask

    prop :name
    prop :as

    def initialize
      @components = {}
      @archetypes = []
      @component_mask = 0
      
      # Add any components defined at the class level
      self.class.component_classes&.each do |name, config|
        component_class = config[:class]
        defaults = config[:defaults]
        add_component(component_class, **defaults)
      end
    end
    
    def [](key)
      @components[key]
    end

    def add(...)
      add_component(...)
    end

    def add_component(component_class, **data)
      component_name = component_class.component_name
      old_mask = @component_mask
      
      # Create the component instance and store it
      component_instance = component_class.new(self, **data)
      @components[component_name] = component_instance
      @component_mask |= world&.register_component(component_name) || 0
      
      if world && old_mask != @component_mask
        world.notify_component_change(self, old_mask, @component_mask)
      end
      
      component_instance
    end

    def remove(key)
      old_mask = @component_mask
      @components.delete(key)
      @component_mask &= ~(world&.register_component(key) || 0)
      
      if world && old_mask != @component_mask
        world.notify_component_change(self, old_mask, @component_mask)
      end
    end

    # For backward compatibility
    def component(key, data = nil)
      if key.is_a?(Class) && key < Component
        # Handle class-based component
        add_component(key, **(data || {}))
      else
        # Legacy string/symbol key approach
        old_mask = @component_mask
        @components[key] = data
        @component_mask |= world&.register_component(key) || 0
        
        if world && old_mask != @component_mask
          world.notify_component_change(self, old_mask, @component_mask)
        end
        
        define_singleton_method(key) { @components[key] } unless respond_to?(key)
      end
    end

    def has_components?(mask)
      (component_mask & mask) == mask
    end

    def draw(&blk) 
      @draw_block = blk
    end

    def draw_override(ffi_draw)
      instance_exec(ffi_draw, &@draw_block) if @draw_block
    end
  end
  
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

    def invalidate_cache 
      @committed = false
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

  class System
    include DSL 

    # Class methods for System subclasses
    class << self
      attr_reader :required_components, :excluded_components
      
      def inherited(subclass)
        subclass.instance_variable_set(:@required_components, [])
        subclass.instance_variable_set(:@excluded_components, [])
      end
      
      # Define required components for the system
      def with(*components)
        @required_components ||= []
        @required_components.push(*components)
      end
      
      # Define excluded components for the system
      def without(*components)
        @excluded_components ||= []
        @excluded_components.push(*components)
      end
    end

    attr_reader :query, :callback    
    attr_accessor :world

    def initialize(name = nil)
      @name = name 
      @disabled = false
      
      # Set up the query based on class-defined components if available
      if self.class.required_components.any? || self.class.excluded_components.any?
        @query = proc do
          with(*self.class.required_components) if self.class.required_components.any?
          without(*self.class.excluded_components) if self.class.excluded_components.any?
        end
      end
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
    
    # Process all matching entities
    def process(&block)
      @callback = block if block_given?
    end
    
    # Execute this system (called by the world)
    def execute(args = nil)
      return if disabled?
      
      entities = if query 
        world.query(&query)
      elsif self.class.required_components.any? || self.class.excluded_components.any?
        world.query do 
          with(*self.class.required_components) if self.class.required_components.any?
          without(*self.class.excluded_components) if self.class.excluded_components.any?
        end
      else
        nil
      end
      
      if entities.nil?
        self.instance_exec(&@callback) if @callback
      else 
        entities.each do |entity|
          self.instance_exec(entity, &@callback) if @callback
        end
      end
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

    def _tick(system, args)
      if system.respond_to?(:execute)
        # New class-based system
        system.execute(args)
      else
        # Legacy system with callback
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
        # Check if name is a System class
        if name.is_a?(Class) && name < System
          system = name.new
          system.world = self
          @systems << system
          return system
        else
          # Legacy approach with instance_eval
          system = System.new.tap { _1.instance_eval(&blk) }
          system.world = self
          @systems << system
          system
        end
      end
    end

    # Add a system class instance
    def add_system(system_instance)
      system_instance.world = self
      @systems << system_instance
      system_instance
    end

    def <<(obj) 
      entity do 
        obj.each do |k, v|
          if k == :draw 
            draw(&v)
          else 
            component(k, v)
          end
        end
      end
    end
    
    # Create or retrieve an entity
    def entity(name = nil, &blk)
      if name.is_a?(Class) && name < Entity
        # Create an instance of the Entity subclass
        entity = name.new
        entity.world = self
        entity._id = GTK.create_uuid
        @entities << entity
        notify_component_change(entity, 0, entity.component_mask)
        return entity
      elsif name 
        # Find an entity by name
        @entities.find { _1.name == name }
      else 
        # Legacy approach with instance_eval
        entity = Entity.new
        entity.world = self
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

  def self.world(&blk)
    World.new.tap do |world|
      world.instance_eval(&blk) if blk
    end
  end
end
