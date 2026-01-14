module Drecs
  module SignatureHelper 
    def normalize_signature(component_classes)
      component_classes.sort_by { |c| c.is_a?(Class) ? c.name : c.to_s }.freeze
    end
  end

  class EntityManager
    def initialize(reuse_entity_ids: true)
      @next_id = 0
      @freed_ids = nil # Lazily initialized for memory efficiency
      @reuse_entity_ids = reuse_entity_ids
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
      return unless @reuse_entity_ids
      @freed_ids ||= []
      @freed_ids << id
    end

    def batch_create_entities(count)
      return [] if count <= 0

      total = count
      ids = Array.new(total)
      idx = 0

      if @freed_ids && !@freed_ids.empty?
        pop_count = total < @freed_ids.length ? total : @freed_ids.length
        popped = @freed_ids.pop(pop_count)

        j = 0
        popped_len = popped.length
        while j < popped_len
          ids[idx] = popped[j]
          idx += 1
          j += 1
        end

        count -= pop_count
      end

      if count > 0
        next_id = @next_id
        @next_id = next_id + count

        while count > 0
          ids[idx] = next_id
          idx += 1
          next_id += 1
          count -= 1
        end
      end

      ids
    end
  end

  # Represents a cached query that avoids signature normalization on every iterate.
  class Query
    attr_reader :world, :component_classes, :signature, :matching_archetypes

    def initialize(world, component_classes)
      @world = world
      @component_classes = component_classes
      @signature = world.normalize_signature(component_classes)
      refresh!
    end

    # Updates the list of matching archetypes. Called automatically when the world 
    # creates new archetypes.
    def refresh!
      @matching_archetypes = []
      @cached_stores = []

      @world.archetypes.each_value do |archetype|
        stores_hash = archetype.component_stores
        sig = @signature
        j = 0
        sig_len = sig.length
        matches = true
        while j < sig_len
          unless stores_hash.key?(sig[j])
            matches = false
            break
          end
          j += 1
        end

        if matches
          @matching_archetypes << archetype
          
          # Pre-calculate the exact arrays we need to yield
          classes = @component_classes
          stores = Array.new(classes.length)
          k = 0
          k_len = classes.length
          while k < k_len
            stores[k] = stores_hash[classes[k]]
            k += 1
          end
          @cached_stores << stores
        end
      end
    end

    def each(&block)
      i = 0
      len = @matching_archetypes.length
      while i < len
        archetype = @matching_archetypes[i]
        ids = archetype.entity_ids
        
        # Skip empty archetypes
        unless ids.empty?
          stores = @cached_stores[i]
          case stores.length
          when 0
            yield(ids)
          when 1
            yield(ids, stores[0])
          when 2
            yield(ids, stores[0], stores[1])
          when 3
            yield(ids, stores[0], stores[1], stores[2])
          when 4
            yield(ids, stores[0], stores[1], stores[2], stores[3])
          else
            yield(ids, *stores)
          end
        end
        
        i += 1
      end
    end
  end

  class Archetype
    include SignatureHelper 

    attr_reader :component_classes, :component_stores, :stores_list, :entity_ids

    def initialize(component_classes)
      # The signature of the archetype, always sorted for consistent lookup.
      @component_classes = component_classes.frozen? ? component_classes : normalize_signature(component_classes)
      @component_stores = @component_classes.to_h { |klass| [klass, []] }
      @stores_list = @component_classes.map { |k| @component_stores[k] } # Fast array access
      @entity_ids = [] # Maps row index to the entity ID at that row
    end

    # Adds an entity's data to this archetype.
    def add(entity_id, components_hash)
      classes = @component_classes
      stores = @stores_list
      i = 0
      len = stores.length
      while i < len
        klass = classes[i]
        stores[i] << components_hash[klass]
        i += 1
      end
      @entity_ids << entity_id
      @entity_ids.length - 1 # Return the new row index
    end

    # Optimized add when components are already an array matching signature classes
    def add_ordered(entity_id, components_array)
      # WARNING: This assumes components_array is in the correct order as @component_classes
      # and matches the length exactly.
      stores = @stores_list
      i = 0
      len = stores.length
      while i < len
        stores[i] << components_array[i]
        i += 1
      end
      @entity_ids << entity_id
      @entity_ids.length - 1
    end

    # Removes an entity from a specific row. This is a critical performance path.
    # Returns [moved_entity_id, is_empty] where is_empty indicates if the archetype is now empty.
    def remove(row_index)
      ids = @entity_ids
      last_idx = ids.length - 1
      last_entity_id = ids[last_idx]

      stores = @stores_list

      # To avoid leaving a hole, we move the *last* element into the deleted slot.
      if last_idx > 0 && row_index != last_idx
        i = 0
        len = stores.length
        while i < len
          store = stores[i]
          store[row_index] = store[last_idx]
          i += 1
        end
        ids[row_index] = last_entity_id
      end

      i = 0
      len = stores.length
      while i < len
        stores[i].pop
        i += 1
      end
      ids.pop

      moved_entity = ids.length > row_index ? last_entity_id : nil
      [moved_entity, ids.empty?]
    end
  end

  class World
    include SignatureHelper 
    
    def initialize(reuse_entity_ids: true, validate_components: false)
      @entity_manager = EntityManager.new(reuse_entity_ids: reuse_entity_ids)
      @systems = []

      @validate_components = validate_components

      # The core lookup tables
      @archetypes = {} # { [Component Classes Signature] => Archetype }
      
      # Optimized location storage: Index is entity_id
      @entity_archetypes = [] 
      @entity_rows = []
      @entity_count = 0
      
      @signature_cache = {} # Cache for normalized signatures
      @query_cache = {} # Cache for matching archetypes per query signature
      @active_queries = [] # List of Query objects to refresh when archetypes change

      @deferred = []
      @resources = {}
    end

    def defer(&blk)
      @deferred << blk
    end

    def flush_defer!
      deferred = @deferred
      @deferred = []
      deferred.each { _1.call(self) }
      nil
    end

    def systems
      @systems
    end

    def add_system(system = nil, &blk)
      system ||= blk
      return nil unless system
      @systems << system
      system
    end

    def tick(args)
      Array.each(@systems) { _1.call(self, args) }
      nil
    end

    # Creates a new entity with the given components.
    def spawn(*components)
      entity_id = @entity_manager.create_entity

      # Handle both struct instances and plain hashes
      if components.length == 1 && components[0].is_a?(Hash)
        components_hash = components[0]
        signature = normalize_signature(components_hash.keys)
        archetype = find_or_create_archetype(signature)
        row = archetype.add(entity_id, components_hash)
      else
        if @validate_components
          classes = components.map(&:class)
          if classes.uniq.length != classes.length
            raise ArgumentError, "Duplicate component types passed to spawn"
          end
        end
        
        # Get signature and archetype
        classes = components.map(&:class)
        signature = normalize_signature(classes)
        archetype = find_or_create_archetype(signature)
        
        # If the components are already in the correct signature order, we can use add_ordered.
        # Otherwise, we use the robust hash-based add.
        if classes == archetype.component_classes
          row = archetype.add_ordered(entity_id, components)
        else
          # Fallback to hash-based add for correct mapping. 
          # We manually build the hash to avoid the overhead of components.to_h
          comp_hash = {}
          Array.each(components) { |c| comp_hash[c.class] = c }
          row = archetype.add(entity_id, comp_hash)
        end
      end

      @entity_archetypes[entity_id] = archetype
      @entity_rows[entity_id] = row
      @entity_count += 1

      entity_id
    end

    def spawn_many(count, *components)
      return [] if count <= 0

      classes = components.map(&:class)
      signature = normalize_signature(classes)
      archetype = find_or_create_archetype(signature)
      
      # Ensure components are in the correct order for the archetype once
      ordered_components = if classes == archetype.component_classes
        components
      else
        archetype.component_classes.map do |klass|
          components[classes.index(klass)]
        end
      end
      
      ids = @entity_manager.batch_create_entities(count)

      stores_list = archetype.stores_list
      store_i = 0
      store_len = stores_list.length
      while store_i < store_len
        store = stores_list[store_i]
        proto = ordered_components[store_i]

        base = store.length
        store[base + count - 1] = nil
        j = 0
        while j < count
          store[base + j] = proto.dup
          j += 1
        end

        store_i += 1
      end
      
      start_row = archetype.entity_ids.length
      archetype.entity_ids.concat(ids)
      
      current_row = start_row
      i = 0
      while i < count
        id = ids[i]
        @entity_archetypes[id] = archetype
        @entity_rows[id] = current_row
        current_row += 1
        i += 1
      end
      
      @entity_count += count
      ids
    end

    alias_method :create, :spawn

    # Alias for spawn using the << operator for a more fluid API
    # Examples:
    #   world << Position.new(0, 0)
    #   world << [Position.new(0, 0), Velocity.new(1, 1)]
    def <<(components)
      if components.is_a?(Array)
        spawn(*components)
      else
        spawn(components)
      end
    end

    def destroy(*entity_ids)
      archetypes_to_cleanup = []

      Array.each(entity_ids) do |entity_id|
        archetype = @entity_archetypes[entity_id]
        next unless archetype

        removed_row = @entity_rows[entity_id]
        moved_entity_id, is_empty = archetype.remove(removed_row)

        if moved_entity_id && moved_entity_id != entity_id
          @entity_rows[moved_entity_id] = removed_row
        end

        archetypes_to_cleanup << archetype if is_empty

        @entity_manager.destroy_entity(entity_id)
        @entity_archetypes[entity_id] = nil
        @entity_rows[entity_id] = nil
        @entity_count -= 1
      end

      cleanup_empty_archetypes(archetypes_to_cleanup)
    end

    alias_method :delete, :destroy
    alias_method :despawn, :destroy
    
    # Adds a component to an existing entity. This triggers a move between archetypes.
    # For hash components, pass a hash like { position: { x: 0, y: 0 } }
    def add_component(entity_id, component_key_or_component, component_value = nil)
      old_archetype = @entity_archetypes[entity_id]
      return false unless old_archetype

      # 1. Gather all current components for the entity
      row = @entity_rows[entity_id]
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][row]]
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

      # If we're already in the right archetype, just update components in place
      if old_archetype == new_archetype
        if component_value.nil?
          if component_key_or_component.is_a?(Hash)
            Array.each(component_key_or_component) do |k, v|
              new_archetype.component_stores[k][row] = v
            end
          else
            new_archetype.component_stores[component_key_or_component.class][row] = component_key_or_component
          end
        else
          new_archetype.component_stores[component_key_or_component][row] = component_value
        end

        return true
      end

      # 3. Add entity data to the new archetype
      new_row = new_archetype.add(entity_id, all_components)
      @entity_archetypes[entity_id] = new_archetype
      @entity_rows[entity_id] = new_row

      # 4. Remove the entity from the old archetype, filling the hole
      moved_entity_id, is_empty = old_archetype.remove(row)

      # 5. If another entity was moved to fill the hole, update its location
      if moved_entity_id && moved_entity_id != entity_id
        @entity_rows[moved_entity_id] = row
      end

      # 6. Clean up old archetype if it's now empty
      cleanup_empty_archetypes([old_archetype]) if is_empty

      true
    end

    alias_method :add, :add_component

    # Removes a component from an existing entity. This triggers a move between archetypes.
    def remove_component(entity_id, component_class)
      old_archetype = @entity_archetypes[entity_id]
      return false unless old_archetype

      # 1. Gather all current components for the entity
      row = @entity_rows[entity_id]
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][row]]
      end

      # If the entity doesn't have the component, nothing to do
      return false unless all_components.key?(component_class)

      # 2. Remove the specified component and find/create the new archetype
      all_components.delete(component_class)
      new_signature = normalize_signature(all_components.keys)
      new_archetype = find_or_create_archetype(new_signature)

      # 3. Add entity data to the new archetype
      new_row = new_archetype.add(entity_id, all_components)
      @entity_archetypes[entity_id] = new_archetype
      @entity_rows[entity_id] = new_row

      # 4. Remove the entity from the old archetype, filling the hole
      moved_entity_id, is_empty = old_archetype.remove(row)

      # 5. If another entity was moved to fill the hole, update its location
      if moved_entity_id && moved_entity_id != entity_id
        @entity_rows[moved_entity_id] = row
      end

      # 6. Clean up old archetype if it's now empty
      cleanup_empty_archetypes([old_archetype]) if is_empty

      true
    end

    alias_method :remove, :remove_component

    # Check if an entity exists in the world
    def entity_exists?(entity_id)
      !@entity_archetypes[entity_id].nil?
    end

    alias_method :exists?, :entity_exists?
    alias_method :alive?, :entity_exists?

    def has_component?(entity_id, component_class)
      archetype = @entity_archetypes[entity_id]
      return false unless archetype
      archetype.component_stores.key?(component_class)
    end

    alias_method :has?, :has_component?
    alias_method :component?, :has_component?

    # Retrieves a specific component from an entity. Returns nil if entity or component doesn't exist.
    def get_component(entity_id, component_class)
      archetype = @entity_archetypes[entity_id]
      return nil unless archetype
      
      return nil unless archetype.component_stores.key?(component_class)

      archetype.component_stores[component_class][@entity_rows[entity_id]]
    end

    alias_method :get, :get_component

    def [](entity_id, component_class)
      get_component(entity_id, component_class)
    end

    # Sets multiple components on an entity in a single operation, avoiding multiple archetype migrations.
    # If the entity doesn't exist, returns false. Components can be added or replaced.
    def set_components(entity_id, *components)
      old_archetype = @entity_archetypes[entity_id]
      return false unless old_archetype

      row = @entity_rows[entity_id]

      # 1. Gather all current components for the entity
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][row]]
      end

      # 2. Merge in the new components (overwriting any existing ones)
      Array.each(components) do |c|
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
        Array.each(components) do |c|
          if c.is_a?(Hash)
            Array.each(c) { |k, v| new_archetype.component_stores[k][row] = v }
          else
            new_archetype.component_stores[c.class][row] = c
          end
        end
        return true
      end

      # 5. Add entity data to the new archetype
      new_row = new_archetype.add(entity_id, all_components)
      @entity_archetypes[entity_id] = new_archetype
      @entity_rows[entity_id] = new_row

      # 6. Remove the entity from the old archetype, filling the hole
      moved_entity_id, is_empty = old_archetype.remove(row)

      # 7. If another entity was moved to fill the hole, update its location
      if moved_entity_id && moved_entity_id != entity_id
        @entity_rows[moved_entity_id] = row
      end

      # 8. Clean up old archetype if it's now empty
      cleanup_empty_archetypes([old_archetype]) if is_empty

      true
    end

    alias_method :set, :set_components
    alias_method :upsert, :set_components

    def set_component(entity_id, component_key_or_component, component_value = nil)
      if component_value.nil?
        set_components(entity_id, component_key_or_component)
      else
        set_components(entity_id, { component_key_or_component => component_value })
      end
    end

    def []=(entity_id, component_class, component_value)
      set_component(entity_id, component_class, component_value)
    end

    # The query interface for systems.
    # Yields entity_ids array first, followed by component arrays.
    def query(*component_classes, with: nil, &block)
      # If no block is given, return an enumerator that will yield single entities.
      # This provides an ergonomic "AoS" view (e.g. query(A).first -> [id, a])
      # while keeping the optimized "SoA" view for the block form.
      unless block_given?
        return each_entity(*component_classes, with: with)
      end

      with_components = Array(with)
      required_components = (component_classes + with_components).uniq

      # Normalize query signature and cache it
      query_sig = normalize_signature(required_components)

      # Use cached matching archetypes if available
      matching_archetypes = @query_cache[query_sig] ||= @archetypes.values.select do |archetype|
        stores_hash = archetype.component_stores
        j = 0
        lenj = query_sig.length
        ok = true
        while j < lenj
          unless stores_hash.key?(query_sig[j])
            ok = false
            break
          end
          j += 1
        end
        ok
      end

      # Find all archetypes that contain *at least* the required components
      i = 0
      len = matching_archetypes.length
      while i < len
        archetype = matching_archetypes[i]
        i += 1
        
        # Skip empty archetypes
        next if archetype.entity_ids.empty?

        # Pre-compute component stores to avoid repeated hash lookups
        stores = component_classes.map { |klass| archetype.component_stores[klass] }

        # Yield entity_ids first, then component arrays for high-speed iteration
        yield(archetype.entity_ids, *stores)
      end
    end

    # Creates a persistent Query object that avoids signature setup on every call.
    def query_for(*component_classes, with: nil)
      with_components = Array(with)
      required_components = (component_classes + with_components).uniq
      
      q = Query.new(self, required_components)
      @active_queries << q
      q
    end

    def archetypes
      @archetypes
    end

    def each_chunk(*component_classes, with: nil, &block)
      unless block_given?
        return Enumerator.new do |yielder|
          each_chunk(*component_classes, with: with) do |*args|
            yielder.yield(*args)
          end
        end
      end

      query(*component_classes, with: with, &block)
    end

    def count(*component_classes, with: nil)
      total = 0
      query(*component_classes, with: with) do |entity_ids, *stores|
        total += entity_ids.length
      end
      total
    end

    def ids(*component_classes, with: nil)
      all_ids = []
      query(*component_classes, with: with) do |entity_ids, *stores|
        all_ids.concat(entity_ids)
      end
      all_ids
    end

    # Iterates over each entity that has the specified components, yielding the entity_id
    # and the requested components as individual values (not arrays).
    # More ergonomic than query() for per-entity iteration.
    def each_entity(*component_classes, with: nil, &block)
      unless block_given?
        return Enumerator.new do |yielder|
          each_entity(*component_classes, with: with) do |*args|
            yielder.yield(*args)
          end
        end
      end

      query(*component_classes, with: with) do |entity_ids, *stores|
        i = 0
        len = entity_ids.length
        num_stores = stores.length
        
        while i < len
          case num_stores
          when 1 then yield(entity_ids[i], stores[0][i])
          when 2 then yield(entity_ids[i], stores[0][i], stores[1][i])
          when 3 then yield(entity_ids[i], stores[0][i], stores[1][i], stores[2][i])
          when 4 then yield(entity_ids[i], stores[0][i], stores[1][i], stores[2][i], stores[3][i])
          else
            yield(entity_ids[i], *stores.map { |s| s[i] })
          end
          i += 1
        end
      end

      flush_defer!
    end

    alias_method :each, :each_entity

    # Finds the first entity that has the specified components.
    # Returns [entity_id, component1, component2, ...] or nil if no match found.
    # If a block is given, yields the entity_id and components, returning the entity_id.
    def first_entity(*component_classes, with: nil, &block)
      query(*component_classes, with: with) do |entity_ids, *stores|
        next if entity_ids.empty?

        entity_id = entity_ids[0]
        components = stores.map { |store| store[0] }

        if block_given?
          yield(entity_id, *components)
          return entity_id
        else
          return [entity_id, *components]
        end
      end

      # No matching entity found
      nil
    end

    alias_method :first, :first_entity

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

    # Destroys all entities that match a passed query.
    # This is safe to use during iteration since it collects entities first.
    def destroy_from_query(query)
      entities = query.flat_map { |*args| args.first }
      destroy(*entities) unless entities.empty?
    end

    # Convenience wrapper for destroying all entities matching a query signature.
    def destroy_query(*component_classes, with: nil)
      destroy_from_query(query(*component_classes, with: with))
    end

    alias_method :destroy_all, :destroy_query

    def remove_all(component, where: nil)
      query_components = Array(where)
      query_components << component unless query_components.include?(component)
      remove_components_from_query(query(*query_components), component)
      nil
    end

    def clear!
      Array.each(@entity_archetypes) do |arch, id|
        destroy(id) if arch
      end
      nil
    end

    # Debug/inspection methods for understanding world state
    def entity_count
      @entity_count
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

    # Resources provide global singleton state management
    def insert_resource(resource_or_key, value = nil)
      @resources ||= {}
      if value.nil?
        if resource_or_key.is_a?(Hash)
          key = resource_or_key.keys.first
          val = resource_or_key.values.first
          @resources[key] = val
        else
          @resources[resource_or_key.class] = resource_or_key
        end
      else
        @resources[resource_or_key] = value
      end
    end

    # Retrieve a resource by class or symbol key
    def resource(resource_or_key)
      @resources&.[](resource_or_key)
    end

    # Remove a resource by class or symbol key
    def remove_resource(resource_or_key)
      @resources&.delete(resource_or_key)
    end

    private

    def find_or_create_archetype(signature)
      normalized = signature.frozen? ? signature : normalize_signature(signature)
      if !@archetypes.key?(normalized)
        @archetypes[normalized] = Archetype.new(normalized)
        @query_cache.clear
        Array.each(@active_queries) { _1.refresh! }
      end
      @archetypes[normalized]
    end

    def cleanup_empty_archetypes(archetypes)
      Array.each(archetypes) do |archetype|
        next unless archetype.entity_ids.empty?
        signature = archetype.component_classes
        @archetypes.delete(signature)
      end
    end
  end
end
