module Drecs 
  class Entity
    include DSL

    attr_reader :components, :relationships
    attr_accessor :world, :_id, :archetypes, :component_mask

    prop :name
    prop :as

    def initialize(world:, **overrides)
      @components = {}
      @archetypes = []
      @component_mask = 0
      @world = world
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

    def method_missing(name, *args, &blk)
      if name.to_s.end_with?('=')
        component(name.to_s[0..-2], *args, &blk)
      elsif respond_to?(name)
        send(name, *args, &blk)
      else
        nil
      end
    end

    # For backward compatibility
    def component(key, data = nil)
      old_mask = @component_mask
      @components[key] = data
      @component_mask |= world&.register_component(key) || 0
      
      if world && old_mask != @component_mask
        world.notify_component_change(self, old_mask, @component_mask)
      end
      
      define_singleton_method(key) { @components[key] } unless respond_to?(key)
      define_singleton_method("#{key}=", ->(value) { @components[key] = value }) unless respond_to?("#{key}=")
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