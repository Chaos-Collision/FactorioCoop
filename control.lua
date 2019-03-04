local coop = require("coop")

coop.add_remote_interface()

local register_events = function()
  for event_name, handler in pairs (coop.get_events()) do
    script.on_event(event_name, handler)
  end
  for n, handler in pairs (coop.on_nth_tick) do
    script.on_nth_tick(n, handler)
  end
end

script.on_init(function()
  coop.on_init()
  register_events()
end)

script.on_load(function()
  coop.on_load()
  register_events()
end)

script.on_configuration_changed(function()
  coop.on_configuration_changed()
end)
