# Components for our shape physics sample
# These demonstrate the new class-based Component API

# Position component holds the x,y coordinates
class Position < Drecs::Component
  attr :x, :y
end

# Velocity component holds the dx,dy movement values per frame
class Velocity < Drecs::Component
  attr :dx, :dy
end

# Shape component holds the visual representation info
class Shape < Drecs::Component
  attr :type, :width, :height, :color
end

# Collider component identifies objects that can collide
class Collider < Drecs::Component
  attr :radius, :bouncy
end

# Player component marks an entity as controlled by the player
class Player < Drecs::Component
  attr :speed
end

# Lifetime component for temporary entities
class Lifetime < Drecs::Component
  attr :duration, :created_at
end
