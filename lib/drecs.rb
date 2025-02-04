# frozen_string_literal: true

$gtk.ffi_misc.gtk_dlopen("flecs")

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
        define_method(name) do |*arr, **hash, &block|
          if block_given?
            instance_variable_set("@#{name}", block)
          elsif !arr.empty? || !hash.empty?
            value = if arr.empty?
              hash
            elsif arr.size == 1
              arr.first
            else 
              arr
            end
            instance_variable_set("@#{name}", value)
          else
            instance_variable_get("@#{name}")
          end
        end
      end
    end
  end
  
  class Component
    MAP = {}
  end


  class Entity
    include DSL

    attr_reader :components, :relationships, :entity
    attr_accessor :world

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
      # component_id = Component::MAP[key]
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

    def register_with_flecs!
      @entity = FFI::Flecs.ecs_set_name(world.world, 0, name)
      components.keys.each do |key|
        Component::MAP[key] ||= FFI::Flecs.ecs_new(world.world)
        FFI::Flecs.ecs_add_id(world.world, @entity, Component::MAP[key])
      end
    end
  end
  
  class Query 
    def initialize(arr)
      @arr = arr 
      @operations = []
    end

    def with(*components)
      @operations << Proc.new do |entities| 
        entities.select { _1.has_components?(*components) } 
      end
      self
    end

    def without(*components)
      @operations << Proc.new do |entities| 
        entities.reject { _1.has_components?(*components) } 
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

    attr_reader :query, :callback, :with   
    attr_accessor :world

    def initialize(name = nil)
      @name = name 
      @disabled = false
      @with = []
    end

    prop :name
    prop :callback
    
    def with(*components) 
      if components.empty?
        @with
      else
        @with = components.map { |c| Component::MAP[c] }
      end
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
  end

  class World
    include DSL 

    attr_gtk
    attr_reader :entities, :systems, :world

    def initialize
      @world = FFI::Flecs.ecs_init

      @entities = []
      @systems = []

      @debug = debug

      @query = Query.new(@entities)
    end

    prop :name

    def _tick(system, args)
      component_ids = system.with
      entities = component_ids.empty? ? nil : []
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
        #FFI::Flecs.ecs_system_init(world)
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
        entity.register_with_flecs!
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
