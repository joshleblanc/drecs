module Drecs 
  class Entity
    include DSL

    # Component class storage at the class level
    class << self
      attr_reader :component_classes
      
      def inherited(subclass)
        subclass.instance_variable_set(:@component_classes, {})
      end
      
      # Define component declarations at the class level
      def component(component_class, **defaults)
        @component_classes ||= {}
        @component_classes[component_class.component_name] = {
          class: component_class,
          defaults: defaults
        }
        
        define_method(component_class.component_name.downcase) do
          @components[component_class.component_name]
        end

        define_method("#{component_class.component_name.downcase}=") do |new_val|
          @components[component_class.component_name] = new_value
        end
      end
    end

    attr_reader :components, :relationships
    attr_accessor :world, :_id, :archetypes, :component_mask

    prop :name
    prop :as

    def initialize(world:, **overrides)
      @components = {}
      @archetypes = []
      @component_mask = 0
      @world = world
      
      # Add any components defined at the class level
      self.class.component_classes&.each do |name, config|
        component_class = config[:class]
        defaults = overrides[component_class.component_name.to_sym] || config[:defaults]
        add_component(component_class, **defaults)
      end
    end
    
    def [](key)
      @components[key]
    end

    def add(...)
      add_component(...)
    end

    def add_component(component_class, **data)
      component_name = component_class.component_name
      old_mask = @component_mask
      
      # Create the component instance and store it
      component_instance = component_class.new(self, **data)
      @components[component_name] = component_instance
      @component_mask |= world&.register_component(component_name) || 0
      
      if world && old_mask != @component_mask
        world.notify_component_change(self, old_mask, @component_mask)
      end
      
      component_instance
    end

    def remove(key)
      old_mask = @component_mask
      @components.delete(key)
      @component_mask &= ~(world&.register_component(key) || 0)
      
      if world && old_mask != @component_mask
        world.notify_component_change(self, old_mask, @component_mask)
      end
    end

    # For backward compatibility
    def component(key, data = nil)
      if key.is_a?(Class) && key < Component
        # Handle class-based component
        add_component(key, **(data || {}))
      else
        # Legacy string/symbol key approach
        old_mask = @component_mask
        @components[key] = data
        @component_mask |= world&.register_component(key) || 0
        
        if world && old_mask != @component_mask
          world.notify_component_change(self, old_mask, @component_mask)
        end
        
        define_singleton_method(key) { @components[key] } unless respond_to?(key)
      end
    end

    def has_components?(mask)
      (component_mask & mask) == mask
    end

    def draw(&blk) 
      @draw_block = blk
    end

    def draw_override(ffi_draw)
      instance_exec(ffi_draw, &@draw_block) if @draw_block
    end
  end
end