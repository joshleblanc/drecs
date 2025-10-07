GRID_SIZE = 20
CELL_SIZE = 32
MOVE_INTERVAL = 0.15

def tick(args)
  args.state.world ||= setup(args)

  handle_input(args)
  update_movement(args)
  check_collisions(args)
  render(args)
end

def setup(args)
  world = Drecs::World.new

  head = world.spawn({
    position: { x: 10, y: 10 },
    velocity: { dx: 1, dy: 0 },
    snake_head: true,
    sprite: { r: 0, g: 255, b: 0 }
  })

  world.spawn({
    position: { x: 9, y: 10 },
    snake_body: { index: 1 },
    sprite: { r: 0, g: 200, b: 0 }
  })

  world.spawn({
    position: { x: 8, y: 10 },
    snake_body: { index: 2 },
    sprite: { r: 0, g: 200, b: 0 }
  })

  spawn_food(world)

  args.state.move_timer = 0
  args.state.game_over = false
  args.state.score = 0

  world
end

def spawn_food(world)
  world.spawn({
    position: { x: rand(GRID_SIZE), y: rand(GRID_SIZE) },
    food: true,
    sprite: { r: 255, g: 0, b: 0 }
  })
end

def handle_input(args)
  return if args.state.game_over

  world = args.state.world

  world.each_entity(:snake_head, :velocity) do |entity_id, head, velocity|
    if args.inputs.keyboard.key_down.up && velocity[:dy] == 0
      velocity[:dx] = 0
      velocity[:dy] = 1
    elsif args.inputs.keyboard.key_down.down && velocity[:dy] == 0
      velocity[:dx] = 0
      velocity[:dy] = -1
    elsif args.inputs.keyboard.key_down.left && velocity[:dx] == 0
      velocity[:dx] = -1
      velocity[:dy] = 0
    elsif args.inputs.keyboard.key_down.right && velocity[:dx] == 0
      velocity[:dx] = 1
      velocity[:dy] = 0
    end
  end

  if args.inputs.keyboard.key_down.r
    args.state.world = setup(args)
  end
end

def update_movement(args)
  return if args.state.game_over

  args.state.move_timer += args.state.tick_count > 0 ? 1.0 / 60 : 0

  return if args.state.move_timer < MOVE_INTERVAL

  args.state.move_timer = 0
  world = args.state.world

  head_pos = nil
  new_head_pos = nil

  world.each_entity(:snake_head, :position, :velocity) do |entity_id, head, pos, vel|
    head_pos = { x: pos[:x], y: pos[:y] }
    new_head_pos = { x: pos[:x] + vel[:dx], y: pos[:y] + vel[:dy] }

    pos[:x] = new_head_pos[:x]
    pos[:y] = new_head_pos[:y]
  end

  return unless head_pos

  body_segments = []
  world.each_entity(:snake_body, :position) do |entity_id, body, pos|
    body_segments << { entity_id: entity_id, index: body[:index], pos: pos }
  end

  body_segments = body_segments.sort_by { |s| s[:index] }

  prev_pos = head_pos
  body_segments.each do |segment|
    current_pos = { x: segment[:pos][:x], y: segment[:pos][:y] }
    segment[:pos][:x] = prev_pos[:x]
    segment[:pos][:y] = prev_pos[:y]
    prev_pos = current_pos
  end
end

def check_collisions(args)
  return if args.state.game_over

  world = args.state.world

  head_pos = nil
  world.each_entity(:snake_head, :position) do |entity_id, head, pos|
    head_pos = pos

    if pos[:x] < 0 || pos[:x] >= GRID_SIZE || pos[:y] < 0 || pos[:y] >= GRID_SIZE
      args.state.game_over = true
      return
    end
  end

  return unless head_pos

  world.each_entity(:snake_body, :position) do |entity_id, body, pos|
    if pos[:x] == head_pos[:x] && pos[:y] == head_pos[:y]
      args.state.game_over = true
      return
    end
  end

  food_entity = nil
  world.each_entity(:food, :position) do |entity_id, food, pos|
    if pos[:x] == head_pos[:x] && pos[:y] == head_pos[:y]
      food_entity = entity_id
      args.state.score += 1
    end
  end

  if food_entity
    world.destroy(food_entity)
    spawn_food(world)
    grow_snake(world)
  end
end

def grow_snake(world)
  max_index = 0
  last_segment = nil

  world.each_entity(:snake_body, :position) do |entity_id, body, pos|
    if body[:index] > max_index
      max_index = body[:index]
      last_segment = { pos: pos, index: body[:index] }
    end
  end

  if last_segment
    world.spawn({
      position: { x: last_segment[:pos][:x], y: last_segment[:pos][:y] },
      snake_body: { index: max_index + 1 },
      sprite: { r: 0, g: 200, b: 0 }
    })
  end
end

def render(args)
  world = args.state.world

  args.outputs.solids << { x: 0, y: 0, w: 1280, h: 720, r: 20, g: 20, b: 20 }

  world.each_entity(:position, :sprite) do |entity_id, pos, sprite|
    args.outputs.solids << {
      x: pos[:x] * CELL_SIZE + 320,
      y: pos[:y] * CELL_SIZE + 40,
      w: CELL_SIZE - 2,
      h: CELL_SIZE - 2,
      r: sprite[:r],
      g: sprite[:g],
      b: sprite[:b]
    }
  end

  args.outputs.labels << {
    x: 640,
    y: 700,
    text: "Score: #{args.state.score}",
    size_enum: 4,
    alignment_enum: 1,
    r: 255,
    g: 255,
    b: 255
  }

  if args.state.game_over
    args.outputs.labels << {
      x: 640,
      y: 400,
      text: "GAME OVER",
      size_enum: 10,
      alignment_enum: 1,
      r: 255,
      g: 0,
      b: 0
    }
    args.outputs.labels << {
      x: 640,
      y: 340,
      text: "Press R to restart",
      size_enum: 4,
      alignment_enum: 1,
      r: 255,
      g: 255,
      b: 255
    }
  end
end
