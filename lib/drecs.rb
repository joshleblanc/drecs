# The native (SDL3-threaded) runtime is OPTIONAL. drecs degrades gracefully
# when it isn't present (see World#each_entity / #run_native_system, which
# both feature-detect `Drecs::Parallel`). Loading it must therefore never be
# fatal â€” a `GTK.download_stb_rb` single-file install of `lib/drecs.rb` won't
# ship `ext/drecs_parallel.rb`, and that's fine.
begin
  require 'ext/drecs_parallel.rb'
rescue LoadError, StandardError
  # Native runtime unavailable; pure-Ruby paths are used instead.
end

module Drecs
  # Native system support is provided by ext/drecs_parallel.rb (Drecs::Parallel)
  # plus the World#register_native_system / World#run_native_system pair below.
  #
  # For high-performance rendering, write a native kernel that walks the
  # drecs struct stores and pushes to args.outputs via the standard native
  # system flow â€” there's no separate render API by design.

  module SignatureHelper 
    def normalize_signature(component_classes)
      # Anonymous classes (e.g. a `Drecs.component(...)` result that hasn't
      # been assigned to a constant yet) have a nil name; fall back to a
      # stable per-class key so sorting never compares nil against a String.
      component_classes.sort_by { |c| c.is_a?(Class) ? (c.name || "~anon~#{c.object_id}") : c.to_s }.freeze
    end
  end

  # Install the drecs component accessors (the @-ivar getters/setters plus the
  # Struct-ish `members`/`values`/`[]`/`[]=` API) onto `klass`. Shared by both
  # `Drecs.component` (anonymous-class form) and the `Drecs::Component` mixin
  # (named-class form) so the two stay byte-for-byte identical.
  #
  # Why @-ivars and not `Struct.new(*members)`: mruby's Struct stores fields in
  # an internal C array, NOT as @-ivars. So `mrb_iv_get(obj, :x)` returns nil,
  # and `mrb_iv_set(obj, :x, v)` writes to a separate slot the Struct accessor
  # `.x` never reads. The two stay desynced forever â€” `run_kernel_native` would
  # silently produce all-zero positions, sizes, and colors (which is why the v2
  # path produced a black screen). Pre-compute the @-ivar symbol for each member
  # once so the per-call accessors don't rebuild `:"@#{m}"` on every read/write â€”
  # that interpolation was a real cost on hot iteration paths.
  def self.define_component_accessors(klass, members)
    ivars = members.map { |m| :"@#{m}" }
    klass.class_eval do
      define_method(:initialize) do |*args|
        i = 0
        len = ivars.length
        while i < len
          instance_variable_set(ivars[i], args[i])
          i += 1
        end
      end
      members.each_with_index do |m, idx|
        ivar = ivars[idx]
        define_method(m)       { instance_variable_get(ivar) }
        define_method("#{m}=") { |v| instance_variable_set(ivar, v) }
      end
      define_method(:members) { members }
      define_method(:values)  { ivars.map { |iv| instance_variable_get(iv) } }
      define_method(:[])      { |key| instance_variable_get(:"@#{key}") }
      define_method(:[]=)     { |key, v| instance_variable_set(:"@#{key}", v) }
    end
    klass
  end

  # Returns an anonymous class whose fields live as @-ivars (see
  # `define_component_accessors`). Good for one-liners with no methods:
  #
  #   Position = Drecs.component(:x, :y)
  #
  # Like `Struct.new`, an optional block is class_eval'd on the result, so you
  # can add methods or override the default initializer inline:
  #
  #   Velocity = Drecs.component(:dx, :dy) do
  #     def speed = Math.sqrt(dx * dx + dy * dy)
  #   end
  #
  # When you need real class constants (e.g. `Tile::TILE_FLOOR`) or just prefer
  # a normal, named class body, use the `Drecs::Component` mixin instead.
  def self.component(*members, &block)
    klass = define_component_accessors(Class.new, members)
    klass.class_eval(&block) if block
    klass
  end

  # Mixin that turns an ordinary, named class into a drecs component. Use this
  # when you want methods and/or real class constants without the
  # `X = Drecs.component(...)` + `class X` reopen dance:
  #
  #   class Velocity
  #     include Drecs::Component
  #     component :dx, :dy
  #
  #     def moving? = dx != 0 || dy != 0
  #     def speed   = Math.sqrt(dx * dx + dy * dy)
  #   end
  #
  #   class Tile
  #     include Drecs::Component
  #     component :type
  #     TILE_FLOOR = 0   # a real class constant: Tile::TILE_FLOOR works
  #   end
  #
  # The default initializer assigns members positionally; define your own
  # `initialize` after the `component` call to add defaults.
  module Component
    def self.included(base)
      base.extend(ClassMethods)
    end

    module ClassMethods
      def component(*members)
        Drecs.define_component_accessors(self, members)
        members
      end
    end
  end

  # Build a tag component â€” a zero-field marker class with an introspectable
  # `tag_name` reader, available on both the class and its instances:
  #
  #   Player = Drecs.tag(:player)
  #   Player.tag_name       # => :player
  #   Player.new.tag_name   # => :player
  #   Enemy  = Drecs.tag(:enemy)
  #   Bullet = Drecs.tag("Bullet")     # also OK â€” string is used verbatim
  #   Anonymous = Drecs.tag            # tag_name is nil; assign to a constant yourself
  #
  # Tags are plain classes with the standard drecs component API (`members`,
  # `values`, `[]`), NOT `Struct` subclasses: no global `Struct::Player`
  # constant is defined (so two `Drecs.tag(:player)` calls can't collide or
  # emit redefinition warnings), instances carry zero fields, and the class
  # is safe to reference from native systems (which reject Struct-based
  # components).
  def self.tag(name = nil)
    klass = define_component_accessors(Class.new, [])
    klass.define_singleton_method(:tag_name) { name }
    klass.send(:define_method, :tag_name) { name }
    klass
  end

  # Builds a single, persistent renderer object that draws every entity
  # matching a set of components straight out of drecs's archetype storage â€”
  # no per-entity sprite object, no shadow "renderables" hash, no per-frame
  # allocation. Push the returned object into `args.outputs.static_sprites`
  # ONCE; its `draw_override` walks `each_chunk` every frame and emits one
  # positional `ffi.draw_sprite_*` call per entity.
  #
  # This is the bridge between drecs's Structure-of-Arrays storage (where a
  # renderable's data lives across SEPARATE components) and DragonRuby's
  # renderer (which wants all sprite attributes for one draw call): the
  # mapping says which component+field each sprite attribute is pulled from,
  # and the positional FFI draw call assembles them â€” so you keep granular
  # components (Position, Size, Color, ...) and never author a fat "Sprite".
  #
  #   renderer = Drecs.sprite_renderer(world,
  #     x: [Position, :x], y: [Position, :y],
  #     w: [Size, :w],     h: [Size, :h],
  #     path: [Sprite, :path],
  #     r: [Color, :r], g: [Color, :g], b: [Color, :b], a: [Color, :a],
  #     flip_horizontally: [Facing, :flipped])
  #   args.outputs.static_sprites << renderer   # once, ever
  #
  # Each mapping value is one of:
  #   * `[ComponentClass, :field]` â€” read `component.field` per entity
  #   * `[ComponentClass, ->(c){ ... }]` â€” computed from one component
  #   * any other value â€” a constant applied to every entity (e.g.
  #     `path: 'sprites/star.png'`, `angle: 0`, `flip_horizontally: false`)
  #   * omitted â€” DragonRuby's default for that attribute (see DEFAULTS)
  #
  # `with:` / `without:` / `any:` are forwarded to `each_chunk` so you can
  # gate which entities render (e.g. `with: Visible`, `without: Hidden`)
  # without those tag components feeding any sprite attribute.
  def self.sprite_renderer(world, mapping = {}, with: nil, without: nil, any: nil, variant: 6)
    SpriteRenderer.new(world, mapping, with: with, without: without, any: any, variant: variant)
  end

  class SpriteRenderer
    # Canonical attribute order, matching `ffi_draw.draw_sprite_6`'s positional
    # argument list (a superset of draw_sprite_3/4/5). `:a` is alpha; `:r/:g/:b`
    # are the saturation/tint channels (255 = unmodified for an image sprite,
    # or the fill color for the built-in white `:solid` path).
    ATTRS = [
      :x, :y, :w, :h, :path, :angle,
      :a, :r, :g, :b,
      :tile_x, :tile_y, :tile_w, :tile_h,
      :flip_horizontally, :flip_vertically,
      :angle_anchor_x, :angle_anchor_y,
      :source_x, :source_y, :source_w, :source_h,
      :blendmode_enum,
      :anchor_x, :anchor_y,
      :scale_quality_enum
    ].freeze

    # How many leading ATTRS each draw_sprite_N variant consumes.
    VARIANT_ARGC = { 3 => 22, 4 => 23, 5 => 25, 6 => 26 }.freeze

    # Sensible defaults for attributes the caller doesn't map. `path` must be
    # non-nil for anything to render, so it defaults to the built-in white
    # `:solid` pixel (tint it via r/g/b for solid-color fills). Everything else
    # left as nil falls through to DragonRuby's own per-attribute default.
    DEFAULTS = {
      path: :solid,
      angle: 0,
      a: 255, r: 255, g: 255, b: 255,
      flip_horizontally: false, flip_vertically: false
    }.freeze

    attr_reader :components

    def initialize(world, mapping, with: nil, without: nil, any: nil, variant: 6)
      @world = world
      @without = without
      @any = any

      argc = VARIANT_ARGC[variant]
      raise ArgumentError, "variant must be one of #{VARIANT_ARGC.keys.inspect}" unless argc
      @draw_method = "draw_sprite_#{variant}".to_sym
      @argc = argc

      # Discover the components referenced by accessor mappings, in first-seen
      # order â€” this is the iteration signature handed to each_chunk.
      comps = []
      ATTRS.each do |attr|
        v = mapping[attr]
        next unless accessor?(v)
        comps << v[0] unless comps.include?(v[0])
      end

      # `with:` components participate in entity selection but feed no attribute.
      # They're appended AFTER the accessor components so accessor store indices
      # (computed against `comps`) stay valid in the each_chunk yield order.
      with_only = Array(with).reject { |k| comps.include?(k) }
      @components = comps
      @iter_components = comps + with_only

      if @iter_components.empty?
        raise ArgumentError, "sprite_renderer needs at least one [Component, :field] mapping or a `with:` component to know which entities to draw"
      end

      # Precompute, per ATTR slot (only up to @argc), how to resolve its value:
      #   @is_accessor[slot]  -> true if read from a component
      #   @store_idx[slot]    -> which each_chunk store array to read
      #   @getter[slot]       -> Symbol (sent to component) or Proc (called with it)
      #   @is_proc[slot]      -> getter is a Proc
      #   @const[slot]        -> constant/default value when not an accessor
      @is_accessor = Array.new(@argc, false)
      @store_idx   = Array.new(@argc)
      @getter      = Array.new(@argc)
      @is_proc     = Array.new(@argc, false)
      @const       = Array.new(@argc)

      slot = 0
      while slot < @argc
        attr = ATTRS[slot]
        if mapping.key?(attr) && accessor?(mapping[attr])
          v = mapping[attr]
          @is_accessor[slot] = true
          @store_idx[slot]   = comps.index(v[0])
          getter             = v[1]
          @is_proc[slot]     = !getter.is_a?(Symbol) && getter.respond_to?(:call)
          @getter[slot]      = getter
        elsif mapping.key?(attr)
          @const[slot] = mapping[attr]
        else
          @const[slot] = DEFAULTS[attr]
        end
        slot += 1
      end

      # Reused argument buffer â€” refilled per entity, never reallocated.
      @args = Array.new(@argc)
    end

    # Returns true for an accessor mapping of the form [ComponentClass, :field]
    # or [ComponentClass, proc]. Sprite attribute constants are always scalars
    # (numbers / symbols / strings / booleans), so a 2-element [Class, Symbol|callable]
    # array is unambiguously an accessor.
    def accessor?(v)
      v.is_a?(Array) && v.length == 2 && v[0].is_a?(Class) &&
        (v[1].is_a?(Symbol) || v[1].respond_to?(:call))
    end

    # Invoked by DragonRuby for each object in outputs that responds to it.
    # Walks the matching archetype chunks and emits one positional sprite draw
    # per entity, pulling each attribute from its mapped component.
    def draw_override(ffi)
      args        = @args
      argc        = @argc
      is_accessor = @is_accessor
      store_idx   = @store_idx
      getter      = @getter
      is_proc     = @is_proc
      const       = @const
      draw_method = @draw_method

      @world.each_chunk(*@iter_components, with: nil, without: @without, any: @any) do |ids, *stores|
        row = 0
        n = ids.length
        while row < n
          slot = 0
          while slot < argc
            if is_accessor[slot]
              comp = stores[store_idx[slot]][row]
              if is_proc[slot]
                args[slot] = getter[slot].call(comp)
              else
                args[slot] = comp.send(getter[slot])
              end
            else
              args[slot] = const[slot]
            end
            slot += 1
          end
          ffi.send(draw_method, *args)
          row += 1
        end
      end
    end
  end

  Name = Struct.new(:value)

  class Bundle
    include SignatureHelper

    attr_reader :signature

    def initialize(component_keys)
      @signature = normalize_signature(component_keys)
    end
  end

  class BundleBuilder
    def initialize
      @data = {}
    end

    def []=(key, value)
      @data[key] = value
    end

    def [](key)
      @data[key]
    end

    def to_h
      @data
    end
  end

  class Commands
    def initialize
      @queue = []
    end

    def spawn(*components)
      @queue << ->(world) { world.spawn(*components) }
      self
    end

    def spawn_bundle(bundle, *components, &blk)
      @queue << ->(world) { world.spawn_bundle(bundle, *components, &blk) }
      self
    end

    def spawn_many(count, *components)
      @queue << ->(world) { world.spawn_many(count, *components) }
      self
    end

    def destroy(*entity_ids)
      @queue << ->(world) { world.destroy(*entity_ids) }
      self
    end

    def add_component(entity_id, component_key_or_component, component_value = nil)
      @queue << lambda do |world|
        world.add_component(entity_id, component_key_or_component, component_value)
      end
      self
    end

    def remove_component(entity_id, component_class)
      @queue << ->(world) { world.remove_component(entity_id, component_class) }
      self
    end

    def set_component(entity_id, component_key_or_component, component_value = nil)
      @queue << lambda do |world|
        world.set_component(entity_id, component_key_or_component, component_value)
      end
      self
    end

    def set_components(entity_id, *components)
      @queue << ->(world) { world.set_components(entity_id, *components) }
      self
    end

    def set_parent(child_id, parent_id)
      @queue << ->(world) { world.set_parent(child_id, parent_id) }
      self
    end

    def clear_parent(child_id)
      @queue << ->(world) { world.clear_parent(child_id) }
      self
    end

    def add_child(parent_id, child_id)
      @queue << ->(world) { world.add_child(parent_id, child_id) }
      self
    end

    def remove_child(parent_id, child_id)
      @queue << ->(world) { world.remove_child(parent_id, child_id) }
      self
    end

    def destroy_subtree(root_id)
      @queue << ->(world) { world.destroy_subtree(root_id) }
      self
    end

    def defer(&blk)
      @queue << blk
      self
    end

    def apply(world)
      queue = @queue
      @queue = []
      queue.each { |cmd| cmd.call(world) }
      nil
    end
  end

  # Relationship components for parent/child graphs.
  Parent = Struct.new(:id)
  Children = Struct.new(:ids)

  def self.bundle(*component_keys)
    Bundle.new(component_keys)
  end

  # Raised by `World#validate!` when an internal invariant is violated.
  class IntegrityError < StandardError; end

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

    # Drop the freed-id pool. After this call, the next `count` create_entity
    # calls will allocate fresh sequential ids starting from @next_id.
    def reset_freed_ids!
      @freed_ids = nil
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

    def initialize(world, component_classes, with: nil, without: nil, any: nil, changed: nil)
      @world = world
      @component_classes = component_classes
      with_components = Array(with)
      changed_components = Array(changed)
      required_components = (component_classes + with_components + changed_components).uniq
      @signature = world.normalize_signature(required_components)
      @without_signature = (tmp = Array(without)).empty? ? nil : world.normalize_signature(tmp)
      @any_signature = (tmp = Array(any)).empty? ? nil : world.normalize_signature(tmp)
      @changed_signature = (tmp = changed_components).empty? ? nil : world.normalize_signature(tmp)
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

        if matches && (without_sig = @without_signature)
          k = 0
          k_len = without_sig.length
          while k < k_len
            if stores_hash.key?(without_sig[k])
              matches = false
              break
            end
            k += 1
          end
        end

        if matches && (any_sig = @any_signature)
          k = 0
          k_len = any_sig.length
          any_match = false
          while k < k_len
            if stores_hash.key?(any_sig[k])
              any_match = true
              break
            end
            k += 1
          end
          matches = false unless any_match
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

          if (changed_sig = @changed_signature)
            changed_tick = @world.change_tick
            changed_arrays = Array.new(changed_sig.length)
            j = 0
            j_len = changed_sig.length
            while j < j_len
              changed_arrays[j] = archetype.component_changed_at[changed_sig[j]]
              j += 1
            end

            filtered_ids = []
            filtered_stores = Array.new(stores.length) { [] }
            row = 0
            row_len = ids.length
            while row < row_len
              ok = true
              j = 0
              while j < j_len
                if changed_arrays[j][row] != changed_tick
                  ok = false
                  break
                end
                j += 1
              end

              if ok
                filtered_ids << ids[row]
                k = 0
                k_len = stores.length
                while k < k_len
                  filtered_stores[k] << stores[k][row]
                  k += 1
                end
              end

              row += 1
            end

            unless filtered_ids.empty?
              case filtered_stores.length
              when 0
                yield(filtered_ids)
              when 1
                yield(filtered_ids, filtered_stores[0])
              when 2
                yield(filtered_ids, filtered_stores[0], filtered_stores[1])
              when 3
                yield(filtered_ids, filtered_stores[0], filtered_stores[1], filtered_stores[2])
              when 4
                yield(filtered_ids, filtered_stores[0], filtered_stores[1], filtered_stores[2], filtered_stores[3])
              else
                yield(filtered_ids, *filtered_stores)
              end
            end
          else
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
        end
        
        i += 1
      end
    end
  end

  class Archetype
    include SignatureHelper 

    attr_reader :component_classes, :component_stores, :stores_list, :entity_ids, :component_changed_at, :changed_stores_list

    def initialize(component_classes)
      # The signature of the archetype, always sorted for consistent lookup.
      @component_classes = component_classes.frozen? ? component_classes : normalize_signature(component_classes)
      @component_stores = @component_classes.to_h { |klass| [klass, []] }
      @stores_list = @component_classes.map { |k| @component_stores[k] } # Fast array access
      @component_changed_at = @component_classes.to_h { |klass| [klass, []] }
      @changed_stores_list = @component_classes.map { |k| @component_changed_at[k] }
      @entity_ids = [] # Maps row index to the entity ID at that row
    end

    # Adds an entity's data to this archetype.
    def add(entity_id, components_hash, changed_hash = nil, touched_hash = nil, change_tick = nil)
      change_tick ||= 0
      classes = @component_classes
      stores = @stores_list
      changed_stores = @changed_stores_list
      i = 0
      len = stores.length
      while i < len
        klass = classes[i]
        stores[i] << components_hash[klass]
        if touched_hash && touched_hash[klass]
          changed_stores[i] << change_tick
        elsif changed_hash
          changed_stores[i] << (changed_hash[klass] || change_tick)
        else
          changed_stores[i] << change_tick
        end
        i += 1
      end
      @entity_ids << entity_id
      @entity_ids.length - 1 # Return the new row index
    end

    # Optimized add when components are already an array matching signature classes
    def add_ordered(entity_id, components_array, change_tick = nil)
      change_tick ||= 0
      # WARNING: This assumes components_array is in the correct order as @component_classes
      # and matches the length exactly.
      stores = @stores_list
      changed_stores = @changed_stores_list
      i = 0
      len = stores.length
      while i < len
        stores[i] << components_array[i]
        changed_stores[i] << change_tick
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
      changed_stores = @changed_stores_list

      # To avoid leaving a hole, we move the *last* element into the deleted slot.
      if last_idx > 0 && row_index != last_idx
        i = 0
        len = stores.length
        while i < len
          store = stores[i]
          store[row_index] = store[last_idx]
          changed_store = changed_stores[i]
          changed_store[row_index] = changed_store[last_idx]
          i += 1
        end
        ids[row_index] = last_entity_id
      end

      i = 0
      len = stores.length
      while i < len
        stores[i].pop
        changed_stores[i].pop
        i += 1
      end
      ids.pop

      moved_entity = ids.length > row_index ? last_entity_id : nil
      [moved_entity, ids.empty?]
    end
  end

  class World
    include SignatureHelper 
    
    def initialize(reuse_entity_ids: true, validate_components: false, deprecation_warnings: true)
      @entity_manager = EntityManager.new(reuse_entity_ids: reuse_entity_ids)
      @systems = []
      @scheduled_systems = {}
      @compiled_schedule = nil
      @schedule_dirty = false

      @change_tick = 0

      @validate_components = validate_components
      @deprecation_warnings = deprecation_warnings

      # The core lookup tables
      @archetypes = {} # { [Component Classes Signature] => Archetype }
      
      # Optimized location storage: Index is entity_id
      @entity_archetypes = [] 
      @entity_rows = []
      @entity_count = 0
      
      @query_cache = {} # Cache for matching archetypes per query signature
      @active_queries = [] # List of Query objects to refresh when archetypes change

      @deferred = []
      @resources = {}
      @events = {}

      @on_added = {}
      @on_removed = {}
      @on_changed = {}

      @iterating = 0

      yield self if block_given?
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

    def in_iteration?
      @iterating.positive?
    end

    # Buffers a batch of world mutations and always defers them to the next
    # flush point. Safe to call from inside a query (the deferred commands run
    # after iteration ends) and outside a query (they run at the next flush â€”
    # typically the end of `World#tick`).
    #
    # If you need mutations to apply immediately outside of iteration, use
    # `commands!` instead.
    def commands(&block)
      buffer = Commands.new
      if block_given?
        yield buffer
        defer { |w| buffer.apply(w) }
      end
      buffer
    end

    # Like `commands`, but applies the buffered mutations immediately. Use this
    # when you're outside of iteration and need the change to be visible to
    # subsequent calls in the same code path (e.g. mid-tick from a system that
    # ran before iteration, or during boot).
    def commands!(&block)
      buffer = Commands.new
      if block_given?
        yield buffer
        buffer.apply(self)
      end
      buffer
    end

    def on_added(component_class, &blk)
      return nil unless blk
      (@on_added[component_class] ||= []) << blk
      blk
    end

    def on_removed(component_class, &blk)
      return nil unless blk
      (@on_removed[component_class] ||= []) << blk
      blk
    end

    def on_changed(component_class, &blk)
      return nil unless blk
      (@on_changed[component_class] ||= []) << blk
      blk
    end

    def systems
      @systems
    end

    def add_system(system = nil, after: nil, before: nil, **kwargs, &blk)
      if (system.is_a?(Symbol) || system.is_a?(String))
        name = system.to_sym
        callable = blk || kwargs[:system]
        return nil unless callable

        if_condition = kwargs[:if] || kwargs[:run_if]

        @scheduled_systems[name] = {
          name: name,
          callable: callable,
          after: Array(after).compact.map(&:to_sym),
          before: Array(before).compact.map(&:to_sym),
          if: if_condition
        }
        @schedule_dirty = true
        callable
      else
        system ||= blk
        return nil unless system
        @systems << system
        system
      end
    end

    def system(system = nil, after: nil, before: nil, **kwargs, &blk)
      add_system(system, after: after, before: before, **kwargs, &blk)
    end

    def clear_schedule!
      @scheduled_systems.clear
      @compiled_schedule = nil
      @schedule_dirty = false
      nil
    end

    def compile_schedule!
      systems = @scheduled_systems
      names = systems.keys
      return [] if names.empty?

      adjacency = {}
      indegree = {}

      Array.each(names) do |n|
        adjacency[n] = []
        indegree[n] = 0
      end

      Array.each(names) do |n|
        rec = systems[n]

        Array.each(rec[:after]) do |dep|
          raise ArgumentError, "Unknown system referenced: #{dep}" unless systems.key?(dep)
          adjacency[dep] << n
          indegree[n] += 1
        end

        Array.each(rec[:before]) do |dep|
          raise ArgumentError, "Unknown system referenced: #{dep}" unless systems.key?(dep)
          adjacency[n] << dep
          indegree[dep] += 1
        end
      end

      order = []
      queue = []
      Array.each(names) { |n| queue << n if indegree[n] == 0 }

      until queue.empty?
        n = queue.shift
        order << n
        Array.each(adjacency[n]) do |m|
          indegree[m] -= 1
          queue << m if indegree[m] == 0
        end
      end

      if order.length != names.length
        raise ArgumentError, "System schedule has a cycle"
      end

      order
    end

    def scheduled?
      !@scheduled_systems.empty?
    end

    def change_tick
      @change_tick
    end

    def advance_change_tick!
      @change_tick += 1
      clear_events!
    end

    def tick(args)
      advance_change_tick!

      if scheduled?
        if @schedule_dirty || @compiled_schedule.nil?
          @compiled_schedule = compile_schedule!
          @schedule_dirty = false
        end

        Array.each(@compiled_schedule) do |name|
          rec = @scheduled_systems[name]
          cond = rec[:if]
          next if cond && !cond.call(self, args)
          rec[:callable].call(self, args)
        end
      end

      Array.each(@systems) { _1.call(self, args) }

      # Flush any commands deferred via `commands` (the always-defer form).
      # Iteration already flushes when it ends; this catches everything that
      flush_defer! unless @deferred.empty?
      nil
    end

    alias_method :step, :tick

    # Creates a new entity with the given components.
    #
    # NOTE: a single Hash argument is interpreted as hash-keyed components
    # ({ key => component } pairs, keys may be Classes or Symbols) â€” not as
    # one component whose type is Hash.
    def spawn(*components)
      entity_id = @entity_manager.create_entity

      # Handle both struct instances and plain hashes
      if components.length == 1 && components[0].is_a?(Hash)
        components_hash = components[0]
        signature = normalize_signature(components_hash.keys)
        archetype = find_or_create_archetype(signature)
        row = archetype.add(entity_id, components_hash, nil, nil, @change_tick)
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
          row = archetype.add_ordered(entity_id, components, @change_tick)
        else
          # Fallback to hash-based add for correct mapping. 
          # We manually build the hash to avoid the overhead of components.to_h
          comp_hash = {}
          Array.each(components) { |c| comp_hash[c.class] = c }
          row = archetype.add(entity_id, comp_hash, nil, nil, @change_tick)
        end
      end

      @entity_archetypes[entity_id] = archetype
      @entity_rows[entity_id] = row
      @entity_count += 1

      run_added_hooks_for_row(archetype, entity_id, row) unless @on_added.empty?

      entity_id
    end

    # `create` is an alias for `spawn` (see alias_method below).

    def spawn_bundle(bundle, *components)
      entity_id = @entity_manager.create_entity
      signature = bundle.signature
      archetype = find_or_create_archetype(signature)

      comp_hash = nil

      if block_given?
        builder = BundleBuilder.new
        yield(builder)
        comp_hash = builder.to_h
      elsif components.length == 1 && components[0].is_a?(Hash)
        comp_hash = components[0]
      else
        comp_hash = {}
        Array.each(components) do |c|
          if c.is_a?(Hash)
            comp_hash.merge!(c)
          else
            comp_hash[c.class] = c
          end
        end
      end

      i = 0
      len = signature.length
      while i < len
        key = signature[i]
        unless comp_hash.key?(key)
          raise ArgumentError, "Missing component for bundle: #{key}"
        end
        i += 1
      end

      ordered = Array.new(len)
      i = 0
      while i < len
        key = signature[i]
        ordered[i] = comp_hash[key]
        i += 1
      end

      row = archetype.add_ordered(entity_id, ordered, @change_tick)
      @entity_archetypes[entity_id] = archetype
      @entity_rows[entity_id] = row
      @entity_count += 1

      run_added_hooks_for_row(archetype, entity_id, row) unless @on_added.empty?

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
      changed_list = archetype.changed_stores_list
      store_i = 0
      store_len = stores_list.length
      while store_i < store_len
        store = stores_list[store_i]
        changed_store = changed_list[store_i]
        proto = ordered_components[store_i]

        base = store.length
        store[base + count - 1] = nil
        changed_store[base + count - 1] = nil
        j = 0
        while j < count
          store[base + j] = proto.dup
          changed_store[base + j] = @change_tick
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

      unless @on_added.empty?
        base_row = start_row
        i = 0
        while i < count
          run_added_hooks_for_row(archetype, ids[i], base_row + i)
          i += 1
        end
      end
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
        removed_components = nil

        # Relationship cleanup
        if (parent_store = archetype.component_stores[Parent])
          parent_comp = parent_store[removed_row]
          remove_child_from_parent(parent_comp.id, entity_id) if parent_comp
        end

        if (children_store = archetype.component_stores[Children])
          children_comp = children_store[removed_row]
          if children_comp && children_comp.ids
            Array.each(children_comp.ids) do |child_id|
              child_parent = get_component(child_id, Parent)
              remove_component_internal(child_id, Parent, true) if child_parent && child_parent.id == entity_id
            end
          end
        end

        unless @on_removed.empty?
          classes = archetype.component_classes
          stores = archetype.stores_list
          removed_components = Array.new(classes.length)
          i = 0
          len = classes.length
          while i < len
            removed_components[i] = [classes[i], stores[i][removed_row]]
            i += 1
          end
        end
        moved_entity_id, is_empty = archetype.remove(removed_row)

        if moved_entity_id && moved_entity_id != entity_id
          @entity_rows[moved_entity_id] = removed_row
        end

        archetypes_to_cleanup << archetype if is_empty

        @entity_manager.destroy_entity(entity_id)
        @entity_archetypes[entity_id] = nil
        @entity_rows[entity_id] = nil
        @entity_count -= 1

        if removed_components
          i = 0
          len = removed_components.length
          while i < len
            klass, component = removed_components[i]
            run_removed_hook(klass, entity_id, component)
            i += 1
          end
        end
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

      row = @entity_rows[entity_id]
      stores = old_archetype.component_stores
      changed_at = old_archetype.component_changed_at

      # Fast path: if every key being written already exists on the entity's
      # archetype, there's no migration. Update in place without rebuilding the
      # full component hash or recomputing the signature â€” this is the common
      # per-frame "update an existing component" case.
      if component_value.nil?
        if component_key_or_component.is_a?(Hash)
          all_present = true
          component_key_or_component.each_key do |k|
            unless stores.key?(k)
              all_present = false
              break
            end
          end
          if all_present
            keys = []
            component_key_or_component.each do |k, v|
              stores[k][row] = v
              changed_at[k][row] = @change_tick
              keys << k
            end
            run_changed_hooks_for_keys(keys, old_archetype, entity_id, row) unless @on_changed.empty?
            return true
          end
        else
          klass = component_key_or_component.class
          if stores.key?(klass)
            stores[klass][row] = component_key_or_component
            changed_at[klass][row] = @change_tick
            run_changed_hooks_for_keys([klass], old_archetype, entity_id, row) unless @on_changed.empty?
            return true
          end
        end
      elsif stores.key?(component_key_or_component)
        stores[component_key_or_component][row] = component_value
        changed_at[component_key_or_component][row] = @change_tick
        run_changed_hooks_for_keys([component_key_or_component], old_archetype, entity_id, row) unless @on_changed.empty?
        return true
      end

      # Slow path: at least one new component type -> archetype migration.
      # 1. Gather all current components for the entity
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][row]]
      end

      all_changed = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_changed_at[klass][row]]
      end

      touched = {}

      # Handle both hash-style and struct-style components
      if component_value.nil?
        if component_key_or_component.is_a?(Hash)
          all_components.merge!(component_key_or_component)
          Array.each(component_key_or_component) { |k, _v| touched[k] = true }
        else
          all_components[component_key_or_component.class] = component_key_or_component
          touched[component_key_or_component.class] = true
        end
      else
        all_components[component_key_or_component] = component_value
        touched[component_key_or_component] = true
      end

      added_keys = []
      changed_keys = []
      Array.each(touched.keys) do |k|
        if old_archetype.component_stores.key?(k)
          changed_keys << k
        else
          added_keys << k
        end
      end

      # 2. Find the new archetype based on the new signature.
      #    (The fast path above already handled the "every key present" case,
      #    so at least one new component type exists here and new_archetype is
      #    always different from old_archetype.)
      new_signature = normalize_signature(all_components.keys)
      new_archetype = find_or_create_archetype(new_signature)

      # 3. Add entity data to the new archetype
      new_row = new_archetype.add(entity_id, all_components, all_changed, touched, @change_tick)
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

      run_added_hooks_for_keys(added_keys, new_archetype, entity_id, new_row) unless added_keys.empty?
      run_changed_hooks_for_keys(changed_keys, new_archetype, entity_id, new_row) unless changed_keys.empty?

      true
    end

    alias_method :add, :add_component

    # Removes a component from an existing entity. This triggers a move between archetypes.
    def remove_component(entity_id, component_class)
      remove_component_internal(entity_id, component_class, false)
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

    def name(entity_id, value = nil)
      if value.nil?
        component = get_component(entity_id, Name)
        component&.value
      else
        set_component(entity_id, Name, Name.new(value))
        value
      end
    end

    def [](entity_id, component_class)
      get_component(entity_id, component_class)
    end

    # Retrieves multiple components from a single entity efficiently.
    # Returns an array of components in the same order as requested, or nil if missing.
    def get_many(entity_id, *component_classes)
      archetype = @entity_archetypes[entity_id]
      return nil unless archetype

      row = @entity_rows[entity_id]
      stores = archetype.component_stores
      components = []

      # Plain while loop, NOT Array.each: DragonRuby's class-level
      # `Array.each` runs the block in a context where a non-local `return`
      # does not return from the enclosing method, so `return nil` inside it
      # silently kept iterating and get_many returned a partial array
      # instead of nil when a component was missing.
      i = 0
      len = component_classes.length
      while i < len
        store = stores[component_classes[i]]
        return nil unless store
        components << store[row]
        i += 1
      end

      components
    end

    # Yields components for a single entity if all are present.
    # Returns true when yielded, nil when missing.
    def with(entity_id, *component_classes)
      components = get_many(entity_id, *component_classes)
      return nil unless components

      if block_given?
        yield(*components)
        true
      else
        components
      end
    end

    # Returns the parent id for a child entity, or nil.
    def parent_of(entity_id)
      parent = get_component(entity_id, Parent)
      parent&.id
    end

    # Returns an array of child ids for a parent entity.
    def children_of(entity_id)
      children = get_component(entity_id, Children)
      children ? children.ids : []
    end

    # Iterates child ids for a parent entity.
    def each_child(entity_id, &blk)
      ids = children_of(entity_id)
      return ids.to_enum(:each) unless blk
      ids.each(&blk)
      nil
    end

    # Sets the parent for a child entity and updates both sides of the relationship.
    def set_parent(child_id, parent_id)
      return clear_parent(child_id) if parent_id.nil?
      return false unless entity_exists?(child_id)
      return false unless entity_exists?(parent_id)
      return false if child_id == parent_id

      current_parent = parent_of(child_id)
      if current_parent && current_parent != parent_id
        remove_child_from_parent(current_parent, child_id)
      end

      children_comp = get_component(parent_id, Children)
      if children_comp
        unless children_comp.ids.include?(child_id)
          children_comp.ids << child_id
          set_component(parent_id, Children, children_comp)
        end
      else
        add_component(parent_id, Children.new([child_id]))
      end

      return true if current_parent == parent_id

      set_component(child_id, Parent, Parent.new(parent_id))
      true
    end

    # Clears the parent for a child entity and updates both sides of the relationship.
    def clear_parent(child_id)
      parent_comp = get_component(child_id, Parent)
      return false unless parent_comp

      remove_component_internal(child_id, Parent, true)
      remove_child_from_parent(parent_comp.id, child_id)
      true
    end

    def add_child(parent_id, child_id)
      set_parent(child_id, parent_id)
    end

    def remove_child(parent_id, child_id)
      return false unless parent_of(child_id) == parent_id
      clear_parent(child_id)
    end

    # Destroys an entity and all of its descendants.
    def destroy_subtree(root_id)
      return false unless entity_exists?(root_id)

      to_visit = [root_id]
      to_destroy = []
      visited = {}

      until to_visit.empty?
        id = to_visit.pop
        next if visited[id]
        visited[id] = true
        to_destroy << id
        children_of(id).each { |child_id| to_visit << child_id }
      end

      destroy(*to_destroy)
      true
    end

    # Sets multiple components on an entity in a single operation, avoiding multiple archetype migrations.
    # If the entity doesn't exist, returns false. Components can be added or replaced.
    def set_components(entity_id, *components)
      old_archetype = @entity_archetypes[entity_id]
      return false unless old_archetype

      row = @entity_rows[entity_id]
      stores = old_archetype.component_stores
      changed_at = old_archetype.component_changed_at

      # Fast path: if no new component types are introduced, there's no
      # migration â€” update in place and skip the full component-hash rebuild
      # and signature normalization. (When migrating, every component is
      # change-bumped; see the slow path / README note below.)
      all_present = true
      Array.each(components) do |c|
        if c.is_a?(Hash)
          c.each_key do |k|
            unless stores.key?(k)
              all_present = false
              break
            end
          end
        elsif !stores.key?(c.class)
          all_present = false
        end
        break unless all_present
      end

      if all_present
        changed_keys = []
        Array.each(components) do |c|
          if c.is_a?(Hash)
            c.each do |k, v|
              stores[k][row] = v
              changed_at[k][row] = @change_tick
              changed_keys << k
            end
          else
            stores[c.class][row] = c
            changed_at[c.class][row] = @change_tick
            changed_keys << c.class
          end
        end
        run_changed_hooks_for_keys(changed_keys, old_archetype, entity_id, row) unless @on_changed.empty?
        return true
      end

      # Slow path: migration required.
      # 1. Gather all current components for the entity
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][row]]
      end

      touched = {}

      # 2. Merge in the new components (overwriting any existing ones)
      Array.each(components) do |c|
        if c.is_a?(Hash)
          all_components.merge!(c)
          c.each { |k, _v| touched[k] = true }
        else
          all_components[c.class] = c
          touched[c.class] = true
        end
      end

      added_keys = []
      changed_keys = []
      Array.each(touched.keys) do |k|
        if old_archetype.component_stores.key?(k)
          changed_keys << k
        else
          added_keys << k
        end
      end

      # 3. Find the new archetype based on the new signature.
      #    (The fast path above already handled the "every key present" case,
      #    so at least one new component type exists here and new_archetype is
      #    always different from old_archetype.)
      new_signature = normalize_signature(all_components.keys)
      new_archetype = find_or_create_archetype(new_signature)

      # 5. Add entity data to the new archetype.
      #    On migration, bump `changed_at` for every component on the entity â€”
      #    not just the touched ones â€” because the archetype move itself is a
      #    visible change. (If you only want "touched" semantics, build your
      #    own archetype manually instead of going through this path.)
      #    Pass `nil` for `changed_hash` so Archetype.add uses @change_tick
      #    uniformly; `touched_hash` still governs which keys are reported to
      #    the `on_changed` hooks.
      new_row = new_archetype.add(entity_id, all_components, nil, touched, @change_tick)
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

      run_added_hooks_for_keys(added_keys, new_archetype, entity_id, new_row) unless added_keys.empty?
      run_changed_hooks_for_keys(changed_keys, new_archetype, entity_id, new_row) unless changed_keys.empty?

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

    # `query` is the per-entity (AoS) view of the world. It behaves the same
    # with or without a block:
    #   - with a block:    yields (entity_id, *components) once per entity
    #   - without a block: returns an Enumerator of (entity_id, *components)
    #
    # For the batched Structure-of-Arrays (SoA) fast path â€” where you get the
    # entity_ids array followed by one parallel array per component â€” use
    # `each_chunk`. (Previously `query`'s block form returned SoA arrays, which
    # was a frequent footgun; `each_chunk` is now the single SoA entry point.)
    def query(*component_classes, with: nil, without: nil, any: nil, changed: nil, &block)
      each_entity(*component_classes, with: with, without: without, any: any, changed: changed, &block)
    end

    # Creates a persistent Query object that avoids signature setup on every call.
    # Aliases: `query_for` (kept for back-compat) and `cached_query` (the
    # recommended name â€” a query whose archetype list is cached).
    def query_for(*component_classes, with: nil, without: nil, any: nil, changed: nil)
      cached_query(*component_classes, with: with, without: without, any: any, changed: changed)
    end

    # Recommended factory for a persistent Query. Same semantics as
    # `query_for`; this name reads better when the query object is stored
    # and re-used across frames.
    def cached_query(*component_classes, with: nil, without: nil, any: nil, changed: nil)
      q = Query.new(self, component_classes, with: with, without: without, any: any, changed: changed)
      @active_queries << q
      q
    end

    # Backward-compatibility shim: prior versions of drecs exposed
    # `concurrent_query` as a (sequential) alternative to `query`. The
    # threading promise was theatrical because mruby is single-threaded.
    # Now it simply forwards to query; use register_native_system /
    # run_native_system for actual SDL3-threaded execution.
    #
    # DEPRECATED: kept as an alias for one minor version, then plan removal.
    # Calling this method emits a warning unless `deprecation_warnings: false`
    # was passed to `World.new`.
    def concurrent_query(*component_classes, threads: nil, with: nil, without: nil, any: nil, changed: nil, &block)
      warn "Drecs: concurrent_query is deprecated; use each_chunk (SoA) / " \
           "each_entity (per-entity) in Ruby, or register_native_system/" \
           "run_native_system for SDL3-threaded execution. Will be removed in " \
           "a future version." if @deprecation_warnings
      _ = threads # accepted and ignored for backwards compatibility
      # Historically yielded SoA arrays, so forward to each_chunk to preserve
      # that block shape for existing callers.
      each_chunk(*component_classes, with: with, without: without, any: any, changed: changed, &block)
    end

    # Native systems: a registered C kernel that drecs runs across SDL3
    # threads. The kernel is authored in a separate DragonRuby C extension
    # using ext/drecs_kernel.h.
    #
    # @example
    #   world.register_native_system(
    #     :integrate,
    #     module_name: "MySystems",
    #     kernel:      :integrate_motion,
    #     reads:       [[Position, :x], [Position, :y], [Velocity, :x], [Velocity, :y]],
    #     writes:      [[Position, :x], [Position, :y]],
    #     threads:     4,
    #   )
    #   world.run_native_system(:integrate, dt: 1.0/60.0)
    def register_native_system(name,
                                module_name:,
                                kernel:,
                                reads: [],
                                writes: [],
                                with: nil, without: nil, any: nil,
                                threads: 4)
      reads  = reads.map { |pair| [pair[0], pair[1].to_sym] }
      writes = writes.map { |pair| [pair[0], pair[1].to_sym] }

      union_classes = (reads.map(&:first) + writes.map(&:first)).uniq
      raise ArgumentError, "register_native_system: needs at least one read or write component" if union_classes.empty?

      # Native kernels read component fields via the C `mrb_iv_get` path, which
      # only works for components whose fields live as @-ivars â€” i.e. classes
      # built with `Drecs.component(...)`. Plain `Struct.new` stores its fields
      # in an internal C array that `mrb_iv_get` can't see, so a Struct-based
      # component would silently feed all-zeros into the kernel. Fail loudly at
      # registration instead.
      struct_components = union_classes.select { |k| k.is_a?(Class) && k < Struct }
      unless struct_components.empty?
        names = struct_components.map { |k| k.name || k.inspect }.join(', ')
        raise ArgumentError,
              "register_native_system(:#{name}): components #{names} are " \
              "Struct-based, but native kernels require fields stored as " \
              "@-ivars. Define them with Drecs.component(...) instead of " \
              "Struct.new(...)."
      end

      @native_systems ||= {}
      @native_systems[name.to_sym] = {
        module_name: module_name.to_s,
        kernel:      kernel.to_sym,
        reads:       reads,
        writes:      writes,
        union:       normalize_signature(union_classes),
        with:        with ? normalize_signature(Array(with)) : nil,
        without:     without ? normalize_signature(Array(without)) : nil,
        any:         any ? normalize_signature(Array(any)) : nil,
        threads:     threads,
        kernel_ptr:  nil, # resolved lazily on first run
      }
      name.to_sym
    end

    def run_native_system(name, dt: 0.0)
      sys = (@native_systems ||= {})[name.to_sym]
      raise ArgumentError, "run_native_system(:#{name}) not registered" unless sys

      unless ::Drecs.const_defined?(:Parallel) && ::Drecs::Parallel.respond_to?(:run_kernel)
        raise RuntimeError,
              "run_native_system(:#{name}): drecs_parallel runtime not loaded. " \
              "Call DR.dlopen 'drecs_parallel'; Drecs::Parallel.load before run."
      end

      sys[:kernel_ptr] ||= ::Drecs::Parallel.kernel_ptr(sys[:module_name], sys[:kernel])
      fn_ptr = sys[:kernel_ptr]

      union_sig   = sys[:union]
      with_sig    = sys[:with]
      without_sig = sys[:without]
      any_sig     = sys[:any]
      threads     = sys[:threads]
      reads       = sys[:reads]
      writes      = sys[:writes]
      change_tick = @change_tick

      @archetypes.each_value do |archetype|
        stores_hash = archetype.component_stores

        # union (reads+writes) all required
        ok = true
        union_sig.each do |klass|
          unless stores_hash.key?(klass)
            ok = false
            break
          end
        end
        next unless ok

        if with_sig
          with_sig.each do |klass|
            unless stores_hash.key?(klass)
              ok = false
              break
            end
          end
          next unless ok
        end

        if without_sig
          without_sig.each do |klass|
            if stores_hash.key?(klass)
              ok = false
              break
            end
          end
          next unless ok
        end

        if any_sig
          any_match = false
          any_sig.each do |klass|
            if stores_hash.key?(klass)
              any_match = true
              break
            end
          end
          next unless any_match
        end

        count = archetype.entity_ids.length
        next if count.zero?

        # Build struct arrays + member names. The C kernel runner
        # (`run_kernel_native`) does the SoA extraction via mrb_iv_get,
        # which is ~6x faster than the Ruby-side `store[i].send(:x)` loop
        # and the difference between 11fps and 60fps at N=20000.
        in_stores   = reads.map  { |klass, _member| stores_hash[klass] }
        in_members  = reads.map  { |_klass, member| member }
        out_stores  = writes.map { |klass, _member| stores_hash[klass] }
        out_members = writes.map { |_klass, member| member }

        ::Drecs::Parallel.run_kernel_native(
          fn_ptr, in_stores, in_members, out_stores, out_members,
          count, dt.to_f, threads
        )

        # Bump change ticks for the written components (the struct iVars
        # were already updated inside run_kernel_native, so we just
        # notify downstream systems that the data changed).
        writes.each do |klass, _member|
          changed_arr = archetype.component_changed_at[klass]
          row = 0
          while row < count
            changed_arr[row] = change_tick
            row += 1
          end
        end
      end

      name.to_sym
    end

    # @return [Hash] registered native systems by name
    def native_systems
      @native_systems ||= {}
    end

    def archetypes
      @archetypes
    end

    # Structure-of-Arrays (SoA) iteration â€” the high-performance batched view.
    # With a block, yields the entity_ids array followed by one parallel array
    # per requested component, once per matching archetype chunk. Without a
    # block, returns an Enumerator of those chunks.
    #
    #   world.each_chunk(Position, Velocity) do |ids, positions, velocities|
    #     i = 0
    #     while i < ids.length
    #       positions[i].x += velocities[i].dx
    #       i += 1
    #     end
    #   end
    def each_chunk(*component_classes, with: nil, without: nil, any: nil, changed: nil, &block)
      unless block_given?
        return Enumerator.new do |yielder|
          each_chunk(*component_classes, with: with, without: without, any: any, changed: changed) do |*args|
            yielder.yield(*args)
          end
        end
      end

      with_components = Array(with)
      changed_components = Array(changed)
      required_components = (component_classes + with_components + changed_components).uniq

      without_components = Array(without)
      any_components = Array(any)

      # Normalize query signature and cache it
      query_sig = normalize_signature(required_components)

      without_sig = without_components.empty? ? nil : normalize_signature(without_components)
      any_sig = any_components.empty? ? nil : normalize_signature(any_components)
      changed_sig = changed_components.empty? ? nil : normalize_signature(changed_components)
      cache_key = [query_sig, without_sig, any_sig, changed_sig].freeze

      # Use cached matching archetypes if available
      matching_archetypes = @query_cache[cache_key] ||= @archetypes.values.select do |archetype|
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

        if ok && without_sig
          k = 0
          lenk = without_sig.length
          while k < lenk
            if stores_hash.key?(without_sig[k])
              ok = false
              break
            end
            k += 1
          end
        end

        if ok && any_sig
          k = 0
          lenk = any_sig.length
          any_match = false
          while k < lenk
            if stores_hash.key?(any_sig[k])
              any_match = true
              break
            end
            k += 1
          end
          ok = false unless any_match
        end
        ok
      end

      # Find all archetypes that contain *at least* the required components.
      # Track iteration depth so `in_iteration?` is accurate inside chunk
      # blocks and deferred commands queued during iteration flush as soon
      # as the outermost iteration ends (matching each_entity's behavior).
      @iterating += 1
      begin
        i = 0
        len = matching_archetypes.length
        while i < len
          archetype = matching_archetypes[i]
          i += 1

          # Skip empty archetypes
          next if archetype.entity_ids.empty?

          # Pre-compute component stores to avoid repeated hash lookups
          stores = component_classes.map { |klass| archetype.component_stores[klass] }

          if changed_sig
            changed_tick = @change_tick
            changed_arrays = changed_sig.map { |klass| archetype.component_changed_at[klass] }

            ids = archetype.entity_ids
            filtered_ids = []
            filtered_stores = Array.new(stores.length) { [] }
            row = 0
            row_len = ids.length

            while row < row_len
              ok = true
              j = 0
              j_len = changed_arrays.length
              while j < j_len
                if changed_arrays[j][row] != changed_tick
                  ok = false
                  break
                end
                j += 1
              end

              if ok
                filtered_ids << ids[row]
                k = 0
                k_len = stores.length
                while k < k_len
                  filtered_stores[k] << stores[k][row]
                  k += 1
                end
              end

              row += 1
            end

            yield(filtered_ids, *filtered_stores) unless filtered_ids.empty?
          else
            # Yield entity_ids first, then component arrays for high-speed iteration
            yield(archetype.entity_ids, *stores)
          end
        end
      ensure
        @iterating -= 1
      end

      flush_defer! if @iterating.zero? && !@deferred.empty?
      nil
    end

    def count(*component_classes, with: nil, without: nil, any: nil, changed: nil)
      total = 0
      each_chunk(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
        total += entity_ids.length
      end
      total
    end

    def ids(*component_classes, with: nil, without: nil, any: nil, changed: nil)
      all_ids = []
      each_chunk(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
        all_ids.concat(entity_ids)
      end
      all_ids
    end

    # Iterates over each entity that has the specified components, yielding the entity_id
    # and the requested components as individual values (not arrays).
    # More ergonomic than query() for per-entity iteration.
    def each_entity(*component_classes, with: nil, without: nil, any: nil, changed: nil, &block)
      unless block_given?
        return Enumerator.new do |yielder|
          each_entity(*component_classes, with: with, without: without, any: any, changed: changed) do |*args|
            yielder.yield(*args)
          end
        end
      end

      @iterating += 1
      begin
        # Per-row iteration is delegated to C when the parallel runtime is
        # loaded. The C path specializes the 0-4 component case so we
        # never allocate an args array per row, and pre-fetches per-store
        # raw pointers. Falls back to the pure-Ruby loop if the C path
        # isn't available (e.g. tests, minimal installs).
        use_c_iter = ::Drecs.const_defined?(:Parallel) &&
                     ::Drecs::Parallel.respond_to?(:each_row)

        if use_c_iter
          each_chunk(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
            ::Drecs::Parallel.each_row(entity_ids, stores, &block)
          end
        else
          each_chunk(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
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
        end
      ensure
        @iterating -= 1
      end

      flush_defer! if @iterating.zero?
    end

    alias_method :each, :each_entity

    # Finds the first entity that has the specified components.
    # Returns [entity_id, component1, component2, ...] or nil if no match found.
    # If a block is given, yields the entity_id and components, returning the entity_id.
    def first_entity(*component_classes, with: nil, without: nil, any: nil, changed: nil, &block)
      each_chunk(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
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

    # Returns the entity_id of the first entity matching the given components
    # (and any filter clauses), or `nil` if no match. Unlike `first_entity`,
    # this returns just the id â€” no components. Useful for "is there one?"
    # checks and to feed into further operations.
    #
    # If a block is given, it's used as a predicate: the entity is yielded
    # (entity_id, *components); return `false` from the block to skip.
    def find_entity(*component_classes, with: nil, without: nil, any: nil, changed: nil, &predicate)
      each_chunk(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
        i = 0
        len = entity_ids.length
        num_stores = stores.length

        while i < len
          entity_id = entity_ids[i]
          components = if num_stores == 0
            []
          elsif num_stores == 1
            [stores[0][i]]
          else
            Array.new(num_stores) { |k| stores[k][i] }
          end

          if predicate
            keep = predicate.call(entity_id, *components)
            return entity_id if keep
          else
            return entity_id
          end

          i += 1
        end
      end

      nil
    end

    # Removes components from a passed query
    # This is safe to use during iteration since it collects entities first.
    def remove_components_from_query(query, *components)
      entities = collect_entity_ids_from(query)
      Array.each(entities) do |id|
        Array.each(components) do |component|
          remove_component(id, component)
        end
      end
    end

    # Destroys all entities that match a passed query.
    # This is safe to use during iteration since it collects entities first.
    def destroy_from_query(query)
      entities = collect_entity_ids_from(query)
      destroy(*entities) unless entities.empty?
    end

    # Convenience wrapper for destroying all entities matching a query signature.
    def destroy_query(*component_classes, with: nil, without: nil, any: nil, changed: nil)
      destroy_from_query(query(*component_classes, with: with, without: without, any: any, changed: changed))
    end

    alias_method :destroy_all, :destroy_query

    def remove_all(component, where: nil)
      query_components = Array(where)
      query_components << component unless query_components.include?(component)
      remove_components_from_query(query(*query_components), component)
      nil
    end

    def clear!
      # When removal hooks are registered we must fire them, so fall back to
      # the per-entity destroy() path (which also handles relationship cleanup).
      unless @on_removed.empty?
        @entity_archetypes.each_with_index do |arch, id|
          destroy(id) if arch
        end
        return nil
      end

      # Fast path: reset the world's tables in bulk instead of paying the
      # per-entity destroy() cost (archetype hole-filling, relationship
      # cleanup, empty-archetype GC) for every entity.
      i = 0
      len = @entity_archetypes.length
      while i < len
        @entity_manager.destroy_entity(i) if @entity_archetypes[i]
        i += 1
      end

      @archetypes = {}
      @entity_archetypes = []
      @entity_rows = []
      @entity_count = 0
      @query_cache = {}
      Array.each(@active_queries) { _1.refresh! }
      nil
    end

    # Debug/inspection methods for understanding world state
    def entity_count
      @entity_count
    end

    def all_entity_ids
      ids = []
      @entity_archetypes.each_with_index do |arch, id|
        ids << id if arch
      end
      ids
    end

    # Sorted, deduplicated list of every component class/symbol that has at
    # least one entity attached. Useful for serialization and inspector UIs.
    # Returns an empty array if the world has no entities.
    def component_classes
      seen = {}
      Array.each(@archetypes.keys) do |signature|
        Array.each(signature) { |k| seen[k] = true }
      end
      seen.keys.sort_by { |k| k.is_a?(Class) ? k.name : k.to_s }
    end

    # Snapshot the entire world â€” entities + components + resources â€” into a
    # Hash that can be passed to `restore` later. Each component is copied
    # via `deep_copy_component` (a fresh instance, with one level of nested
    # Array/Hash field values dup'd) so the snapshot is decoupled from the
    # live component instances. Deeply nested structures beyond one level
    # are still aliased â€” mruby has no Marshal, so a full deep copy isn't
    # available.
    def snapshot
      {
        entities: all_entity_ids.map do |id|
          [id, components_for(id)]
        end,
        resources: @resources ? @resources.dup : {},
        events: @events ? @events.transform_values(&:dup) : {},
        next_entity_id: @entity_manager.instance_variable_get(:@next_id)
      }
    end

    # Restore a snapshot produced by `snapshot`. Existing world state is
    # cleared first. Events and resources are restored as-is; entities are
    # respawned with the recorded components and re-id'd sequentially
    # starting from 0 (the original entity_ids are NOT preserved).
    #
    # Built-in `Parent`/`Children` components are remapped to the new ids,
    # so hierarchies survive the round-trip. If your OWN components store
    # raw entity ids, remap them yourself via the optional block, which
    # receives the { old_id => new_id } mapping:
    #
    #   world.restore(snap) do |id_map|
    #     world.each_entity(Targeting) { |_id, t| t.target = id_map[t.target] }
    #   end
    def restore(snap)
      clear!
      # Reset freed-id pool so restore produces a deterministic,
      # sequential id assignment (0..n-1). Without this, two restores
      # of the same snapshot can produce different id orderings because
      # clear! destroys via swap-remove, and the entity_manager's
      # @freed_ids ends up in non-sequential order.
      @entity_manager.reset_freed_ids!
      @resources = snap[:resources] ? snap[:resources].dup : {}
      @events    = snap[:events]    ? snap[:events].dup    : {}

      id_map = {}
      Array.each(snap[:entities]) do |old_id, components|
        # Copy every component again on the way back in, so the restored
        # world never aliases the snapshot (restoring twice, or mutating
        # the restored world, must not corrupt the snapshot). The hash
        # form handles struct-keyed, symbol-keyed, and mixed entities â€”
        # spawn accepts a { key => component } hash directly.
        copied = {}
        components.each do |key, comp|
          copied[key] = deep_copy_component(key, comp)
        end
        id_map[old_id] = spawn(copied)
      end

      # Remap the built-in relationship components to the new entity ids.
      id_map.each_value do |new_id|
        parent_comp = get_component(new_id, Parent)
        if parent_comp && id_map.key?(parent_comp.id)
          parent_comp.id = id_map[parent_comp.id]
        end

        children_comp = get_component(new_id, Children)
        if children_comp && children_comp.ids
          children_comp.ids.map! { |cid| id_map.fetch(cid, cid) }
        end
      end

      yield id_map if block_given?
      self
    end

    # Development-time integrity check. Walks every archetype and verifies:
    #   - every component store has the same length as entity_ids
    #   - every row in component_changed_at matches a stored value
    #   - the @entity_archetypes / @entity_rows tables are consistent
    # Raises `Drecs::IntegrityError` with a human-readable report if any
    # invariant is violated. Returns `true` if everything checks out.
    def validate!
      issues = []

      Array.each(@archetypes.values) do |archetype|
        entity_count = archetype.entity_ids.length
        Array.each(archetype.component_classes) do |klass|
          store = archetype.component_stores[klass]
          if store.length != entity_count
            issues << "Archetype #{archetype_signature(archetype)}: " \
                      "store for #{klass.inspect} has length #{store.length} " \
                      "(expected #{entity_count})"
          end

          changed = archetype.component_changed_at[klass]
          if changed.nil?
            issues << "Archetype #{archetype_signature(archetype)}: " \
                      "no changed_at store for #{klass.inspect}"
          elsif changed.length != entity_count
            issues << "Archetype #{archetype_signature(archetype)}: " \
                      "changed_at for #{klass.inspect} has length #{changed.length} " \
                      "(expected #{entity_count})"
          end
        end
      end

      i = 0
      while i < @entity_archetypes.length
        arch = @entity_archetypes[i]
        if arch
          row = @entity_rows[i]
          if row.nil?
            issues << "Entity #{i}: archetype present but row index is nil"
          elsif row >= arch.entity_ids.length || arch.entity_ids[row] != i
            issues << "Entity #{i}: row index #{row} doesn't match archetype"
          end
        end
        i += 1
      end

      if issues.empty?
        true
      else
        raise IntegrityError, "Drecs integrity check failed:\n  - " + issues.join("\n  - ")
      end
    end

    # Returns a copied snapshot of an entity's components as
    # { component_key => component }. Both struct-style (Class key) and
    # hash-style (Symbol key) components are copied via `deep_copy_component`
    # so the returned hash is decoupled from live world state â€” this is what
    # makes `snapshot` safe to hold across subsequent mutations. (Copies are
    # one level deep: nested Array/Hash field values are dup'd, anything
    # nested deeper is still aliased.)
    def components_for(entity_id)
      archetype = @entity_archetypes[entity_id]
      return nil unless archetype

      row = @entity_rows[entity_id]
      archetype.component_classes.to_h do |klass|
        instance = archetype.component_stores[klass][row]
        [klass, deep_copy_component(klass, instance)]
      end
    end

    # Returns a multi-line String describing every archetype and a sample of
    # its entities. Useful for printing from the DragonRuby console for ad-hoc
    # inspection.
    def dump
      lines = ["Drecs::World dump â€” #{entity_count} entities, #{archetype_count} archetypes"]
      Array.each(@archetypes.values) do |archetype|
        next if archetype.entity_ids.empty?
        sig = archetype_signature(archetype)
        lines << "  Archetype [#{sig}]: #{archetype.entity_ids.length} entities"
        # The first N entity_ids occupy rows 0..N-1, so the row index is just
        # the position â€” no need for an O(n) entity_ids.index lookup per cell.
        sample_count = [3, archetype.entity_ids.length].min
        row = 0
        while row < sample_count
          id = archetype.entity_ids[row]
          comp_str = archetype.component_classes.map { |k| "#{k}=#{archetype.component_stores[k][row].inspect}" }.join(', ')
          lines << "    ##{id} { #{comp_str} }"
          row += 1
        end
      end
      lines << "  Resources: #{@resources ? @resources.keys.length : 0}"
      lines << "  Events:    #{@events ? @events.values.map(&:length).sum : 0} buffered"
      lines.join("\n")
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

    def resource!(resource_or_key, value = nil)
      insert_resource(resource_or_key, value)
    end

    # Retrieve a resource by class or symbol key
    def resource(resource_or_key)
      @resources&.[](resource_or_key)
    end

    # Remove a resource by class or symbol key
    def remove_resource(resource_or_key)
      @resources&.delete(resource_or_key)
    end

    # Like `resource`, but raises `KeyError` if the key isn't present.
    # Accepts an optional block to compute a default instead of raising.
    #
    #   world.fetch_resource(:score)             # raises if missing
    #   world.fetch_resource(:score) { 0 }       # returns 0 if missing
    def fetch_resource(resource_or_key)
      @resources ||= {}
      if @resources.key?(resource_or_key)
        @resources[resource_or_key]
      elsif block_given?
        yield resource_or_key
      else
        raise KeyError, "no resource registered for #{resource_or_key.inspect}"
      end
    end

    # True if a resource has been registered for the given key.
    def has_resource?(resource_or_key)
      @resources&.key?(resource_or_key) || false
    end

    def send_event(event_or_key, value = nil)
      @events ||= {}
      if value.nil?
        evt = event_or_key
        key = evt.is_a?(Hash) ? evt.keys.first : evt.class
        (@events[key] ||= []) << evt
        evt
      else
        key = event_or_key
        evt = value
        (@events[key] ||= []) << evt
        evt
      end
    end

    def each_event(event_class_or_key, &block)
      unless block_given?
        return Enumerator.new do |yielder|
          each_event(event_class_or_key) { |evt| yielder << evt }
        end
      end

      events = @events&.[](event_class_or_key)
      return nil unless events && !events.empty?

      i = 0
      len = events.length
      while i < len
        evt = events[i]
        yield(evt)
        i += 1
      end
      nil
    end

    def clear_events!(event_class_or_key = nil)
      events = @events
      return nil unless events && !events.empty?

      if event_class_or_key.nil?
        events.each_value { |arr| arr.clear }
      else
        arr = events[event_class_or_key]
        arr.clear if arr
      end
      nil
    end

    # True if at least one event has been buffered for the given class/key
    # since the last `clear_events!` (or `advance_change_tick!`).
    def event?(event_class_or_key)
      arr = @events&.[](event_class_or_key)
      !arr.nil? && !arr.empty?
    end

    # Number of buffered events for the given class/key. 0 if none.
    def event_count(event_class_or_key)
      arr = @events&.[](event_class_or_key)
      arr ? arr.length : 0
    end

    # Snapshot of all buffered events for the given class/key as an Array.
    # Safe to mutate; does not consume the buffer. Use `each_event` to drain
    # without copying.
    def events(event_class_or_key)
      arr = @events&.[](event_class_or_key)
      arr ? arr.dup : []
    end

    private

    # Collect entity ids from either query shape:
    #   - per-entity (each_entity/query Enumerator): yields (id, *components)
    #   - SoA (Query#each / each_chunk): yields (ids_array, *stores)
    # Implemented with an explicit each loop â€” DragonRuby's mruby
    # Enumerator#flat_map is broken (it only yields the first element), which
    # made remove_all/destroy_from_query silently skip all but one entity.
    def collect_entity_ids_from(query)
      entities = []
      query.each do |*args|
        first = args.first
        if first.is_a?(Array)
          entities.concat(first)
        else
          entities << first
        end
      end
      entities
    end

    # Copy a single component instance for snapshot/restore. Class-keyed
    # components are rebuilt via `key.new(*values)` to guarantee a brand-new
    # instance (`.dup` sometimes returns the same object in some mruby/Struct
    # combos); nested Array/Hash field values are dup'd one level deep so
    # collections like `Children.ids` don't stay aliased to the source.
    def deep_copy_component(key, instance)
      if key.is_a?(Class)
        values = instance.values
        i = 0
        len = values.length
        while i < len
          v = values[i]
          values[i] = v.dup if v.is_a?(Array) || v.is_a?(Hash)
          i += 1
        end
        key.new(*values)
      elsif instance.is_a?(Hash)
        copied = {}
        instance.each do |k, v|
          copied[k] = (v.is_a?(Array) || v.is_a?(Hash)) ? v.dup : v
        end
        copied
      else
        instance
      end
    end

    # Pretty-print a single archetype's signature as "[A, B, C]" with each
    # class/symbol rendered as `ClassName` or `:sym`.
    def archetype_signature(archetype)
      '[' + archetype.component_classes.map { |k|
        k.is_a?(Class) ? k.name : k.inspect
      }.join(', ') + ']'
    end

    def remove_child_from_parent(parent_id, child_id)
      return false unless parent_id
      children_comp = get_component(parent_id, Children)
      return false unless children_comp && children_comp.ids

      index = children_comp.ids.index(child_id)
      return false unless index

      children_comp.ids.delete_at(index)

      if children_comp.ids.empty?
        remove_component_internal(parent_id, Children, true)
      else
        set_component(parent_id, Children, children_comp)
      end

      true
    end

    def remove_component_internal(entity_id, component_class, suppress_relationships)
      old_archetype = @entity_archetypes[entity_id]
      return false unless old_archetype
      return false unless old_archetype.component_stores.key?(component_class)

      row = @entity_rows[entity_id]
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][row]]
      end

      all_changed = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_changed_at[klass][row]]
      end

      removed_component = old_archetype.component_stores[component_class][row]

      unless suppress_relationships
        if component_class == Parent
          parent_id = removed_component&.id
          remove_child_from_parent(parent_id, entity_id) if parent_id
        elsif component_class == Children
          if removed_component && removed_component.ids
            Array.each(removed_component.ids) do |child_id|
              child_parent = get_component(child_id, Parent)
              remove_component_internal(child_id, Parent, true) if child_parent && child_parent.id == entity_id
            end
          end
        end
      end

      all_components.delete(component_class)
      all_changed.delete(component_class)
      new_signature = normalize_signature(all_components.keys)
      new_archetype = find_or_create_archetype(new_signature)

      new_row = new_archetype.add(entity_id, all_components, all_changed, nil, @change_tick)
      @entity_archetypes[entity_id] = new_archetype
      @entity_rows[entity_id] = new_row

      moved_entity_id, is_empty = old_archetype.remove(row)

      if moved_entity_id && moved_entity_id != entity_id
        @entity_rows[moved_entity_id] = row
      end

      cleanup_empty_archetypes([old_archetype]) if is_empty

      run_removed_hook(component_class, entity_id, removed_component)

      true
    end

    def run_added_hooks_for_row(archetype, entity_id, row)
      hooks = @on_added
      classes = archetype.component_classes
      stores = archetype.stores_list
      i = 0
      len = classes.length
      while i < len
        klass = classes[i]
        list = hooks[klass]
        if list && !list.empty?
          comp = stores[i][row]
          j = 0
          j_len = list.length
          while j < j_len
            list[j].call(self, entity_id, comp)
            j += 1
          end
        end
        i += 1
      end
    end

    def run_added_hooks_for_keys(keys, archetype, entity_id, row)
      hooks = @on_added
      # Skip the normalize_signature allocation when no registered hook
      # matches any of the touched keys (the common case).
      return unless keys.any? { |k| hooks.key?(k) }
      classes = normalize_signature(keys)
      Array.each(classes) do |klass|
        list = hooks[klass]
        next unless list && !list.empty?
        component = archetype.component_stores[klass][row]
        j = 0
        j_len = list.length
        while j < j_len
          list[j].call(self, entity_id, component)
          j += 1
        end
      end
    end

    def run_changed_hooks_for_keys(keys, archetype, entity_id, row)
      hooks = @on_changed
      # Skip the normalize_signature allocation when no registered hook
      # matches any of the touched keys (the common case).
      return unless keys.any? { |k| hooks.key?(k) }
      classes = normalize_signature(keys)
      Array.each(classes) do |klass|
        list = hooks[klass]
        next unless list && !list.empty?
        component = archetype.component_stores[klass][row]
        j = 0
        j_len = list.length
        while j < j_len
          list[j].call(self, entity_id, component)
          j += 1
        end
      end
    end

    def run_removed_hook(component_class, entity_id, component)
      list = @on_removed[component_class]
      return nil unless list && !list.empty?
      i = 0
      len = list.length
      while i < len
        list[i].call(self, entity_id, component)
        i += 1
      end
      nil
    end

    def find_or_create_archetype(signature)
      normalized = signature.frozen? ? signature : normalize_signature(signature)
      if !@archetypes.key?(normalized)
        new_archetype = Archetype.new(normalized)
        @archetypes[normalized] = new_archetype
        invalidate_affected_queries(new_archetype)
        Array.each(@active_queries) { _1.refresh! }
      end
      @archetypes[normalized]
    end

    # Only invalidate cached queries that could potentially match the new archetype
    def invalidate_affected_queries(new_archetype)
      return if @query_cache.empty?
      
      new_stores = new_archetype.component_stores
      @query_cache.delete_if do |cache_key, _|
        query_sig, without_sig, any_sig, _changed_sig = cache_key
        
        # Check if archetype has all required components
        i = 0
        len = query_sig.length
        could_match = true
        while i < len
          unless new_stores.key?(query_sig[i])
            could_match = false
            break
          end
          i += 1
        end
        
        # If required components match, check without filter
        if could_match && without_sig
          i = 0
          len = without_sig.length
          while i < len
            if new_stores.key?(without_sig[i])
              could_match = false
              break
            end
            i += 1
          end
        end
        
        # If still could match, check any filter
        if could_match && any_sig
          i = 0
          len = any_sig.length
          any_match = false
          while i < len
            if new_stores.key?(any_sig[i])
              any_match = true
              break
            end
            i += 1
          end
          could_match = false unless any_match
        end
        
        # Delete from cache if this archetype could match the query
        could_match
      end
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
