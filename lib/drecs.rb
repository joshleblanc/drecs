module Drecs
  module SignatureHelper 
    def normalize_signature(component_classes)
      component_classes.sort_by { |c| c.is_a?(Class) ? c.name : c.to_s }.freeze
    end
  end

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

  class DebugOverlay
    DEFAULT_MAX_LINES = 24
    PANEL_PADDING = 12
    LIST_ROW_HEIGHT = 20
    LEFT_PANEL_WIDTH = 320
    TOP_BAR_HEIGHT = 40

    def initialize(world, toggle_key: :f1)
      @world = world
      @toggle_key = toggle_key
      @enabled = false
      @entity_index = 0
      @selected_entity_id = nil
      @scroll_offset = 0
      @filter_text = ""
      @filter_active = false
      @components_expanded = true
      @systems_expanded = true
      @component_header_rect = nil
      @system_header_rect = nil
      @group_expanded = {}
      @edit_target = nil
      @edit_buffer = ""
      @field_rects = []
    end

    def enabled?
      @enabled
    end

    def tick(args)
      keyboard = args.inputs.keyboard
      if key_pressed?(keyboard, @toggle_key)
        @enabled = !@enabled
      end

      return unless @enabled

      handle_keyboard_input(args)
      handle_mouse_input(args)

      render(args)
    end

    private

    def handle_keyboard_input(args)
      keyboard = args.inputs.keyboard
      if keyboard.key_down.up
        @entity_index -= 1
      elsif keyboard.key_down.down
        @entity_index += 1
      end
      entities = filtered_entity_ids
      @entity_index = 0 if @entity_index.negative?
      @entity_index = entities.length - 1 if @entity_index >= entities.length
      @selected_entity_id = entities[@entity_index] if entities[@entity_index]
      if @edit_target
        if keyboard.key_down.backspace && !@edit_buffer.empty?
          @edit_buffer = @edit_buffer[0..-2]
        elsif keyboard.key_down.enter
          commit_edit
        elsif keyboard.key_down.escape
          clear_edit
        else
          if (text = args.inputs.text)
            text = text.join if text.is_a?(Array)
            @edit_buffer += text if text && !text.empty?
          end
        end
      else
        if keyboard.key_down.backspace && @filter_active && !@filter_text.empty?
          @filter_text = @filter_text[0..-2]
        end
        if @filter_active && (text = args.inputs.text)
          text = text.join if text.is_a?(Array)
          @filter_text += text if text && !text.empty?
        end
      end
    end

    def handle_mouse_input(args)
      mouse = args.inputs.mouse
      return unless mouse

      if mouse.click
        @filter_active = point_in_rect?(mouse.x, mouse.y, filter_rect(args))
        if @component_header_rect && point_in_rect?(mouse.x, mouse.y, @component_header_rect)
          @components_expanded = !@components_expanded
        elsif @system_header_rect && point_in_rect?(mouse.x, mouse.y, @system_header_rect)
          @systems_expanded = !@systems_expanded
        end

        if (field = field_for_point(mouse.x, mouse.y))
          start_edit(field)
          return
        end
      end

      if (wheel_y = mouse_wheel_y(mouse))
        @scroll_offset -= wheel_y * LIST_ROW_HEIGHT
      end

      return unless mouse.click

      rect = entity_list_rect(args)
      if point_in_rect?(mouse.x, mouse.y, rect)
        row_idx = ((rect[:y] + rect[:h] - mouse.y - LIST_ROW_HEIGHT) / LIST_ROW_HEIGHT).floor
        row_idx = 0 if row_idx.negative?
        rows = build_entity_rows(filtered_entity_ids)
        row_index = (@scroll_offset / LIST_ROW_HEIGHT).floor + row_idx
        row = rows[row_index]
        return unless row

        if row[:type] == :group
          @group_expanded[row[:key]] = !row[:expanded]
        elsif row[:type] == :entity
          entities = filtered_entity_ids
          @entity_index = entities.index(row[:id]) || 0
          @selected_entity_id = row[:id]
        end
      end
    end

    def key_pressed?(keyboard, key)
      return keyboard.key_down.f1 if key == :f1
      return keyboard.key_down.f2 if key == :f2
      return keyboard.key_down.f3 if key == :f3
      return keyboard.key_down.f4 if key == :f4
      return keyboard.key_down.f5 if key == :f5
      return keyboard.key_down.f6 if key == :f6
      return keyboard.key_down.f7 if key == :f7
      return keyboard.key_down.f8 if key == :f8
      return keyboard.key_down.f9 if key == :f9
      return keyboard.key_down.f10 if key == :f10
      return keyboard.key_down.f11 if key == :f11
      return keyboard.key_down.f12 if key == :f12
      false
    end

    def render(args)
      w = args.grid.w
      h = args.grid.h
      args.outputs.solids << { x: 0, y: 0, w: w, h: h, r: 0, g: 0, b: 0, a: 180 }

      labels = args.outputs.labels

      render_top_bar(labels, w, h)
      render_left_panel(args, labels, w, h)
      render_right_panel(args, labels, w, h)
    end

    def render_top_bar(labels, w, h)
      labels << {
        x: PANEL_PADDING,
        y: h - PANEL_PADDING,
        text: "Drecs Debug Overlay (#{@toggle_key.to_s.upcase} to toggle)",
        size_enum: 4,
        r: 255, g: 255, b: 255
      }
      labels << {
        x: w - PANEL_PADDING,
        y: h - PANEL_PADDING,
        text: "Entities: #{@world.entity_count} | Archetypes: #{@world.archetype_count} | Systems: #{system_names.length}",
        size_enum: 2,
        alignment_enum: 2,
        r: 220, g: 220, b: 220
      }
    end

    def render_left_panel(args, labels, w, h)
      rect = left_panel_rect(args)
      args.outputs.solids << { x: rect[:x], y: rect[:y], w: rect[:w], h: rect[:h], r: 10, g: 10, b: 20, a: 220 }

      filter = filter_rect(args)
      args.outputs.solids << { x: filter[:x], y: filter[:y], w: filter[:w], h: filter[:h], r: 30, g: 30, b: 50, a: 240 }
      labels << {
        x: filter[:x] + 8,
        y: filter[:y] + filter[:h] - 8,
        text: @filter_text.empty? ? "Filter components..." : @filter_text,
        size_enum: 2,
        r: @filter_active ? 255 : 180,
        g: @filter_active ? 255 : 180,
        b: @filter_active ? 200 : 180
      }

      list = entity_list_rect(args)
      entities = filtered_entity_ids
      return if entities.empty?

      rows = build_entity_rows(entities)
      @scroll_offset = [[@scroll_offset, 0].max, [rows.length * LIST_ROW_HEIGHT - list[:h], 0].max].min

      first_row = (@scroll_offset / LIST_ROW_HEIGHT).floor
      y = list[:y] + list[:h] - LIST_ROW_HEIGHT + 4
      visible_rows = (list[:h] / LIST_ROW_HEIGHT).floor

      (0...visible_rows).each do |row|
        idx = first_row + row
        break if idx >= rows.length
        row_data = rows[idx]

        if row_data[:type] == :group
          labels << {
            x: list[:x] + 8,
            y: y,
            text: "#{row_data[:expanded] ? '▼' : '▶'} #{row_data[:label]} (#{row_data[:count]})",
            size_enum: 2,
            r: 150, g: 200, b: 255
          }
        else
          is_selected = row_data[:id] == (@selected_entity_id || entities[@entity_index])
          labels << {
            x: list[:x] + 20,
            y: y,
            text: "#{is_selected ? '>' : ' '} #{row_data[:id]}",
            size_enum: 2,
            r: is_selected ? 255 : 200,
            g: is_selected ? 255 : 200,
            b: is_selected ? 140 : 200
          }
        end
        y -= LIST_ROW_HEIGHT
      end
    end

    def render_right_panel(args, labels, w, h)
      rect = right_panel_rect(args)
      args.outputs.solids << { x: rect[:x], y: rect[:y], w: rect[:w], h: rect[:h], r: 15, g: 15, b: 25, a: 220 }

      entities = filtered_entity_ids
      return if entities.empty?

      selected_id = @selected_entity_id || entities[@entity_index]
      y = rect[:y] + rect[:h] - PANEL_PADDING

      labels << section_label("Entity #{selected_id}", y, rect[:x] + PANEL_PADDING)
      y -= LIST_ROW_HEIGHT

      parent_id = @world.parent_of(selected_id)
      labels << info_label("Parent: #{parent_id || '-'}", y, rect[:x] + PANEL_PADDING)
      y -= LIST_ROW_HEIGHT
      labels << info_label("Children: #{@world.children_of(selected_id).join(', ')}", y, rect[:x] + PANEL_PADDING)
      y -= LIST_ROW_HEIGHT * 2

      labels << section_label("Components#{@components_expanded ? '' : ' (collapsed)'}", y, rect[:x] + PANEL_PADDING)
      @component_header_rect = {
        x: rect[:x] + PANEL_PADDING,
        y: y - LIST_ROW_HEIGHT + 6,
        w: rect[:w] - PANEL_PADDING * 2,
        h: LIST_ROW_HEIGHT
      }
      y -= LIST_ROW_HEIGHT
      if @components_expanded
        @field_rects = []
        comps = @world.components_for(selected_id) || {}
        comps.each do |klass, component|
          labels << {
            x: rect[:x] + PANEL_PADDING,
            y: y,
            text: format_component_key(klass),
            size_enum: 2,
            r: 150, g: 200, b: 255
          }
          y -= LIST_ROW_HEIGHT

          fields = component_fields(component)
          fields.each do |field, value|
            display_value = value.inspect
            display_value = display_value.length > 60 ? "#{display_value[0, 57]}..." : display_value
            editing = editing_field?(selected_id, klass, field)
            text = editing ? "#{field}: [#{@edit_buffer}]" : "#{field}: #{display_value}"
            labels << {
              x: rect[:x] + PANEL_PADDING * 2,
              y: y,
              text: text,
              size_enum: 2,
              r: editing ? 255 : 220,
              g: editing ? 255 : 220,
              b: editing ? 180 : 220
            }
            @field_rects << {
              rect: {
                x: rect[:x] + PANEL_PADDING * 2,
                y: y - LIST_ROW_HEIGHT + 4,
                w: rect[:w] - PANEL_PADDING * 3,
                h: LIST_ROW_HEIGHT
              },
              entity_id: selected_id,
              comp_key: klass,
              field: field,
              value: value
            }
            y -= LIST_ROW_HEIGHT
            break if y <= rect[:y] + PANEL_PADDING + LIST_ROW_HEIGHT * 6
          end

          break if y <= rect[:y] + PANEL_PADDING + LIST_ROW_HEIGHT * 6
        end
      end

      y -= LIST_ROW_HEIGHT
      labels << section_label("Systems#{@systems_expanded ? '' : ' (collapsed)'}", y, rect[:x] + PANEL_PADDING)
      @system_header_rect = {
        x: rect[:x] + PANEL_PADDING,
        y: y - LIST_ROW_HEIGHT + 6,
        w: rect[:w] - PANEL_PADDING * 2,
        h: LIST_ROW_HEIGHT
      }
      y -= LIST_ROW_HEIGHT
      if @systems_expanded
        system_names.each do |name|
          labels << {
            x: rect[:x] + PANEL_PADDING,
            y: y,
            text: name,
            size_enum: 2,
            r: 180, g: 220, b: 255
          }
          y -= LIST_ROW_HEIGHT
          break if y <= rect[:y] + PANEL_PADDING
        end
      end
    end

    def format_component_key(key)
      key.is_a?(Class) ? key.name : key.to_s
    end

    def filtered_entity_ids
      entities = @world.all_entity_ids
      entities.sort!
      return entities if @filter_text.empty?

      entities.select do |entity_id|
        comps = @world.components_for(entity_id) || {}
        comps.any? { |klass, _comp| format_component_key(klass).downcase.include?(@filter_text.downcase) }
      end
    end

    def system_names
      names = []
      names.concat(@world.scheduled_system_names) if @world.respond_to?(:scheduled_system_names)
      names.concat(@world.systems.map { |sys| sys.class.name || sys.to_s })
      names.compact.uniq
    end

    def left_panel_rect(args)
      h = args.grid.h
      {
        x: PANEL_PADDING,
        y: PANEL_PADDING,
        w: LEFT_PANEL_WIDTH,
        h: h - TOP_BAR_HEIGHT - PANEL_PADDING * 2
      }
    end

    def right_panel_rect(args)
      h = args.grid.h
      w = args.grid.w
      {
        x: LEFT_PANEL_WIDTH + PANEL_PADDING * 2,
        y: PANEL_PADDING,
        w: w - LEFT_PANEL_WIDTH - PANEL_PADDING * 3,
        h: h - TOP_BAR_HEIGHT - PANEL_PADDING * 2
      }
    end

    def filter_rect(args)
      rect = left_panel_rect(args)
      {
        x: rect[:x],
        y: rect[:y] + rect[:h] - LIST_ROW_HEIGHT - PANEL_PADDING,
        w: rect[:w],
        h: LIST_ROW_HEIGHT + 4
      }
    end

    def entity_list_rect(args)
      rect = left_panel_rect(args)
      filter = filter_rect(args)
      {
        x: rect[:x],
        y: rect[:y],
        w: rect[:w],
        h: filter[:y] - rect[:y] - PANEL_PADDING
      }
    end

    def point_in_rect?(x, y, rect)
      x >= rect[:x] && x <= rect[:x] + rect[:w] && y >= rect[:y] && y <= rect[:y] + rect[:h]
    end

    def mouse_wheel_y(mouse)
      return nil unless mouse.respond_to?(:wheel)
      wheel = mouse.wheel
      return nil unless wheel
      wheel.respond_to?(:y) ? wheel.y : nil
    end

    def header_label(text, y, x = 20)
      { x: x, y: y, text: text, size_enum: 4, r: 255, g: 255, b: 255 }
    end

    def section_label(text, y, x = 20)
      { x: x, y: y, text: text, size_enum: 3, r: 150, g: 200, b: 255 }
    end

    def info_label(text, y, x = 20)
      { x: x, y: y, text: text, size_enum: 2, r: 220, g: 220, b: 220 }
    end

    def build_entity_rows(entities)
      rows = []
      entity_set = entities.to_h { |id| [id, true] }

      @world.archetypes.each_value do |archetype|
        ids = archetype.entity_ids.select { |id| entity_set[id] }
        next if ids.empty?

        signature = archetype.component_classes
        label = signature.map { |k| format_component_key(k) }.join(", ")
        key = signature.join("|")
        expanded = @group_expanded.fetch(key, true)

        rows << { type: :group, key: key, label: label.empty? ? "(empty)" : label, count: ids.length, expanded: expanded }
        if expanded
          ids.each do |id|
            rows << { type: :entity, id: id, group: key }
          end
        end
      end

      rows
    end

    def component_fields(component)
      if component.is_a?(Hash)
        component.map { |k, v| [k, v] }
      elsif component.is_a?(Struct)
        component.members.map { |m| [m, component[m]] }
      else
        [[:value, component]]
      end
    end

    def field_for_point(x, y)
      @field_rects.find { |field| point_in_rect?(x, y, field[:rect]) }
    end

    def start_edit(field)
      @edit_target = field
      @edit_buffer = field[:value].to_s
    end

    def clear_edit
      @edit_target = nil
      @edit_buffer = ""
    end

    def editing_field?(entity_id, comp_key, field)
      @edit_target && @edit_target[:entity_id] == entity_id && @edit_target[:comp_key] == comp_key && @edit_target[:field] == field
    end

    def commit_edit
      return unless @edit_target

      entity_id = @edit_target[:entity_id]
      comp_key = @edit_target[:comp_key]
      field = @edit_target[:field]
      original = @edit_target[:value]

      value = coerce_value(@edit_buffer, original)
      component = @world.get_component(entity_id, comp_key)
      if component.is_a?(Hash)
        component[field] = value
        @world.set_component(entity_id, comp_key, component)
      elsif component.is_a?(Struct)
        updated = component.dup
        updated[field] = value
        @world.set_component(entity_id, updated)
      end

      clear_edit
    end

    def coerce_value(text, original)
      return text.to_i if original.is_a?(Integer)
      return text.to_f if original.is_a?(Float)
      if original.is_a?(TrueClass) || original.is_a?(FalseClass)
        return text.strip.downcase == "true"
      end
      text
    end
  end

  # Relationship components for parent/child graphs.
  Parent = Struct.new(:id)
  Children = Struct.new(:ids)

  def self.bundle(*component_keys)
    Bundle.new(component_keys)
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
    
    def initialize(reuse_entity_ids: true, validate_components: false, debug_overlay: true)
      @entity_manager = EntityManager.new(reuse_entity_ids: reuse_entity_ids)
      @systems = []
      @scheduled_systems = {}
      @compiled_schedule = nil
      @schedule_dirty = false

      @change_tick = 0

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
      @events = {}

      @on_added = {}
      @on_removed = {}
      @on_changed = {}

      @iterating = 0

      @debug_overlay = debug_overlay ? DebugOverlay.new(self) : nil
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

    def commands
      buffer = Commands.new
      if block_given?
        yield buffer
        if in_iteration?
          defer { |w| buffer.apply(w) }
        else
          buffer.apply(self)
        end
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
      @debug_overlay&.tick(args)
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

      # 1. Gather all current components for the entity
      row = @entity_rows[entity_id]
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

      # 2. Find the new archetype based on the new signature
      new_signature = normalize_signature(all_components.keys)
      new_archetype = find_or_create_archetype(new_signature)

      # If we're already in the right archetype, just update components in place
      if old_archetype == new_archetype
        if component_value.nil?
          if component_key_or_component.is_a?(Hash)
            Array.each(component_key_or_component) do |k, v|
              new_archetype.component_stores[k][row] = v
              new_archetype.component_changed_at[k][row] = @change_tick
            end
          else
            new_archetype.component_stores[component_key_or_component.class][row] = component_key_or_component
            new_archetype.component_changed_at[component_key_or_component.class][row] = @change_tick
          end
        else
          new_archetype.component_stores[component_key_or_component][row] = component_value
          new_archetype.component_changed_at[component_key_or_component][row] = @change_tick
        end

        run_changed_hooks_for_keys(changed_keys, new_archetype, entity_id, row) unless changed_keys.empty?

        return true
      end

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

      Array.each(component_classes) do |klass|
        store = stores[klass]
        return nil unless store
        components << store[row]
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

      # 1. Gather all current components for the entity
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][row]]
      end

      all_changed = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_changed_at[klass][row]]
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

      # 3. Find the new archetype based on the new signature
      new_signature = normalize_signature(all_components.keys)
      new_archetype = find_or_create_archetype(new_signature)

      # 4. If we're already in the right archetype, just update components in place
      if old_archetype == new_archetype
        Array.each(components) do |c|
          if c.is_a?(Hash)
            c.each do |k, v|
              new_archetype.component_stores[k][row] = v
              new_archetype.component_changed_at[k][row] = @change_tick
            end
          else
            new_archetype.component_stores[c.class][row] = c
            new_archetype.component_changed_at[c.class][row] = @change_tick
          end
        end

        run_changed_hooks_for_keys(changed_keys, new_archetype, entity_id, row) unless changed_keys.empty?
        return true
      end

      # 5. Add entity data to the new archetype
      new_row = new_archetype.add(entity_id, all_components, all_changed, touched, @change_tick)
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

    # The query interface for systems.
    # Yields entity_ids array first, followed by component arrays.
    def query(*component_classes, with: nil, without: nil, any: nil, changed: nil, &block)
      # If no block is given, return an enumerator that will yield single entities.
      # This provides an ergonomic "AoS" view (e.g. query(A).first -> [id, a])
      # while keeping the optimized "SoA" view for the block form.
      unless block_given?
        return each_entity(*component_classes, with: with, without: without, any: any, changed: changed)
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
    end

    # Creates a persistent Query object that avoids signature setup on every call.
    def query_for(*component_classes, with: nil, without: nil, any: nil, changed: nil)
      q = Query.new(self, component_classes, with: with, without: without, any: any, changed: changed)
      @active_queries << q
      q
    end

    def archetypes
      @archetypes
    end

    def each_chunk(*component_classes, with: nil, without: nil, any: nil, changed: nil, &block)
      unless block_given?
        return Enumerator.new do |yielder|
          each_chunk(*component_classes, with: with, without: without, any: any, changed: changed) do |*args|
            yielder.yield(*args)
          end
        end
      end

      query(*component_classes, with: with, without: without, any: any, changed: changed, &block)
    end

    def count(*component_classes, with: nil, without: nil, any: nil, changed: nil)
      total = 0
      query(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
        total += entity_ids.length
      end
      total
    end

    def ids(*component_classes, with: nil, without: nil, any: nil, changed: nil)
      all_ids = []
      query(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
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
        query(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
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
      query(*component_classes, with: with, without: without, any: any, changed: changed) do |entity_ids, *stores|
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
      Array.each(@entity_archetypes) do |arch, id|
        destroy(id) if arch
      end
      nil
    end

    # Debug/inspection methods for understanding world state
    def entity_count
      @entity_count
    end

    def debug_overlay
      @debug_overlay
    end

    def enable_debug_overlay!(toggle_key: :f1)
      @debug_overlay = DebugOverlay.new(self, toggle_key: toggle_key)
    end

    def disable_debug_overlay!
      @debug_overlay = nil
    end

    def all_entity_ids
      ids = []
      @entity_archetypes.each_with_index do |arch, id|
        ids << id if arch
      end
      ids
    end

    def components_for(entity_id)
      archetype = @entity_archetypes[entity_id]
      return nil unless archetype

      row = @entity_rows[entity_id]
      archetype.component_classes.to_h do |klass|
        [klass, archetype.component_stores[klass][row]]
      end
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

    private

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

      row = @entity_rows[entity_id]
      all_components = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_stores[klass][row]]
      end

      all_changed = old_archetype.component_classes.to_h do |klass|
        [klass, old_archetype.component_changed_at[klass][row]]
      end

      return false unless all_components.key?(component_class)

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
