module Drecs
  class Component
    # Class methods for Component subclasses
    class << self
      attr_reader :attributes, :component_name
      
      def inherited(subclass)
        subclass.instance_variable_set(:@attributes, [])
        subclass.instance_variable_set(:@component_name, subclass.name.split('::').last.to_sym)
      end
      
      # Define attributes for the component
      def attr(*names)
        names.each do |name|
          @attributes ||= []
          @attributes << name
          
          # Define getter and setter methods
          define_method(name) do
            @data[name]
          end
          
          define_method("#{name}=") do |value|
            @data[name] = value
          end
        end
      end
    end
    
    attr_reader :data, :entity
    
    def initialize(entity, **attributes)
      @entity = entity
      @data = {}
      
      # Set initial values for attributes
      attributes.each do |key, value|
        if self.class.attributes&.include?(key)
          @data[key] = value
        end
      end
    end
    
    # Allow direct access to data
    def [](key)
      @data[key]
    end
    
    def []=(key, value)
      @data[key] = value
    end
  end
end