BUILDING_HEIGHTS = [4, 4, 6, 8, 15, 18, 20]
BUILDING_ROOM_SIZES = [4, 5, 6, 7]
BUILDING_ROOM_WIDTH = 10
BUILDING_ROOM_SPACING = 15
BUILDING_ROOM_HEIGHT = 15
BUILDING_SPACING = 1

system :accelerate, :acceleration, :position do |entities|
  entities.each do |e|
    e.position.x += e.acceleration.x
    e.position.y += e.acceleration.y
  end
end

system :check_win, :killable, :exploded do |entities|
  next if entities.empty?

  winner = winner(entities)

  winner.score.score += 1
  state.systems.delete(:handle_input)
  state.systems.delete(:render_turn_input)
  state.systems.delete(:check_win)

  state.systems << :handle_input_game_over

  label_text = winner.id == state.player_one.id ? "Player 1 Wins!!" : "Player 2 Wins!!"
  game_over_screen = create_entity(:game_over_screen, solids: { solids: [grid.rect, 0, 0, 0, 200] })
  game_over_screen.labels.labels << [640, 340, label_text, 5, 1, FANCY_WHITE.values]
end

system :check_win, :destroyed do |entities|
  entities.each(&method(:delete_entity))
end

system :generate_stage do
  buildings = []
  buildings << generate_building(BUILDING_ROOM_SPACING - 20, *random_building_size)

  8.numbers.inject(buildings) do |b, i|
    b << generate_building(BUILDING_SPACING + b.last.position.x + b.last.size.width, *random_building_size)
  end

  generate_player(state.player_one, buildings[1], :left)
  generate_player(state.player_two, buildings[-3], :right)

  wind_speed = 1.randomize(:ratio, :sign)
  state.wind.speed.speed = 1.randomize(:ratio, :sign)

  state.current_turn.turn.first_player ||= state.player_one
  state.current_turn.turn.player = state.current_turn.turn.first_player

  state.systems.delete(:generate_stage)
end

system :handle_explosion, :explodes, :position, :size do |entities|
  collidables = state.entities.select { |e| has_components?(e, :collides, :position, :size) }

  next unless collidables.any?

  holes = state.entities.select { |e| has_components?(e, :empty, :position, :size) }

  entities.each do |entity|
    rect = make_rect(entity)

    collision = collidables.find { |collidable| make_rect(collidable).intersect_rect?(rect) }

    next unless collision

    in_hole = holes.map { |h| make_rect(h).scale_rect(0.8, 0.5, 0.5) }.any? { |h| h.intersect_rect?(make_rect(collision)) }

    next if in_hole

    create_entity(:hole, position: { x: collision.position.x - 20, y: collision.position.y - 20 })
    add_component(collision, :destroyed)
    add_component(entity, :exploded)
  end
end

system :handle_input do
  turn = state.current_turn.turn

  next if turn_finished?(turn)

  current_input = current_input(turn)

  if inputs.keyboard.key_down.enter
    submit_input(turn)
  elsif inputs.keyboard.key_down.backspace
    update_input(turn, current_input[0..-2])
  elsif inputs.keyboard.key_down.char
    char = inputs.keyboard.key_down.char
    update_input(turn, current_input + char) if (0..9).map(&:to_s).include?(char)
  end
end

system :handle_input_game_over, :ephemeral do |entities|
  next unless inputs.keyboard.key_down.truthy_keys.any?

  entities.each(&method(:delete_entity))

  state.entities.each do |e|
    remove_component(e, :exploded)
  end

  outputs.static_colids.clear
  state.systems.delete :handle_input_game_over

  state.current_turn.turn.angle = ""
  state.current_turn.turn.velocity = ""
  state.current_turn.turn.angle_committed = false
  state.current_turn.turn.velocity_committed = false
  state.current_turn.turn.first_player = next_player(state.current_turn.turn.first_player)

  state.systems << :generate_stage
  state.systems << :handle_input
  state.systems << :render_turn_input
  state.systems << :check_win
end

system :handle_miss, :collides, :position do |entities|
  entities.each do |entity|
    delete_entity(entity) if entity.position.y < 0
  end
end

system :handle_next_turn, :collides do |entities|
  turn = state.current_turn.turn

  next unless turn.angle_committed && turn.velocity_committed
  next if entities.any?

  turn.player = next_player(turn.player)
  turn.angle = ""
  turn.angle_committed = false
  turn.velocity = ""
  turn.velocity_committed = false
end

system :handle_rotation, :acceleration, :rotation, :sprite do |entities|
  entities.each do |entity|
    rotation = (state.tick_count % 360) * entity.rotation.velocity
    rotation *= -1 if entity.acceleration.x > 0
    entity.sprite.angle = rotation
  end
end

system :render_animations, :animated, :position, :size do |entities|
  entities.each do |entity|
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

        remove_component(entity, :animated) unless entity.animated.idle_sprite
      end
    end

    outputs.sprites << {
      x: entity.position.x,
      y: entity.position.y,
      w: entity.size.width,
      h: entity.size.height,
      path: sprite,
    }
  end
end

system :render_background, :background_color do |entities|
  entities.each do |entity|
    outputs.background_color = entity.background_color.color
  end
end

system :render_labels, :labels do |entities|
  labels = entities.flat_map { |entity| entity.labels.labels.map(&:label) }

  outputs.primitives << labels
end

system :render_lines, :lines, :rendered do |entities|
  entities.each do |entity|
    outputs.lines << entity.lines.lines
  end
end

system :render_scores do
  outputs.labels << [10, 25, "Score: #{state.player_one.score.score}", 0, 0, FANCY_WHITE.values]
  outputs.labels << [1270, 25, "Score: #{state.player_two.score.score}", 0, 2, FANCY_WHITE.values]
end

system :render_solids, :solids, :rendered do |entities|
  entities.each do |entity|
    outputs.primitives << entity.solids.solids.map(&:solid)
  end
end

system :render_sprites, :position, :rendered, :size, :sprite do |entities|
  sprites = entities.map do |entity|
    {
      x: entity.position.x,
      y: entity.position.y,
      w: entity.size.width,
      h: entity.size.height,
      angle: entity.sprite.angle,
      path: entity.sprite.path,
    }
  end

  outputs.sprites << sprites
end

system :render_static_solids, :solids, :static_rendered do |entities|
  entities.each do |entity|
    remove_component(entity, :static_rendered)
    outputs.static_solids << entity.solids.solids
  end
end

system :render_turn_input do
  turn = state.current_turn.turn
  next unless turn.player
  next if turn.angle_comitted && turn.velocity.committed

  x = turn.player.id == state.player_one.id ? 10 : 1120

  labels = [{ x: x, y: 710, text: "Angle:    #{turn.angle}_" }.merge(FANCY_WHITE)]

  if turn.angle_committed
    labels << { x: x, y: 690, text: "Velocity: #{turn.velocity}_" }.merge(FANCY_WHITE)
  end

  outputs.labels << labels
end

system :update_acceleration, :acceleration do |entities|
  entities.each do |entity|
    entity.acceleration.x += state.wind.speed.speed.fdiv(50)
    entity.acceleration.y -= state.gravity.speed.speed
  end
end

system :update_wind do
  wind = state.wind
  wind_speed = wind.speed.speed

  wind.solids.solids = [[640, 12, wind_speed * 500 + wind_speed * 10 * rand, 4, 35, 136, 162]]
end

def next_player(player)
  remaining = [state.player_one, state.player_two] - [player]
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
    create_entity(:banana, owned: { owner: turn.player }, position: { x: turn.player.position.x + 25, y: turn.player.position.y + 60 }, angled: { angle: angle }, acceleration: { x: angle.vector_x(velocity), y: angle.vector_y(velocity) })
  end
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

def turn_finished?(turn)
  turn.angle_committed && turn.velocity_committed
end

def make_rect(entity)
  [entity.position.x, entity.position.y, entity.size.width, entity.size.height]
end

def winner(entities)
  remaining = [state.player_one, state.player_two] - entities.to_a
  remaining.first
end

def generate_building(x, floors, rooms)
  width = BUILDING_ROOM_WIDTH * rooms + BUILDING_ROOM_SPACING * (rooms + 1)
  height = BUILDING_ROOM_HEIGHT * floors + BUILDING_ROOM_SPACING * (floors + 1)

  create_entity(:building, position: { x: x, y: 0 }, size: { width: width, height: height }, solids: { solids: [[x - 1, 0, width + 2, height + 1, FANCY_WHITE.values], [x, 0, width, height, random_building_color], windows_for_building(x, floors, rooms)] })
end

def generate_player(player, building, id)
  x = building.position.x + building.size.width.fdiv(2)
  y = building.size.height

  player.position.x = x
  player.position.y = y
end

def windows_for_building(x, floors, rooms)
  (floors - 1).combinations(rooms - 1).map do |floor, room|
    [
      (x + BUILDING_ROOM_WIDTH * room) + (BUILDING_ROOM_SPACING * (room + 1)),
      (BUILDING_ROOM_HEIGHT * floor) + (BUILDING_ROOM_SPACING * (floor + 1)),
      BUILDING_ROOM_WIDTH,
      BUILDING_ROOM_HEIGHT,
      random_window_color,
    ]
  end
end

def random_building_color
  [
    [99, 0, 107],
    [35, 64, 124],
    [35, 136, 162],
  ].sample
end

def random_building_size
  [BUILDING_HEIGHTS.sample, BUILDING_ROOM_SIZES.sample]
end

def random_window_color
  [
    [88, 62, 104],
    [253, 224, 187],
  ].sample
end
