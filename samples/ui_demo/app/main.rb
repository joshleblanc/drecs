UiState = Struct.new(:clicks, :message, :active)
UiIds = Struct.new(:root, :panel, :title, :message, :button, :footer)

PRIMARY_BG = { r: 12, g: 12, b: 20, a: 220 }
PRIMARY_BORDER = { r: 50, g: 60, b: 80 }
BUTTON_BG = { r: 40, g: 120, b: 220, a: 230 }
BUTTON_ACTIVE_BG = { r: 120, g: 80, b: 220, a: 230 }

UI = Drecs::UI


def boot(args)
  world = Drecs::World.new
  world.clear_schedule!

  world.add_system(:ui_resize) do |w, a|
    ids = w.resource(UiIds)
    next unless ids
    layout = w.get_component(ids.root, UI::UiLayout)
    next unless layout
    layout.w = a.grid.w
    layout.h = a.grid.h
  end

  world.add_system(:ui_state, after: :ui_resize) do |w, _a|
    ids = w.resource(UiIds)
    state = w.resource(UiState)
    next unless ids && state

    if (message = w.get_component(ids.message, UI::UiText))
      message.text = "Clicks: #{state.clicks}"
    end

    if (button_text = w.get_component(ids.button, UI::UiText))
      button_text.text = state.message
    end

    if (footer = w.get_component(ids.footer, UI::UiText))
      footer.text = "Click the button to toggle its state. Press F1 for debug overlay."
    end
  end

  UI.install(world)

  world.insert_resource(UiState.new(0, "Click me", false))

  root = world.spawn(
    UI::UiNode.new("root"),
    UI::UiLayout.new(0, 0, args.grid.w, args.grid.h, :column, 24, 16, :start, :start)
  )

  panel = world.spawn(
    UI::UiNode.new("panel"),
    UI::UiLayout.new(0, 0, 520, 300, :column, 16, 12, :start, :start),
    UI::UiStyle.new(PRIMARY_BG, PRIMARY_BORDER, 1, nil)
  )
  world.set_parent(panel, root)

  title = world.spawn(
    UI::UiNode.new("title"),
    UI::UiLayout.new(0, 0, 0, 28, :row, 0, 0, :start, :start),
    UI::UiText.new("Drecs UI Sample", 3)
  )
  world.set_parent(title, panel)

  message = world.spawn(
    UI::UiNode.new("message"),
    UI::UiLayout.new(0, 0, 0, 22, :row, 0, 0, :start, :start),
    UI::UiText.new("", 2)
  )
  world.set_parent(message, panel)

  button = world.spawn(
    UI::UiNode.new("button"),
    UI::UiLayout.new(0, 0, 220, 36, :row, 0, 0, :start, :start),
    UI::UiStyle.new(BUTTON_BG, PRIMARY_BORDER, 1, nil),
    UI::UiText.new("", 2),
    UI::UiInput.new(false, false, lambda do |id, w|
      state = w.resource(UiState)
      style = w.get_component(id, UI::UiStyle)
      state.active = !state.active
      state.clicks += 1
      state.message = state.active ? "Clicked!" : "Click me"
      style.bg = state.active ? BUTTON_ACTIVE_BG : BUTTON_BG
    end)
  )
  world.set_parent(button, panel)

  footer = world.spawn(
    UI::UiNode.new("footer"),
    UI::UiLayout.new(0, 0, 0, 20, :row, 0, 0, :start, :start),
    UI::UiText.new("", 1)
  )
  world.set_parent(footer, panel)

  world.insert_resource(UiIds.new(root, panel, title, message, button, footer))

  args.state.entities = world
end


def tick(args)
  boot(args) unless args.state.entities
  args.state.entities.tick(args)
end
