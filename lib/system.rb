module Drecs 
  class System
    include DSL 

    # Class methods for System subclasses
    class << self
      attr_reader :required_components, :excluded_components
      
      def inherited(subclass)
        subclass.instance_variable_set(:@required_components, [])
        subclass.instance_variable_set(:@excluded_components, [])
      end
      
      # Define required components for the system
      def with(*components)
        @required_components ||= []
        @required_components.push(*components)
      end
      
      # Define excluded components for the system
      def without(*components)
        @excluded_components ||= []
        @excluded_components.push(*components)
      end
    end

    attr_reader :query, :callback    
    attr_accessor :world

    def initialize(name = nil)
      @name = name 
      @disabled = false
      
      # Set up the query based on class-defined components if available
      if self.class.required_components.any? || self.class.excluded_components.any?
        @query = proc do
          with(*self.class.required_components) if self.class.required_components.any?
          without(*self.class.excluded_components) if self.class.excluded_components.any?
        end
      end
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
    
    # Process all matching entities
    def process(&block)
      @callback = block if block_given?
    end
    
    # Execute this system (called by the world)
    def execute(args = nil)
      return if disabled?
      
      entities = if query 
        world.query(&query)
      elsif self.class.required_components.any? || self.class.excluded_components.any?
        world.query do 
          with(*self.class.required_components) if self.class.required_components.any?
          without(*self.class.excluded_components) if self.class.excluded_components.any?
        end
      else
        nil
      end
      
      if entities.nil?
        self.instance_exec(&@callback) if @callback
      else 
        entities.each do |entity|
          self.instance_exec(entity, &@callback) if @callback
        end
      end
    end
  end
end