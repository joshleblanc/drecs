module Drecs 
  class System
    include DSL 

    # Class methods for System subclasses
    class << self
      def required_components 
        @required_components ||= []
      end

      def excluded_components 
        @excluded_components ||= []
      end
      
      def inherited(subclass)
        subclass.instance_variable_set(:@required_components, [])
        subclass.instance_variable_set(:@excluded_components, [])
      end
      
      # Define required components for the system
      def with(*components)
        required_components.push(*components)
      end
      
      # Define excluded components for the system
      def without(*components)
        excluded_components.push(*components)
      end
    end

    attr_reader :query, :callback    
    attr_accessor :world

    def initialize(name = nil, world:)
      @name = name 
      @disabled = false
      @query = Query.new
      @world = world

      self.class.required_components.each do |component|
        @query.with(component)
      end

      self.class.excluded_components.each do |component|
        @query.without(component)
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

    def raw(entities); end 
    def each(entity); end
    
    # Execute this system (called by the world)
    def execute(args = nil)
      return if disabled?

      
      entities = if query 
        query
      elsif self.class.required_components.any? || self.class.excluded_components.any?
        world.query do 
          with(*self.class.required_components) if self.class.required_components.any?
          without(*self.class.excluded_components) if self.class.excluded_components.any?
        end
      else
        nil
      end

      p entities
      
      if entities.nil?
        self.instance_exec(&@callback) if @callback
      else 
        raw(entities)
        entities.each do |entity|
          each(entity)
        end
      end
    end
  end
end