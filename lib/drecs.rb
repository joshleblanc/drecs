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
    attr_accessor :world, :_id

    def initialize
      @components = {}
      @relationships = []
    end

    prop :name
    prop :as
    

    def relationship(key, entity)
      @relationships << { key => entity }
    end

    def [](key)
      @components[key]
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

    attr_gtk
    attr_reader :entities, :systems

    def initialize
      @entities = []
      @systems = []

      @debug = debug

      @query = Query.new(@entities)
    end

    prop :name

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
        entities.each do |entity|
          system.instance_exec(entity, &system.callback)
        end
      end
      
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
        entity._id = GTK.create_uuid
        if entity.as 
          define_singleton_method(entity.as) { entity }        
        end
        @entities << entity
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
