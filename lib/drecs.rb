module Drecs
  module SignatureHelper 
    def normalize_signature(component_classes)
      component_classes.sort_by { |c| c.is_a?(Class) ? c.name : c.to_s }
    end
  end

  class EntityManager
    def initialize
      @next_id = 0
      @freed_ids = nil # Lazily initialized for memory efficiency
    end

    def create_entity
      if @freed_ids && !@freed_ids.empty?
        @freed_ids.pop
      else
        id = @next_id
        @next_id += 1
        id
      end
    end

    def destroy_entity(id)
      @freed_ids ||= []
      @freed_ids << id
    end
  end

  class Archetype
    include SignatureHelper 

    attr_reader :component_classes, :component_stores, :entity_ids

    def initialize(component_classes)
      # The signature of the archetype, always sorted for consistent lookup.
      @component_classes = normalize_signature(component_classes)
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
    # Returns [moved_entity_id, is_empty] where is_empty indicates if the archetype is now empty.
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
      moved_entity = @entity_ids.length > row_index ? last_entity_id : nil
      [moved_entity, @entity_ids.empty?]
    end
  end

  class World
    include SignatureHelper 
    
    def initialize
      @entity_manager = EntityManager.new
      @systems = []

      # The core lookup tables
      @archetypes = {} # { [Component Classes Signature] => Archetype }
      @entity_locations = {} # { entity_id => { archetype:, row: } }
      @signature_cache = {} # Cache for normalized signatures
    end

    # Creates a new entity with the given components.
    def spawn(*components)
      entity_id = @entity_manager.create_entity

      # Handle both struct instances and plain hashes
      components_hash = if components.length == 1 && components[0].is_a?(Hash)
        components[0]
      else
        components.to_h { |c| [c.class, c] }
      end

      # Find or create the correct archetype
      signature = normalize_signature(components_hash.keys)
      archetype = find_or_create_archetype(signature)

      # Add the entity to the archetype and record its location
      row = archetype.add(entity_id, components_hash)
      @entity_locations[entity_id] = { archetype: archetype, row: row }

      entity_id
    end

    def destroy(*entity_ids)
      archetypes_to_cleanup = []

      entity_ids.each do |entity_id|
        location = @entity_locations[entity_id]
        next unless location

        archetype = location[:archetype]

        # Remove the entity and capture if another entity was moved to fill the hole
        removed_row = location[:row]
        moved_entity_id, is_empty = archetype.remove(removed_row)

        # If another entity was moved into this row, update its recorded row index
        if moved_entity_id && moved_entity_id != entity_id
          @entity_locations[moved_entity_id][:row] = removed_row
        end

        # Mark archetype for cleanup if it's now empty
        archetypes_to_cleanup << archetype if is_empty

        @entity_manager.destroy_entity(entity_id)
        @entity_locations.delete(entity_id)
      end

      # Clean up empty archetypes
      cleanup_empty_archetypes(archetypes_to_cleanup)
    end
    
    # Adds a component to an existing entity. This triggers a move between archetypes.
    # For hash components, pass a hash like { position: { x: 0, y: 0 } }
    def add_component(entity_id, component_key_or_component, component_value = nil)
      location = @entity_locations[entity_id]
      return false unless location

      old_archetype = location[:archetype]

      # 1. Gather all current components for the entity
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][location[:row]]]
      end

      # Handle both hash-style and struct-style components
      if component_value.nil?
        if component_key_or_component.is_a?(Hash)
          all_components.merge!(component_key_or_component)
        else
          all_components[component_key_or_component.class] = component_key_or_component
        end
      else
        all_components[component_key_or_component] = component_value
      end

      # 2. Find the new archetype based on the new signature
      new_signature = normalize_signature(all_components.keys)
      new_archetype = find_or_create_archetype(new_signature)

      # 3. Add entity data to the new archetype
      new_row = new_archetype.add(entity_id, all_components)
      @entity_locations[entity_id] = { archetype: new_archetype, row: new_row }

      # 4. Remove the entity from the old archetype, filling the hole
      moved_entity_id, is_empty = old_archetype.remove(location[:row])

      # 5. If another entity was moved to fill the hole, update its location
      if moved_entity_id && moved_entity_id != entity_id
        @entity_locations[moved_entity_id][:row] = location[:row]
      end

      # 6. Clean up old archetype if it's now empty
      cleanup_empty_archetypes([old_archetype]) if is_empty

      true
    end

    # Removes a component from an existing entity. This triggers a move between archetypes.
    def remove_component(entity_id, component_class)
      location = @entity_locations[entity_id]
      return false unless location # Entity doesn't exist

      old_archetype = location[:archetype]

      # 1. Gather all current components for the entity
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][location[:row]]]
      end

      # If the entity doesn't have the component, nothing to do
      return false unless all_components.key?(component_class)

      # 2. Remove the specified component and find/create the new archetype
      all_components.delete(component_class)
      new_signature = normalize_signature(all_components.keys)
      new_archetype = find_or_create_archetype(new_signature)

      # 3. Add entity data to the new archetype
      new_row = new_archetype.add(entity_id, all_components)
      @entity_locations[entity_id] = { archetype: new_archetype, row: new_row }

      # 4. Remove the entity from the old archetype, filling the hole
      moved_entity_id, is_empty = old_archetype.remove(location[:row])

      # 5. If another entity was moved to fill the hole, update its location
      if moved_entity_id && moved_entity_id != entity_id
        @entity_locations[moved_entity_id][:row] = location[:row]
      end

      # 6. Clean up old archetype if it's now empty
      cleanup_empty_archetypes([old_archetype]) if is_empty

      true
    end

    # Check if an entity exists in the world
    def entity_exists?(entity_id)
      @entity_locations.key?(entity_id)
    end

    def has_component?(entity_id, component_class)
      location = @entity_locations[entity_id]
      return false unless location
      location[:archetype].component_classes.include?(component_class)
    end

    # Retrieves a specific component from an entity. Returns nil if entity or component doesn't exist.
    def get_component(entity_id, component_class)
      location = @entity_locations[entity_id]
      return nil unless location

      archetype = location[:archetype]
      return nil unless archetype.component_classes.include?(component_class)

      archetype.component_stores[component_class][location[:row]]
    end

    # Sets multiple components on an entity in a single operation, avoiding multiple archetype migrations.
    # If the entity doesn't exist, returns false. Components can be added or replaced.
    def set_components(entity_id, *components)
      location = @entity_locations[entity_id]
      return false unless location

      old_archetype = location[:archetype]

      # 1. Gather all current components for the entity
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][location[:row]]]
      end

      # 2. Merge in the new components (overwriting any existing ones)
      components.each do |c|
        if c.is_a?(Hash)
          all_components.merge!(c)
        else
          all_components[c.class] = c
        end
      end

      # 3. Find the new archetype based on the new signature
      new_signature = normalize_signature(all_components.keys)
      new_archetype = find_or_create_archetype(new_signature)

      # 4. If we're already in the right archetype, just update components in place
      if old_archetype == new_archetype
        components.each do |c|
          if c.is_a?(Hash)
            c.each { |k, v| new_archetype.component_stores[k][location[:row]] = v }
          else
            new_archetype.component_stores[c.class][location[:row]] = c
          end
        end
        return true
      end

      # 5. Add entity data to the new archetype
      new_row = new_archetype.add(entity_id, all_components)
      @entity_locations[entity_id] = { archetype: new_archetype, row: new_row }

      # 6. Remove the entity from the old archetype, filling the hole
      moved_entity_id, is_empty = old_archetype.remove(location[:row])

      # 7. If another entity was moved to fill the hole, update its location
      if moved_entity_id && moved_entity_id != entity_id
        @entity_locations[moved_entity_id][:row] = location[:row]
      end

      # 8. Clean up old archetype if it's now empty
      cleanup_empty_archetypes([old_archetype]) if is_empty

      true
    end

    # The query interface for systems.
    # Yields entity_ids array first, followed by component arrays.
    def query(*component_classes, &block)
      # If no block is given, return an enumerator that will yield the same values.
      return to_enum(:query, *component_classes) unless block_given?

      # Normalize query signature and cache it
      query_sig = normalize_signature(component_classes)

      # Find all archetypes that contain *at least* the required components
      @archetypes.each_value do |archetype|
        # Use Set-like subtraction check: all query components must be in archetype
        next unless (query_sig - archetype.component_classes).empty?

        # Skip empty archetypes
        next if archetype.entity_ids.empty?

        # Pre-compute component stores to avoid repeated hash lookups
        stores = component_classes.map { |klass| archetype.component_stores[klass] }

        # Yield entity_ids first, then component arrays for high-speed iteration
        yield(archetype.entity_ids, *stores)
      end
    end

    # Iterates over each entity that has the specified components, yielding the entity_id
    # and the requested components as individual values (not arrays).
    # More ergonomic than query() for per-entity iteration.
    def each_entity(*component_classes, &block)
      return to_enum(:each_entity, *component_classes) unless block_given?

      query(*component_classes) do |entity_ids, *stores|
        # not using Array.each_with_index here because we want to be able to `break` this loop
        entity_ids.each_with_index do |entity_id, i|
          components = stores.map { |store| store[i] }
          yield(entity_id, *components)
        end
      end
    end

    # Removes components from a passed query
    # This is safe to use during iteration since it collects entities first.
    def remove_components_from_query(query, *components)
      entities = query.flat_map { |*args| args.first }
      Array.each(entities) do |id|
        Array.each(components) do |component|
          remove_component(id, component)
        end
      end
    end

    # Debug/inspection methods for understanding world state
    def entity_count
      @entity_locations.size
    end

    def archetype_count
      @archetypes.size
    end

    def archetype_stats
      @archetypes.map do |signature, archetype|
        {
          components: signature.map { |c| c.is_a?(Class) ? c.name : c.to_s },
          entity_count: archetype.entity_ids.length
        }
      end
    end

    private

    def find_or_create_archetype(signature)
      @archetypes[signature] ||= Archetype.new(signature)
    end

    def cleanup_empty_archetypes(archetypes)
      archetypes.each do |archetype|
        next unless archetype.entity_ids.empty?
        signature = archetype.component_classes
        @archetypes.delete(signature)
      end
    end
  end
end
