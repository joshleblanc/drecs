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
  end
  
  class Query 

    def initialize(arr, world)
      @arr = arr 
      @operations = []
      @world = world
    end

    def with(*components)
      mask = Array.map(components) { |c| @world.register_component(c) }.reduce(:|)
      @operations << Proc.new do |entities| 
        @world.archetypes[mask] || entities.select { |e| e.has_components?(mask) }
      end
      self
    end

    def without(*components)
      mask = Array.map(components) { |c| @world.register_component(c) }.reduce(:|)
      @operations << Proc.new do |entities| 
        entities.reject { |e| e.has_components?(mask) }
      end
      self
    end

    def execute 
      result = @operations.inject(@arr) do |entities, operation|
        operation.call(entities)
      end
      @operations.clear
      result
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
    attr_reader :entities, :systems, :archetypes

    prop :name

    def initialize
      @entities = []
      @systems = []

      @component_bits = {}
      @next_component_bit = 0
      @component_map = {}
      
      @archetypes = {}

      @debug = debug

      @query = Query.new(@entities, self)
    end

    def register_component(name)
      return @component_bits[name] if @component_bits[name]
      
      bit = @next_component_bit
      @component_bits[name] = 1 << bit
      @component_map[1 << bit] = name
      @next_component_bit += 1
      
      @component_bits[name]
    end
  
    def component_name(bit)
      @component_map[bit]
    end

    def query(&blk)
      @query.instance_eval(&blk).execute
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
        Array.each(entities) do |entity|
          system.instance_exec(entity, &system.callback)
        end
      end
    end

    def tick(args)
      self.args = args
      Array.each(@systems.reject(&:disabled?)) do |system|
        if @debug 
          b("System: #{system.name}") do
            _tick(system, args)
          end
        else
          _tick(system, args)
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
        cache_archetypes(entity)
        entity
      end
      
    end

    private 

    def b(label = "")
      cur = Time.now
      yield
      $args.outputs.debug << "#{label}: #{((Time.now - cur) / (1/60))}"
      # log "#{label}: #{((Time.now - cur) / (1/60))}"
    end
  end

  def self.world(&blk)
    World.new.tap do |world|
      world.instance_eval(&blk) if blk
    end
  end
end
