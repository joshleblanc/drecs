# frozen_string_literal: true

require_relative "drecs/version"

module Drecs
  class Error < StandardError; end

  SYSTEMS = {}
  ENTITIES = {}
  COMPONENTS = {}

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
      Drecs::COMPONENTS[name] = {}
      Drecs::COMPONENTS[name].merge! defaults
    end

    def entity(name, *components, **overrides)
      Drecs::ENTITIES[name] = {}
      components.each { |c| Drecs::ENTITIES[name][c] = {} }
      overrides.each { |k, v| Drecs::ENTITIES[name][k] = v }
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

  def process_systems(args)
    args.state.systems.each do |system|
      s = Drecs::SYSTEMS[system]
      s = Drecs::SYSTEMS["#{system}_system".to_sym] unless s

      next unless s

      system_entities = args.state.entities.select do |e|
        has_components?(e, *s.components)
      end

      instance_exec(system_entities, args, &s.block)
    end
  end
end
