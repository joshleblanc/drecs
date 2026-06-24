class Enemy < Struct.new(:type, :damage, :hp, :attack_cooldown, :detection_range)
  ENEMY_TYPES = [:goblin, :skeleton, :orc].freeze

  def initialize(type = :goblin, damage = 10, hp = 30, attack_cooldown = 0, detection_range = 200)
    super(type, damage, hp, attack_cooldown, detection_range)
  end

  def can_attack?
    attack_cooldown <= 0
  end

  def use_attack
    self.attack_cooldown = 30
  end

  def tick_cooldown
    self.attack_cooldown = [0, attack_cooldown - 1].max
  end

  def speed
    case type
    when :goblin   then 0.5  # 1 tile per 2 ticks
    when :skeleton then 0.67 # 1 tile per 1.5 ticks
    when :orc      then 0.4  # slow but bursty
    else                 0.5
    end
  end

  def self.goblin
    Enemy.new(:goblin, 10, 30, 0, 200)
  end

  def self.skeleton
    Enemy.new(:skeleton, 8, 20, 0, 300)
  end

  def self.orc
    Enemy.new(:orc, 25, 80, 0, 150)
  end
end