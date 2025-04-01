# frozen_string_literal: true
module Drecs 
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
end

require_relative "world"
require_relative "entity"
require_relative "query"
require_relative "system"
require_relative "component"

module Drecs
  VERSION = "0.1.0"

  class Error < StandardError; end

  # Base class for all components
  

  def self.world(&blk)
    World.new.tap do |world|
      world.instance_eval(&blk) if blk
    end
  end
end
