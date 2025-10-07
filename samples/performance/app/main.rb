Position = Struct.new(:x, :y)
Velocity = Struct.new(:dx, :dy)
Health = Struct.new(:current, :max)
Damage = Struct.new(:value)
Tag = Struct.new(:name)

SCENARIOS = [
  { name: "1K Entities - Simple Query", count: 1000 },
  { name: "5K Entities - Simple Query", count: 5000 },
  { name: "10K Entities - Simple Query", count: 10000 },
  { name: "20K Entities - Simple Query", count: 20000 },
  { name: "1K Entities - Complex Query", count: 1000, complex: true },
  { name: "5K Entities - Complex Query", count: 5000, complex: true },
  { name: "10K Entities - Archetype Migration", count: 10000, migration: true },
  { name: "1K Entities - Batch Destroy", count: 1000, destroy: true }
]

def tick(args)
  args.state.scenario_index ||= 0
  args.state.warmup_frames ||= 0
  args.state.benchmark_frames ||= 0
  args.state.frame_times ||= []
  args.state.running ||= false
  args.state.results ||= []

  handle_input(args)

  if args.state.running
    run_benchmark(args)
  else
    render_menu(args)
  end
end

def handle_input(args)
  if !args.state.running
    if args.inputs.keyboard.key_down.space
      args.state.running = true
      args.state.warmup_frames = 0
      args.state.benchmark_frames = 0
      args.state.frame_times = []
      setup_scenario(args, SCENARIOS[args.state.scenario_index])
    elsif args.inputs.keyboard.key_down.up
      args.state.scenario_index = (args.state.scenario_index - 1) % SCENARIOS.length
    elsif args.inputs.keyboard.key_down.down
      args.state.scenario_index = (args.state.scenario_index + 1) % SCENARIOS.length
    elsif args.inputs.keyboard.key_down.r
      args.state.results = []
    end
  end
end

def setup_scenario(args, scenario)
  args.state.world = Drecs::World.new
  world = args.state.world

  scenario[:count].times do |i|
    components = [
      Position.new(rand(1280), rand(720)),
      Velocity.new(Numeric.rand(-5.0..5.0), Numeric.rand(-5.0..5.0))
    ]

    if scenario[:complex]
      components << Health.new(100, 100)
      components << Damage.new(Numeric.rand(1..10))
      components << Tag.new("entity_#{i}")
    end

    world.spawn(*components)
  end

  args.state.scenario = scenario
end

def run_benchmark(args)
  scenario = args.state.scenario
  world = args.state.world

  if args.state.warmup_frames < 60
    args.state.warmup_frames += 1
    perform_scenario_work(args, scenario, world)
    render_benchmark_progress(args, "Warming up...", args.state.warmup_frames / 60.0)
    return
  end

  if args.state.benchmark_frames < 300
    start_time = Time.now

    perform_scenario_work(args, scenario, world)

    end_time = Time.now
    frame_time = (end_time - start_time) * 1000
    args.state.frame_times << frame_time
    args.state.benchmark_frames += 1

    render_benchmark_progress(args, "Benchmarking...", args.state.benchmark_frames / 300.0)
  else
    finish_benchmark(args)
  end
end

def perform_scenario_work(args, scenario, world)
  if scenario[:migration]
    entities_to_modify = []
    world.each_entity(Position) do |entity_id, pos|
      entities_to_modify << entity_id if rand < 0.01
    end

    entities_to_modify.each do |entity_id|
      if world.has_component?(entity_id, Health)
        world.remove_component(entity_id, Health)
      else
        world.add_component(entity_id, Health.new(100, 100))
      end
    end
  elsif scenario[:destroy]
    if args.state.benchmark_frames == 0
      entities_to_destroy = []
      world.each_entity(Position) do |entity_id, pos|
        entities_to_destroy << entity_id if rand < 0.5
      end
      world.destroy(*entities_to_destroy)
    end
  end

  world.query(Position, Velocity) do |entity_ids, positions, velocities|
    positions.each_with_index do |pos, i|
      vel = velocities[i]
      pos.x += vel.dx
      pos.y += vel.dy

      pos.x = 0 if pos.x > 1280
      pos.x = 1280 if pos.x < 0
      pos.y = 0 if pos.y > 720
      pos.y = 720 if pos.y < 0
    end
  end

  if scenario[:complex]
    world.query(Health, Damage) do |entity_ids, healths, damages|
      healths.each_with_index do |health, i|
        damage = damages[i]
        health.current = [health.current - damage.value * 0.01, 0].max
        health.current = health.max if health.current == 0
      end
    end
  end
end

def finish_benchmark(args)
  frame_times = args.state.frame_times
  avg_time = frame_times.sum / frame_times.length
  min_time = frame_times.min
  max_time = frame_times.max
  p50 = frame_times.sort[frame_times.length / 2]
  p95 = frame_times.sort[(frame_times.length * 0.95).to_i]
  p99 = frame_times.sort[(frame_times.length * 0.99).to_i]

  world = args.state.world
  entity_count = world.entity_count
  archetype_count = world.archetype_count

  args.state.results << {
    name: args.state.scenario[:name],
    avg_time: avg_time,
    min_time: min_time,
    max_time: max_time,
    p50: p50,
    p95: p95,
    p99: p99,
    entity_count: entity_count,
    archetype_count: archetype_count,
    avg_fps: 1000.0 / avg_time
  }

  args.state.scenario_index = (args.state.scenario_index + 1) % SCENARIOS.length
  args.state.running = false
end

def render_menu(args)
  args.outputs.solids << { x: 0, y: 0, w: 1280, h: 720, r: 20, g: 20, b: 30 }

  args.outputs.labels << {
    x: 640, y: 680,
    text: "Drecs Performance Benchmarks",
    size_enum: 8,
    alignment_enum: 1,
    r: 100, g: 200, b: 255
  }

  y = 580
  args.outputs.labels << {
    x: 640, y: y,
    text: "Select Scenario (↑/↓) | SPACE to Run | R to Reset",
    size_enum: 2,
    alignment_enum: 1,
    r: 180, g: 180, b: 180
  }

  y = 520
  SCENARIOS.each_with_index do |scenario, i|
    color = i == args.state.scenario_index ? { r: 255, g: 255, b: 100 } : { r: 200, g: 200, b: 200 }
    prefix = i == args.state.scenario_index ? "▶ " : "  "

    args.outputs.labels << {
      x: 400, y: y,
      text: "#{prefix}#{scenario[:name]}",
      size_enum: 3,
      alignment_enum: 0,
      **color
    }

    result = args.state.results.find { |r| r[:name] == scenario[:name] }
    if result
      args.outputs.labels << {
        x: 880, y: y,
        text: sprintf("%.2f ms (%.0f FPS) | P95: %.2f ms", result[:avg_time], result[:avg_fps], result[:p95]),
        size_enum: 2,
        alignment_enum: 1,
        r: 100, g: 255, b: 100
      }
    end

    y -= 50
  end

  if args.state.results.length > 0
    y = 80
    args.outputs.labels << {
      x: 640, y: y,
      text: "Legend: avg ms (avg FPS) | P95: 95th percentile ms",
      size_enum: 1,
      alignment_enum: 1,
      r: 150, g: 150, b: 150
    }
  end
end

def render_benchmark_progress(args, status, progress)
  args.outputs.solids << { x: 0, y: 0, w: 1280, h: 720, r: 20, g: 20, b: 30 }

  args.outputs.labels << {
    x: 640, y: 400,
    text: status,
    size_enum: 8,
    alignment_enum: 1,
    r: 100, g: 200, b: 255
  }

  args.outputs.labels << {
    x: 640, y: 340,
    text: args.state.scenario[:name],
    size_enum: 4,
    alignment_enum: 1,
    r: 200, g: 200, b: 200
  }

  bar_width = 600
  bar_height = 40
  bar_x = 640 - bar_width / 2
  bar_y = 280

  args.outputs.borders << {
    x: bar_x, y: bar_y,
    w: bar_width, h: bar_height,
    r: 100, g: 100, b: 100
  }

  args.outputs.solids << {
    x: bar_x + 2, y: bar_y + 2,
    w: (bar_width - 4) * progress, h: bar_height - 4,
    r: 100, g: 200, b: 255
  }

  args.outputs.labels << {
    x: 640, y: 300,
    text: sprintf("%.0f%%", progress * 100),
    size_enum: 4,
    alignment_enum: 1,
    r: 255, g: 255, b: 255
  }

  world = args.state.world
  args.outputs.labels << {
    x: 640, y: 220,
    text: "Entities: #{world.entity_count} | Archetypes: #{world.archetype_count}",
    size_enum: 2,
    alignment_enum: 1,
    r: 180, g: 180, b: 180
  }

  if args.state.frame_times.length > 0
    recent_times = args.state.frame_times.last(60)
    avg_recent = recent_times.sum / recent_times.length
    args.outputs.labels << {
      x: 640, y: 180,
      text: sprintf("Current: %.2f ms (%.0f FPS)", avg_recent, 1000.0 / avg_recent),
      size_enum: 2,
      alignment_enum: 1,
      r: 150, g: 255, b: 150
    }
  end
end
