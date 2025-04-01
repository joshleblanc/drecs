FANCY_WHITE = {r: 253, g: 252, b: 253}
BUILDING_HEIGHTS = [4, 4, 6, 8, 15, 18, 20]
BUILDING_ROOM_SIZES = [4, 5, 6, 7]
BUILDING_ROOM_WIDTH = 10
BUILDING_ROOM_SPACING = 15
BUILDING_ROOM_HEIGHT = 15
BUILDING_SPACING = 1

def windows_for_building(x, floors, rooms)
  (floors - 1).combinations(rooms - 1).map do |floor, room|
    [
      (x + BUILDING_ROOM_WIDTH * room) + (BUILDING_ROOM_SPACING * (room + 1)),
      (BUILDING_ROOM_HEIGHT * floor) + (BUILDING_ROOM_SPACING * (floor + 1)),
      BUILDING_ROOM_WIDTH,
      BUILDING_ROOM_HEIGHT,
      random_window_color
    ]
  end
end

def random_building_color
  [
    [99, 0, 107],
    [35, 64, 124],
    [35, 136, 162]
  ].sample
end

def generate_building(x, floors, rooms)
  width = BUILDING_ROOM_WIDTH * rooms + BUILDING_ROOM_SPACING * (rooms + 1)
  height = BUILDING_ROOM_HEIGHT * floors + BUILDING_ROOM_SPACING * (floors + 1)

  
  $args.state.entities << {
    position: {x: x, y: 0},
    size: {width: width, height: height},
    solids: [
      [x - 1, 0, width + 2, height + 1, FANCY_WHITE.values],
      [x, 0, width, height, random_building_color],
      *windows_for_building(x, floors, rooms)
    ]
  }
end

def random_building_size
  [BUILDING_HEIGHTS.sample, BUILDING_ROOM_SIZES.sample]
end

def generate_player(player, building, id)
  x = building.position.x + building.size.width.fdiv(2)
  y = building.size.height

  player.position.x = x
  player.position.y = y
end

def random_window_color
  [
    [88, 62, 104],
    [253, 224, 187]
  ].sample
end

def make_rect(entity)
  [entity.position.x, entity.position.y, entity.size.width, entity.size.height]
end

def turn_finished?(turn)
  turn.angle_committed && turn.velocity_committed
end

def current_input(turn)
  if !turn.angle_committed
    turn.angle
  else
    turn.velocity
  end
end

def update_input(turn, value)
  if !turn.angle_committed
    turn.angle = value
  else
    turn.velocity = value
  end
end

def winner(entities)
  remaining = [$args.state.entities.player_one, $args.state.entities.player_two] - entities.to_a
  remaining.first
end

def submit_input(turn)
  if !turn.angle_committed
    turn.angle_committed = true
  else
    turn.velocity_committed = true
  end

  if turn.velocity_committed && turn.angle_committed
    angle = turn.angle.to_i
    angle = 180 - angle if state.player_two.id == turn.player.id
    velocity = turn.velocity.to_i / 5

    turn.player.animated.enabled = true

    $args.state.entities << {
      
    }
    create_entity(:banana, owned: {owner: turn.player}, position: {x: turn.player.position.x + 25, y: turn.player.position.y + 60}, angled: {angle: angle}, acceleration: {x: angle.vector_x(velocity), y: angle.vector_y(velocity)})
  end
end

def boot(args)
  args.state.entities = Drecs::World.new
  args.state.entities << { 
    background_color: {
      color: [33, 32, 87]
    }
  }

  # scoreboard
  args.state.entities << { 
    debug: true, 
    rendered: true, 
    solid: true, 
    position: {x: 0, y: 0}, 
    size: { width: 1200, height: 31 }, 
    solids: [[0, 0, 1280, 31, FANCY_WHITE.values], [1, 1, 1279, 29]]
  }

  args.state.entities << {
    turn: {angle: "", angle_committed: false, first_player: nil, player: nil, velocity: "", velocity_committed: false},
    as: :current_turn
  }

  # wind
  args.state.entities << {
    rendered: true,
    solids: [],
    speed: { amt: 1 },
    lines: [640, 30, 640, 0, FANCY_WHITE.values],
    as: :wind
  }

  # gravity 
  args.state.entities << {
    speed: 0.25,
    as: :gravity
  }

  # player 1
  args.state.entities << { 
    animated: {idle_sprite: "samples/gorillas-basic/sprites/left-idle.png", frames: [[5, "samples/gorillas-basic/sprites/left-0.png"], [5, "samples/gorillas-basic/sprites/left-1.png"], [5, "samples/gorillas-basic/sprites/left-2.png"]]},
    explodes: true,
    killable: true,
    position: {x: 0, y: 0},
    score: 0,
    solid: true,
    size: {width: 50, height: 50},
    as: :player_one
  }

  # player 2
  args.state.entities << { 
    animated: {idle_sprite: "samples/gorillas-basic/sprites/right-idle.png", frames: [[5, "samples/gorillas-basic/sprites/right-0.png"], [5, "samples/gorillas-basic/sprites/right-1.png"], [5, "samples/gorillas-basic/sprites/right-2.png"]]},
    explodes: true,
    killable: true,
    position: {x: 0, y: 0},
    score: 0,
    solid: true,
    size: {width: 50, height: 50},
    as: :player_two
  }

  args.state.entities << {angle: "", angle_committed: false, first_player: nil, player: nil, velocity: "", velocity_committed: false}

  buildings = []
  buildings << generate_building(BUILDING_ROOM_SPACING - 20, *random_building_size)

  8.numbers.inject(buildings) do |b, i|
    b << generate_building(BUILDING_SPACING + b.last.position.x + b.last.size.width, *random_building_size)
  end

  generate_player(args.state.entities.player_one, buildings[1], :left)
  generate_player(args.state.entities.player_two, buildings[-3], :right)

  args.state.entities.wind.speed.amt = 1.randomize(:ratio, :sign)

  args.state.entities.current_turn.turn.first_player ||= args.state.entities.player_one
  args.state.current_turn.turn.player = args.state.entities.current_turn.turn.first_player
end

def tick(args)
  args.state.entities.with(:background_color).each do |entity|
    args.outputs.background_color = entity.background_color.color
  end

  args.outputs.labels << [10, 25, "Score: #{args.state.entities.player_one.score}", 0, 0, FANCY_WHITE.values]
  args.outputs.labels << [1270, 25, "Score: #{args.state.entities.player_two.score}", 0, 2, FANCY_WHITE.values]

  args.state.entities.with(:solids, :static_rendered).each do |entity|
    args.outputs.static_solids << entity.solids
    entity.remove :static_rendered
  end

  wind = args.state.entities.wind
  wind_speed = wind.speed.amt
  wind.solids = [[640, 12, wind_speed * 500 + wind_speed * 10 * rand, 4, 35, 136, 162]]

  args.state.entities.with(:acceleration, :rotation, :sprite).each do |entity|
    rotation = (state.tick_count % 360) * entity.rotation.velocity
    rotation *= -1 if entity.acceleration.x > 0
    entity.sprite.angle = rotation
  end

  args.state.entities.with(:lines, :rendered).each do |entity|
    args.state.outputs.lines << entity.lines
  end

  args.state.entities.with(:solids, :rendered).each do |entity|
    args.outputs.primitives << entity.solids.solid
  end

  args.state.entities.with(:labels).each do |entity|
    args.outputs.labels << entity.labels.label
  end

  args.state.entities.with(:acceleration, :position).each do |entity|
    entity.position.x += entity.acceleration.x
    entity.position.y += entity.acceleration.y
  end

  args.state.entities.with(:acceleration).each do |entity|
    entity.acceleration.x += args.state.entities.wind.speed.fdiv(50)
    entity.acceleration.y -= args.state.entities.gravity.speed
  end

  collidables = args.state.entities.with(:collides, :position, :size)
  holes = args.state.entities.with(:empty, :position, :size)

  args.state.entities.with(:explodes, :position, :size).each do |entity|
    rect = make_rect(entity)
    collision = collidables.find { |collidable| make_rect(collidable).intersect_rect?(rect)} 

    next unless collision 

    in_hole = holes.map { |h| make_rect(h).scale_rect(0.8, 0.5, 0.5) }.any? { |h| h.intersect_rect?(make_rect(collision)) }

    next if in_hole

    args.state.entities << {
      empty: true,
      ephemeral: true,
      rendered: true,
      position: {x: collision.position.x - 20, y: collision.position.y - 20},
      size: {width: 40, height: 40},
      sprite: {path: "samples/gorillas-basic/sprites/hole.png"}, 
      animated: {
        enabled: true, 
        frames: [[3, "samples/gorillas-basic/sprites/explosion0.png"], [3, "samples/gorillas-basic/sprites/explosion1.png"], [3, "samples/gorillas-basic/sprites/explosion2.png"], [3, "samples/gorillas-basic/sprites/explosion3.png"], [3, "samples/gorillas-basic/sprites/explosion4.png"], [3, "samples/gorillas-basic/sprites/explosion5.png"], [3, "samples/gorillas-basic/sprites/explosion6.png"]]
      }
    }

    collision.add :destroyed
    entity.add :exploded
  end

  args.state.entities.with(:collides, :position).each do |entity|
    args.state.entities.delete(entity) if entity.position.y < 0
  end

  args.state.entities.with(:destroyed).each do |entity|
    args.state.entities.delete(entity)
  end

  args.state.entities.with(:position, :rendered, :size, :sprite).raw do |entities|
    args.outputs.sprites << entities.map do |entity|
      {
        x: entity.position.x,
        y: entity.position.y,
        w: entity.size.width,
        h: entity.size.height,
        angle: entity.sprite.angle,
        path: entity.sprite.path
      }
    end
  end

  args.state.entities.with(:animated, :position, :size).each do |entity|
    sprite = entity.animated.idle_sprite

    if entity.animated.enabled
      frame = entity.animated.frames[entity.animated.index]
      sprite = frame.last

      entity.animated.frame_tick_count += 1
      if entity.animated.frame_tick_count >= frame.first
        entity.animated.frame_tick_count = 0
        entity.animated.index += 1
      end

      if entity.animated.index >= entity.animated.frames.count
        entity.animated.enabled = false
        entity.animated.index = 0

        entity.remove :animated unless entity.animated.idle_sprite
      end
    end

    args.outputs.sprites << {
      x: entity.position.x,
      y: entity.position.y,
      w: entity.size.width,
      h: entity.size.height,
      path: sprite
    }
  end

  turn = args.state.entities.current_turn.turn

  next if turn_finished?(turn)

  current_input = current_input(turn)

  if args.inputs.keyboard.key_down.enter
    submit_input(turn)
  elsif args.inputs.keyboard.key_down.backspace
    update_input(turn, current_input[0..-2])
  elsif args.inputs.keyboard.key_down.char
    char = args.inputs.keyboard.key_down.char
    update_input(turn, current_input + char) if (0..9).map(&:to_s).include?(char)
  end

  turn = args.state.current_turn.turn
  next unless turn.player
  next if turn.angle_comitted && turn.velocity.committed

  x = (turn.player.id == args.state.entities.player_one.id) ? 10 : 1120

  labels = [{x: x, y: 710, text: "Angle:    #{turn.angle}_"}.merge(FANCY_WHITE)]

  if turn.angle_committed
    labels << {x: x, y: 690, text: "Velocity: #{turn.velocity}_"}.merge(FANCY_WHITE)
  end

  args.outputs.labels << labels

  args.state.entities.with(:killable, :exploded).each do |entity|
    winner = winner(entities)

    winner.score += 1

    # remove_system(:handle_input)
    # remove_system(:render_turn_input)
    # remove_system(:check_win)

    #state.systems << :handle_input_game_over

    label_text = (winner._id == args.state.entities.player_one._id) ? "Player 1 Wins!!" : "Player 2 Wins!!"

    args.state.entities << {
      ephemeral: true,
      rendered: true,
      solids: [[grid.rect, 0, 0, 0, 200]],
      labels: [[640, 370, "Game Over!!", 5, 1, FANCY_WHITE.values]]
    }
  end

  args.state.entities.with(:collides).raw do |entities|
    turn = args.state.entities.current_turn.turn

    next unless turn.angle_committed && turn.velocity_committed
    next if entities.any?
  
    turn.player = next_player(turn.player)
    turn.angle = ""
    turn.angle_committed = false
    turn.velocity = ""
    turn.velocity_committed = false
  end
end
