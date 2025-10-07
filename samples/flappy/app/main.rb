GRAVITY = -0.5
FLAP_STRENGTH = 8
PIPE_SPEED = 3
PIPE_GAP = 150
PIPE_WIDTH = 60
PIPE_SPAWN_INTERVAL = 90

def tick(args)
  args.state.world ||= setup(args)

  if args.state.game_over
    handle_game_over(args)
  else
    handle_input(args)
    update_physics(args)
    update_pipes(args)
    check_collisions(args)
  end

  render(args)
end

def setup(args)
  world = Drecs::World.new

  world.spawn({
    position: { x: 200, y: 360 },
    velocity: { dy: 0 },
    bird: true,
    size: { w: 30, h: 30 },
    color: { r: 255, g: 255, b: 0 }
  })

  args.state.pipe_timer = 0
  args.state.score = 0
  args.state.game_over = false
  args.state.game_started = false

  world
end

def handle_input(args)
  world = args.state.world

  if args.inputs.keyboard.key_down.space || args.inputs.mouse.button_left
    args.state.game_started = true

    world.each_entity(:bird, :velocity) do |entity_id, bird, velocity|
      velocity[:dy] = FLAP_STRENGTH
    end
  end
end

def update_physics(args)
  return unless args.state.game_started

  world = args.state.world

  world.each_entity(:bird, :position, :velocity) do |entity_id, bird, pos, vel|
    vel[:dy] += GRAVITY
    pos[:y] += vel[:dy]

    if pos[:y] < 0
      pos[:y] = 0
      vel[:dy] = 0
      args.state.game_over = true
    end

    if pos[:y] > 720
      pos[:y] = 720
      vel[:dy] = 0
    end
  end
end

def update_pipes(args)
  return unless args.state.game_started

  world = args.state.world

  args.state.pipe_timer += 1

  if args.state.pipe_timer >= PIPE_SPAWN_INTERVAL
    args.state.pipe_timer = 0
    spawn_pipe_pair(world, args)
  end

  world.each_entity(:pipe, :position) do |entity_id, pipe, pos|
    pos[:x] -= PIPE_SPEED

    if pos[:x] < -PIPE_WIDTH
      world.destroy(entity_id)
    end
  end

  world.each_entity(:score_trigger, :position) do |entity_id, trigger, pos|
    pos[:x] -= PIPE_SPEED

    bird_pos = nil
    world.each_entity(:bird, :position) do |bird_id, bird, bird_p|
      bird_pos = bird_p
    end

    if bird_pos && pos[:x] + 10 < bird_pos[:x] && !trigger[:scored]
      trigger[:scored] = true
      args.state.score += 1
    end

    if pos[:x] < -10
      world.destroy(entity_id)
    end
  end
end

def spawn_pipe_pair(world, args)
  gap_center = 150 + rand(420)

  world.spawn({
    position: { x: 1280, y: 0 },
    size: { w: PIPE_WIDTH, h: gap_center - PIPE_GAP / 2 },
    pipe: true,
    color: { r: 0, g: 200, b: 0 }
  })

  world.spawn({
    position: { x: 1280, y: gap_center + PIPE_GAP / 2 },
    size: { w: PIPE_WIDTH, h: 720 - (gap_center + PIPE_GAP / 2) },
    pipe: true,
    color: { r: 0, g: 200, b: 0 }
  })

  world.spawn({
    position: { x: 1280, y: 0 },
    score_trigger: { scored: false }
  })
end

def check_collisions(args)
  return unless args.state.game_started

  world = args.state.world

  bird_rect = nil
  world.each_entity(:bird, :position, :size) do |entity_id, bird, pos, size|
    bird_rect = { x: pos[:x], y: pos[:y], w: size[:w], h: size[:h] }
  end

  return unless bird_rect

  world.each_entity(:pipe, :position, :size) do |entity_id, pipe, pos, size|
    pipe_rect = { x: pos[:x], y: pos[:y], w: size[:w], h: size[:h] }

    if rects_collide?(bird_rect, pipe_rect)
      args.state.game_over = true
    end
  end
end

def rects_collide?(r1, r2)
  r1[:x] < r2[:x] + r2[:w] &&
  r1[:x] + r1[:w] > r2[:x] &&
  r1[:y] < r2[:y] + r2[:h] &&
  r1[:y] + r1[:h] > r2[:y]
end

def handle_game_over(args)
  if args.inputs.keyboard.key_down.r
    args.state.world = setup(args)
  end
end

def render(args)
  world = args.state.world

  args.outputs.solids << { x: 0, y: 0, w: 1280, h: 720, r: 135, g: 206, b: 235 }

  world.each_entity(:pipe, :position, :size, :color) do |entity_id, pipe, pos, size, color|
    args.outputs.solids << {
      x: pos[:x],
      y: pos[:y],
      w: size[:w],
      h: size[:h],
      r: color[:r],
      g: color[:g],
      b: color[:b]
    }

    args.outputs.borders << {
      x: pos[:x],
      y: pos[:y],
      w: size[:w],
      h: size[:h],
      r: 0, g: 150, b: 0
    }
  end

  world.each_entity(:bird, :position, :size, :color) do |entity_id, bird, pos, size, color|
    args.outputs.solids << {
      x: pos[:x],
      y: pos[:y],
      w: size[:w],
      h: size[:h],
      r: color[:r],
      g: color[:g],
      b: color[:b]
    }
  end

  args.outputs.labels << {
    x: 640, y: 680,
    text: "Score: #{args.state.score}",
    size_enum: 8,
    alignment_enum: 1,
    r: 255, g: 255, b: 255
  }

  unless args.state.game_started
    args.outputs.labels << {
      x: 640, y: 400,
      text: "Press SPACE or Click to Start",
      size_enum: 6,
      alignment_enum: 1,
      r: 255, g: 255, b: 255
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
