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
    attr_reader :components, :component_mask
    attr_accessor :world

    def initialize
      @components = {}
    end

    def as(name = nil)
      if name 
        @alias = name 
      else
        @alias
      end
    end

    def component(key, data)
      @components[key] = data

      define_singleton_method(key) { @components[key] }
    end

    def has_components?(*components)
      components.all? { |c| @components.keys.include?(c) }
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

    def where(query)
      @operations.push()
      self
    end

    def execute 
      @operations.inject(@arr) do |entities, operation|
        operation.call(entities)
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

    def _tick(system, args)
      entities = if system.query 
        Query.new(@entities).instance_eval(&system.query).execute
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
        entity = Entity.new.tap { _1.instance_eval(&blk) }
        entity.world = self
        if entity.as 
          define_singleton_method(entity.as) { entity }
        end
        @entities << entity
        entity
      end
      
    end
  end

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def system(name, *filter, &blk)
      Drecs::SYSTEMS[name] = {
        components: filter,
        block: blk
      }
    end

    def component(name, **defaults)
      Drecs::COMPONENTS[name] = {}
      Drecs::COMPONENTS[name].merge! defaults
      Drecs::COMPONENT_BITS[name] = 1 << CONFIG[:next_component_bit]
      CONFIG[:next_component_bit] += 1
    end

    def entity(name, *components, **overrides)
      Drecs::ENTITIES[name] = {}
      components.each { |c| Drecs::ENTITIES[name][c] = {} }
      overrides.each { |k, v| Drecs::ENTITIES[name][k] = v }
    end

    def world(&blk)
      World.new.tap do |world|
        world.instance_eval(&blk) if blk
      end
    end
  end

  def b(label = "")
    cur = Time.now
    yield
    $args.outputs.debug << "#{label}: #{((Time.now - cur) / (1/60))}"
    # log "#{label}: #{((Time.now - cur) / (1/60))}"
  end

  def add_component(entity, component, **overrides)
    c = entity[component] || Drecs::COMPONENTS[component]
    entity[component] = c.merge(overrides)
    entity.component_mask ||= 0
    entity.component_mask |= COMPONENT_BITS[component]
  end

  def remove_component(entity, component)
    entity[component] = nil
    entity.component_mask &= ~COMPONENT_BITS[component]
  end

  def has_components?(entity, *components) 
    mask = components.reduce(0) { |acc, c| acc | COMPONENT_BITS[c] }
    (entity.component_mask & mask) == mask
  end

  def create_entity(name, **overrides)
    $args.state.entities ||= []

    state_alias = overrides.delete(:as)

    entity = $args.state.new_entity(name) do |e|
      e.alias = state_alias
      e.component_mask = 0

      Drecs::ENTITIES[name]&.each do |k, v|
        add_component(e, k, v.dup.merge(overrides[k] || {}))
      end
    end

    $args.state.entities << entity
    $args.state[state_alias.to_sym] = entity if state_alias

    entity
  end

  def delete_entity(entity)
    $args.state.as_hash.delete(entity.alias)
    $args.state.entities.delete(entity)
  end

  def add_system(system)
    $args.state.systems ||= []
    $args.state.systems << system unless $args.state.systems.include?(system)
  end

  def remove_system(system)
    $args.state.systems.delete(system)
  end

  def set_world(name)
    if $args.state.entities 
      h = $args.state.as_hash
      $args.state.entities.select { _1.alias }.each { h.delete(_1.alias) }
    end
    $args.state.entities = []
    $args.state.systems = []
    $args.state.active_world = name

    world = Drecs::WORLDS[name]

    Array.each(world.entities) do |entity|
      if entity.is_a? Hash
        entity.each { |k, v| create_entity(k, v)}
      else
        create_entity(entity)
      end
    end

    world.systems.each(&method(:add_system))
  end

  def process_systems(args, debug: false)
    return unless args.state

    args.state.systems ||= []
    args.state.entities ||= []

    Array.each(args.state.systems) do |system|
      if debug
        b("System: #{system}") do 
          process_system(args, system)
        end
      else
        process_system(args, system)
      end
      
    end    
  end

  def process_system(args, system)
    s = Drecs::SYSTEMS[system]
    s ||= Drecs::SYSTEMS[:"#{system}_system"]

    next unless s

    system_entities = if s.components.empty?
      args.state.entities
    else
      Array.select(args.state.entities) do |e|
        has_components?(e, *s.components)
      end
    end

    args.tap do |klass|
      klass.instance_exec(system_entities, &s.block)
    end
  end

  module Main
    include Drecs
    include Drecs::ClassMethods
  end
end
