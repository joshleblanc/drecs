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
      SYSTEMS[name] = {
        components: filter,
        block: blk,
      }
    end

    def component(name, **defaults, &blk)
      COMPONENTS[name] = {}
      COMPONENTS[name].merge! defaults
    end

    def entity(name, *components, **overrides)
      ENTITIES[name] = {}
      components.each { |c| ENTITIES[name][c] = {} }
      overrides.each { |k, v| ENTITIES[name][k] = v }
    end
  end

  def add_component(entity, component, **overrides)
    c = entity[component] || COMPONENTS[component]

    entity[component] = c.merge(overrides)
  end

  def remove_component(entity, component)
    entity.as_hash.delete component
  end

  def has_components?(entity, *components)
    keys = entity.as_hash.keys
    components.all? do |c|
      keys.include? c
    end
  end

  def new_entity(name, **overrides)
    $args.state.new_entity(name) do |e|
      ENTITIES[name].each do |k, v|
        add_component(e, k, v.merge(overrides[k] || {}))
      end
    end
  end

  def process_systems(args)
    args.state.systems.each do |system|
      s = SYSTEMS[system]
      s = SYSTEMS["#{system}_system".to_sym] unless s

      next unless s

      system_entities = args.state.entities.select do |e|
        next unless has_components?(e, s.components)
      end

      instance_exec(system_entities, args, &s.block)
    end
  end
end
