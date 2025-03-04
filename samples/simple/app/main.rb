NAMES = [
  "Kojiro", "Genzo", "Taro", "Hikaru", "Jun",
  "Shingo", "Ryo", "Takeshi", "Masao", "Kazuo",
]

def random_position(radius:, on_circle: false)
  res = { 
    x: rand * radius,
    y: rand * radius
  }

  if on_circle
    return Geometry.vec2_normalize(res)
  end

  res
end

def boot 
  ecs = Drecs.world 
  args.state.ecs = ecs
  NAMES.each do |name| 
    ecs.entity do 
      component :player
      component :name, name
      component :talent, false
      component :position, **random_position(radius: 25)
    end
  end

  ecs.entity do 
    component :player 
    component :name, "Tsubasa"
    component :talent, true
    component :position, x: 0, y: 50
  end

  ecs.entity do 
    component :ball
    component :position, x: 0, y: 0
  end

  ecs.system do 
    query { with(:name, :position, :talent) }
  end
end

def tick
  ecs.query do 
    with :name, :position, :talent, :player
    reject :whatever 
  end
end