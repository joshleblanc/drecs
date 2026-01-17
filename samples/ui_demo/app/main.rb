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

  root = nil
  panel = nil
  title = nil
  message = nil
  button = nil
  footer = nil

  UI.build(world) do |ui|
    root = ui.root(w: args.grid.w, h: args.grid.h, padding: 24, gap: 16) do
      panel = ui.panel(w: 520, h: 300, padding: 16, gap: 12, bg: PRIMARY_BG, border: PRIMARY_BORDER) do
        title = ui.text("Drecs UI Sample", size: 3, h: 28)
        message = ui.text("", size: 2, h: 22)
        button = ui.button("", w: 220, h: 36, bg: BUTTON_BG, border: PRIMARY_BORDER) do |id, w|
          state = w.resource(UiState)
          style = w.get_component(id, UI::UiStyle)
          state.active = !state.active
          state.clicks += 1
          state.message = state.active ? "Clicked!" : "Click me"
          style.bg = state.active ? BUTTON_ACTIVE_BG : BUTTON_BG
        end
        footer = ui.text("", size: 1, h: 20)
      end
    end
  end

  world.insert_resource(UiIds.new(root, panel, title, message, button, footer))

  args.state.entities = world
end


def tick(args)
  boot(args) unless args.state.entities
  args.state.entities.tick(args)
end
