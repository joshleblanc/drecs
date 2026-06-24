class Player < Struct.new(:facing_direction, :attack_cooldown, :speed)
  DIRECTIONS = [:up, :down, :left, :right].freeze

  def initialize(facing_direction = :down, attack_cooldown = 0, speed = 4.0)
    super(facing_direction, attack_cooldown, speed)
  end

  def can_attack?
    attack_cooldown <= 0
  end

  def use_attack
    self.attack_cooldown = 15 # frames or ticks
  end

  def tick_cooldown
    self.attack_cooldown = [0, attack_cooldown - 1].max
  end

  def facing_vector
    case facing_direction
    when :up    then { dx: 0, dy: -1 }
    when :down  then { dx: 0, dy: 1 }
    when :left  then { dx: -1, dy: 0 }
    when :right then { dx: 1, dy: 0 }
    else            { dx: 0, dy: 0 }
    end
  end

  def turn_left
    idx = DIRECTIONS.index(facing_direction) || 0
    self.facing_direction = DIRECTIONS[(idx + 3) % 4]
  end

  def turn_right
    idx = DIRECTIONS.index(facing_direction) || 0
    self.facing_direction = DIRECTIONS[(idx + 1) % 4]
  end
end