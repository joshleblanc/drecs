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

    def world(name, systems: [], entities: [])
      Drecs::WORLDS[name] = {}
      Drecs::WORLDS[name].systems = systems
      Drecs::WORLDS[name].entities = entities
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
