module Drecs
  class EntityManager
    def initialize
      @next_id = 0
      @freed_ids = []
    end

    def create_entity
      if @freed_ids.any?
        @freed_ids.pop
      else
        @next_id += 1
        @next_id - 1
      end
    end

    def destroy_entity(id)
      @freed_ids.push(id)
    end
  end

  class Archetype
    attr_reader :component_classes, :component_stores, :entity_ids

    def initialize(component_classes)
      # The signature of the archetype, always sorted for consistent lookup.
      @component_classes = component_classes.sort_by(&:name)
      @component_stores = @component_classes.to_h { |klass| [klass, []] }
      @entity_ids = [] # Maps row index to the entity ID at that row
    end

    # Adds an entity's data to this archetype.
    def add(entity_id, components_hash)
      @component_classes.each do |klass|
        @component_stores[klass] << components_hash[klass]
      end
      @entity_ids << entity_id
      @entity_ids.length - 1 # Return the new row index
    end

    # Removes an entity from a specific row. This is a critical performance path.
    def remove(row_index)
      last_entity_id = @entity_ids.last
      
      # To avoid leaving a hole, we move the *last* element into the deleted slot.
      if @entity_ids.length > 1 && row_index != @entity_ids.length - 1
        # Move data from the last row into the now-vacant row
        @component_classes.each do |klass|
          @component_stores[klass][row_index] = @component_stores[klass].last
        end
        @entity_ids[row_index] = last_entity_id
      end

      # Pop the last (now redundant) element off all arrays.
      @component_classes.each { |klass| @component_stores[klass].pop }
      @entity_ids.pop

      # Return the ID of the entity that was moved so the World can update its location.
      # If no entity was moved (because we removed the last one), this is nil.
      last_entity_id if @entity_ids.length > row_index
    end
  end

  class World
    def initialize
      @entity_manager = EntityManager.new
      @systems = []

      # The core lookup tables
      @archetypes = {} # { [Component Classes FrozenSet] => Archetype }
      @entity_locations = {} # { entity_id => { archetype:, row: } }
    end

    # Creates a new entity with the given components.
    def spawn(*components)
      entity_id = @entity_manager.create_entity
      components_hash = components.to_h { |c| [c.class, c] }
      
      # Find or create the correct archetype
      signature = components_hash.keys.sort_by(&:name)
      archetype = find_or_create_archetype(signature)

      # Add the entity to the archetype and record its location
      row = archetype.add(entity_id, components_hash)
      @entity_locations[entity_id] = { archetype: archetype, row: row }
      
      entity_id
    end
    
    # Adds a component to an existing entity. This triggers a move between archetypes.
    def add_component(entity_id, component)
      location = @entity_locations[entity_id]
      return unless location # Entity doesn't exist

      old_archetype = location[:archetype]
      
      # 1. Gather all current components for the entity
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][location[:row]]]
      end
      all_components[component.class] = component # Add the new one
      
      # 2. Find the new archetype based on the new signature
      new_signature = all_components.keys.sort_by(&:name)
      new_archetype = find_or_create_archetype(new_signature)
      
      # 3. Add entity data to the new archetype
      new_row = new_archetype.add(entity_id, all_components)
      @entity_locations[entity_id] = { archetype: new_archetype, row: new_row }

      # 4. Remove the entity from the old archetype, filling the hole
      moved_entity_id = old_archetype.remove(location[:row])

      # 5. If another entity was moved to fill the hole, update its location
      if moved_entity_id && moved_entity_id != entity_id
        @entity_locations[moved_entity_id][:row] = location[:row]
      end
    end

    # The query interface for systems.
    def query(*component_classes)
      # Find all archetypes that contain *at least* the required components
      @archetypes.each_value do |archetype|
        next unless (component_classes - archetype.component_classes).empty?
        
        # Yield the raw component arrays for high-speed iteration
        stores = component_classes.map { |klass| archetype.component_stores[klass] }
        yield(*stores) if stores.first && !stores.first.empty?
      end
    end
    
    def register_system(system)
      @systems << system
    end

    # The main game loop tick.
    def tick
      @systems.each { |s| s.update(self) }
    end

    private

    def find_or_create_archetype(signature)
      @archetypes[signature] ||= Archetype.new(signature)
    end
  end
end
