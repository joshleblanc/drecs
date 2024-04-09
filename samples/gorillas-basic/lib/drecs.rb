# frozen_string_literal: true

require_relative "drecs/version"

module Drecs
  class Error < StandardError; end

  SYSTEMS = {}
  ENTITIES = {}
  COMPONENTS = {}
  WORLDS = {}

  def self.included(base)
    base.extend(ClassMethods)
  end

  module ClassMethods
    def system(name, *filter, &blk)
      Drecs::SYSTEMS[name] = {
        components: filter,
        block: blk,
      }
    end

    def component(name, **defaults, &blk)
      Drecs::COMPONENTS[name] = {}.tap do |klass|
        klass.class_eval(&blk) if blk
      end
      Drecs::COMPONENTS[name].merge! defaults
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

  def add_component(entity, component, **overrides)
    c = entity[component] || Drecs::COMPONENTS[component]

    entity[component] = c.merge(overrides)
    entity.components << component unless entity.components.include? component
  end

  def remove_component(entity, component)
    entity[component] = nil
    entity.components.delete(component)
  end

  def has_components?(entity, *components)
    components.all? do |c|
      entity.components.include? c
    end
  end

  def create_entity(name, **overrides)
    unless Drecs::ENTITIES[name]
      puts "No entity named #{name}"
      return nil
    end

    $args.state.entities ||= []

    state_alias = overrides.delete(:as)
    entity = $args.state.new_entity(name) do |e|
      e.alias = state_alias
      e.components = []

      Drecs::ENTITIES[name].each do |k, v|
        add_component(e, k, v.merge(overrides[k] || {}))
      end
    end
    $args.state.entities << entity
    $args.state[state_alias.to_sym] = entity if state_alias

    entity
  end

  def delete_entity(entity)
    $args.state.entities.delete(entity)
    $args.state[entity.alias] = nil if entity.alias
  end

  def add_system(system)
    $args.state.systems ||= []
    $args.state.systems << system unless $args.state.systems.include?(system)
  end

  def remove_system(system)
    $args.state.systems.delete(system)
  end

  def set_world(name)
    world = Drecs::WORLDS[name]

    world.entities.each do |entity|
      if entity.is_a? Hash 
        create_entity
      else 
        create_entity(entity)
      end
      
    end
    $args.state.world = 
  end

  def process_systems(args)
    return unless args.state.world

    args.state.world.systems ||= []
    args.state.world.entities ||= []

    args.state.world.systems.each do |system|
      s = Drecs::SYSTEMS[system]
      s = Drecs::SYSTEMS["#{system}_system".to_sym] unless s

      next unless s

      system_entities = args.state.entities.select do |e|
        has_components?(e, *s.components)
      end

      args.tap do |klass|
        klass.instance_exec(system_entities, &s.block)
      end
    end
  end

  module Main
    include Drecs
    include Drecs::ClassMethods
  end
end
