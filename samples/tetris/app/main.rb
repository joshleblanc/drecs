GRID_WIDTH = 10
GRID_HEIGHT = 20
CELL_SIZE = 30
GRID_X = 400
GRID_Y = 60

SHAPES = {
  I: { blocks: [[0, 0], [1, 0], [2, 0], [3, 0]], color: { r: 0, g: 255, b: 255 } },
  O: { blocks: [[0, 0], [1, 0], [0, 1], [1, 1]], color: { r: 255, g: 255, b: 0 } },
  T: { blocks: [[1, 0], [0, 1], [1, 1], [2, 1]], color: { r: 128, g: 0, b: 128 } },
  S: { blocks: [[1, 0], [2, 0], [0, 1], [1, 1]], color: { r: 0, g: 255, b: 0 } },
  Z: { blocks: [[0, 0], [1, 0], [1, 1], [2, 1]], color: { r: 255, g: 0, b: 0 } },
  J: { blocks: [[0, 0], [0, 1], [1, 1], [2, 1]], color: { r: 0, g: 0, b: 255 } },
  L: { blocks: [[2, 0], [0, 1], [1, 1], [2, 1]], color: { r: 255, g: 165, b: 0 } }
}

def tick(args)
  args.state.world ||= setup(args)

  if args.state.game_over
    handle_game_over_input(args)
  else
    handle_input(args)
    update_game(args)
  end

  render(args)
end

def setup(args)
  world = Drecs::World.new

  args.state.grid = Array.new(GRID_HEIGHT) { Array.new(GRID_WIDTH) }
  args.state.fall_timer = 0
  args.state.fall_speed = 0.5
  args.state.game_over = false
  args.state.score = 0
  args.state.lines_cleared = 0
  args.state.hook_blocks_spawned = 0
  args.state.hook_blocks_removed = 0

  world.on_added(:block) { |_w, _id, _c| args.state.hook_blocks_spawned += 1 }
  world.on_removed(:block) { |_w, _id, _c| args.state.hook_blocks_removed += 1 }

  spawn_piece(world, args)

  world
end

def spawn_piece(world, args)
  shape_key = SHAPES.keys.sample
  shape_data = SHAPES[shape_key]

  blocks = shape_data[:blocks].map do |bx, by|
    world.spawn({
      grid_pos: { x: 3 + bx, y: 18 + by },
      block: true,
      color: shape_data[:color],
      active: true
    })
  end

  args.state.current_piece = {
    blocks: blocks,
    center_x: 4,
    center_y: 19,
    shape: shape_key
  }
end

def handle_input(args)
  world = args.state.world

  if args.inputs.keyboard.key_down.left
    try_move(world, args, -1, 0)
  elsif args.inputs.keyboard.key_down.right
    try_move(world, args, 1, 0)
  elsif args.inputs.keyboard.key_down.down
    args.state.fall_speed = 0.05
  elsif args.inputs.keyboard.key_down.up
    try_rotate(world, args)
  elsif args.inputs.keyboard.key_down.space
    hard_drop(world, args)
  end

  if args.inputs.keyboard.key_up.down
    args.state.fall_speed = 0.5
  end
end

def handle_game_over_input(args)
  if args.inputs.keyboard.key_down.r
    args.state.world = setup(args)
  end
end

def try_move(world, args, dx, dy)
  piece = args.state.current_piece
  return false unless piece

  positions = []
  world.each_entity(:active, :grid_pos) do |entity_id, active, pos|
    positions << { x: pos[:x] + dx, y: pos[:y] + dy }
  end

  if valid_positions?(args, positions)
    world.each_entity(:active, :grid_pos) do |entity_id, active, pos|
      pos[:x] += dx
      pos[:y] += dy
    end
    piece[:center_x] += dx
    piece[:center_y] += dy
    true
  else
    false
  end
end

def try_rotate(world, args)
  piece = args.state.current_piece
  return unless piece
  return if piece[:shape] == :O

  cx = piece[:center_x]
  cy = piece[:center_y]

  new_positions = []
  world.each_entity(:active, :grid_pos) do |entity_id, active, pos|
    rx = pos[:x] - cx
    ry = pos[:y] - cy

    new_x = cx - ry
    new_y = cy + rx

    new_positions << { entity_id: entity_id, x: new_x, y: new_y }
  end

  if valid_positions?(args, new_positions.map { |p| { x: p[:x], y: p[:y] } })
    new_positions.each do |np|
      pos = world.get_component(np[:entity_id], :grid_pos)
      pos[:x] = np[:x]
      pos[:y] = np[:y]
    end
  end
end

def hard_drop(world, args)
  while try_move(world, args, 0, -1)
  end
  lock_piece(world, args)
end

def valid_positions?(args, positions)
  positions.all? do |pos|
    next false if pos[:x] < 0 || pos[:x] >= GRID_WIDTH
    next false if pos[:y] < 0

    next true if pos[:y] >= GRID_HEIGHT

    args.state.grid[pos[:y]][pos[:x]].nil?
  end
end

def update_game(args)
  args.state.fall_timer += 1.0 / 60

  if args.state.fall_timer >= args.state.fall_speed
    args.state.fall_timer = 0
    unless try_move(args.state.world, args, 0, -1)
      lock_piece(args.state.world, args)
    end
  end
end

def lock_piece(world, args)
  world.each_entity(:active, :grid_pos, :color) do |entity_id, active, pos, color|
    if pos[:y] >= GRID_HEIGHT
      args.state.game_over = true
      return
    end

    args.state.grid[pos[:y]][pos[:x]] = {
      entity_id: entity_id,
      color: color
    }
  end

  world.remove_components_from_query(world.query(:active), :active)

  args.state.current_piece = nil

  clear_lines(world, args)

  spawn_piece(world, args) unless args.state.game_over
end

def clear_lines(world, args)
  lines_to_clear = []

  GRID_HEIGHT.times do |y|
    if args.state.grid[y].all? { |cell| !cell.nil? }
      lines_to_clear << y
    end
  end

  return if lines_to_clear.empty?

  lines_to_clear.each do |y|
    args.state.grid[y].each do |cell|
      world.destroy(cell[:entity_id]) if cell
    end
    args.state.grid[y] = Array.new(GRID_WIDTH)
  end

  lines_to_clear.sort.reverse.each do |cleared_y|
    (cleared_y + 1).upto(GRID_HEIGHT - 1) do |y|
      args.state.grid[y].each_with_index do |cell, x|
        if cell
          pos = world.get_component(cell[:entity_id], :grid_pos)
          pos[:y] -= 1 if pos
        end
      end
    end

    args.state.grid.delete_at(cleared_y)
    args.state.grid << Array.new(GRID_WIDTH)
  end

  args.state.lines_cleared += lines_to_clear.length
  args.state.score += [100, 300, 500, 800][lines_to_clear.length - 1] || 0
end

def render(args)
  world = args.state.world

  args.outputs.solids << { x: 0, y: 0, w: 1280, h: 720, r: 20, g: 20, b: 30 }

  args.outputs.borders << {
    x: GRID_X - 2, y: GRID_Y - 2,
    w: GRID_WIDTH * CELL_SIZE + 4, h: GRID_HEIGHT * CELL_SIZE + 4,
    r: 100, g: 100, b: 100
  }

  args.outputs.solids << {
    x: GRID_X, y: GRID_Y,
    w: GRID_WIDTH * CELL_SIZE, h: GRID_HEIGHT * CELL_SIZE,
    r: 10, g: 10, b: 20
  }

  world.each_entity(:grid_pos, :color) do |entity_id, pos, color|
    args.outputs.solids << {
      x: GRID_X + pos[:x] * CELL_SIZE,
      y: GRID_Y + pos[:y] * CELL_SIZE,
      w: CELL_SIZE - 2,
      h: CELL_SIZE - 2,
      r: color[:r],
      g: color[:g],
      b: color[:b]
    }
  end

  args.outputs.labels << {
    x: 750, y: 650,
    text: "Score: #{args.state.score}",
    size_enum: 6,
    alignment_enum: 0,
    r: 255, g: 255, b: 255
  }

  args.outputs.labels << {
    x: 750, y: 600,
    text: "Lines: #{args.state.lines_cleared}",
    size_enum: 4,
    alignment_enum: 0,
    r: 200, g: 200, b: 200
  }

  args.outputs.labels << {
    x: 750, y: 560,
    text: "Hooks: Blocks +#{args.state.hook_blocks_spawned}/-#{args.state.hook_blocks_removed}",
    size_enum: 3,
    alignment_enum: 0,
    r: 180, g: 180, b: 180
  }

  args.outputs.labels << {
    x: 750, y: 520,
    text: "Controls:",
    size_enum: 3,
    alignment_enum: 0,
    r: 180, g: 180, b: 180
  }

  controls = [
    "← → Move",
    "↑ Rotate",
    "↓ Soft Drop",
    "Space Hard Drop"
  ]

  controls.each_with_index do |control, i|
    args.outputs.labels << {
      x: 750, y: 490 - i * 30,
      text: control,
      size_enum: 2,
      alignment_enum: 0,
      r: 150, g: 150, b: 150
    }
  end

  if args.state.game_over
    args.outputs.solids << {
      x: 0, y: 0,
      w: 1280, h: 720,
      r: 0, g: 0, b: 0, a: 180
    }

    args.outputs.labels << {
      x: 640, y: 400,
      text: "GAME OVER",
      size_enum: 10,
      alignment_enum: 1,
      r: 255, g: 0, b: 0
    }

    args.outputs.labels << {
      x: 640, y: 340,
      text: "Score: #{args.state.score}",
      size_enum: 6,
      alignment_enum: 1,
      r: 255, g: 255, b: 255
    }

    args.outputs.labels << {
      x: 640, y: 280,
      text: "Press R to restart",
      size_enum: 4,
      alignment_enum: 1,
      r: 200, g: 200, b: 200
    }
  end
end
