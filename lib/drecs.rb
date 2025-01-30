# frozen_string_literal: true

module Drecs
  VERSION = "0.1.0"

  class Error < StandardError; end

  SYSTEMS = {}
  ENTITIES = {}
  COMPONENTS = {}
  WORLDS = {}
  COMPONENT_BITS = {}
  CONFIG = {
    next_component_bit: 0
  }


  class Ecs
    attr_reader :name 

    def name(name = nil)
      if name 
        @name = name 
      else
        @name
      end
    end
  end

  class Entity < Ecs
    attr_reader :components, :relationships
    attr_accessor :world

    def initialize
      @components = {}
      @relationships = []
    end

    def as(name = nil)
      if name 
        @alias = name 
      else
        @alias
      end
    end

    def relationship(key, entity)
      @relationships << { key => entity }
    end

    def component(key, data = nil)
      @components[key] = data

      define_singleton_method(key) { @components[key] }
    end

    def has_components?(*components)
      components.all? { |c| @components.keys.include?(c) }
    end

    def has?(*stuff)
      keys = relationships.map { |r| r.keys.first }
      stuff.all? { |s| components.keys.include?(s) || keys.include?(s) }
    end
  end
  
  class Query 
    def initialize(arr)
      @arr = arr 
      @operations = []
    end

    def with(*components)
      @operations << Proc.new do |entities| 
        entities.select { _1.has?(*components) } 
      end
      self
    end

    def without(*components)
      @operations << Proc.new do |entities| 
        entities.reject { _1.has?(*components) } 
      end
      self
    end

    def where(**query)
      @operations << Proc.new do |entities|
        entities.select do |entity|
          query.all? do |key, value|
            matches_query?(entity.send(key), value) if entity.respond_to?(key)
          end
        end
      end
      self
    end

    def execute 
      @operations.inject(@arr) do |entities, operation|
        operation.call(entities)
      end
    end

    private

    def matches_query?(field_value, query_value)
      case query_value
      when Range
        field_value.is_a?(Numeric) && query_value.include?(field_value)
      when Array
        query_value.include?(field_value)
      when Hash
        return false unless field_value.is_a?(Hash)
        query_value.all? do |k, v|
          matches_query?(field_value[k], v)
        end
      when Proc
        query_value.call(field_value)
      else
        field_value == query_value
      end
    end
  end

  class System < Ecs
    attr_reader :query, :callback    
    attr_accessor :world

    def initialize(name = nil)
      @name = name 
      @disabled = false
    end

    def disable!
      @disabled = true
    end

    def enable!
      @disabled = false
    end

    def disabled?
      @disabled
    end

    def query(&blk) 
      if blk 
        @query = blk
      else
        @query
      end
    end

    def callback(&blk)
      if blk
        @callback = blk
      else
        @callback
      end
    end
  end

  class World < Ecs
    attr_gtk
    attr_reader :entities, :systems

    def initialize
      @entities = []
      @systems = []

      @debug = debug
    end

    def query(&blk)
      Query.new(@entities).instance_eval(&blk).execute
    end

    def _tick(system, args)
      entities = if system.query 
        query(&system.query)
      else
        @entities
      end
      system.instance_exec(entities, &system.callback)
    end

    def tick(args)
      self.args = args
      @systems.reject(&:disabled?).each do |system|
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
    
    def entity(name = nil, &blk)
      if name 
        @entities.find { _1.name == name }
      else 
        entity = Entity.new
        entity.tap { _1.instance_eval(&blk) } if blk
        entity.world = self
        if entity.as 
          define_singleton_method(entity.as) { entity }        
        end
        @entities << entity
        p "Added entitty #{self}"
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
