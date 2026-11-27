--- @module "voice.context"
--- The text the shortcut gets from GET /context and hands to Apple's model
--- (Shortcuts "Use Model", Output: Dictionary) together with the dictated
--- request. It holds everything the model needs: the instructions, the allowed
--- actions and every name in the project. The shortcut itself knows nothing
--- about the project, so changes in Composer reach the phone with no edits.

local Context = {}

--- Actions, in the order the model sees them, with what they take.
Context.ACTIONS = {
  { "light_on", "target = light; no target turns on every light in the room" },
  { "light_off", "target = light; no target turns off every light in the room" },
  { "light_level", "target = light, value = brightness 0-100" },
  { "scene", "target = scene, activates it" },
  { "scene_off", "target = scene, deactivates it" },
  { "scenario", "target = scenario, runs it" },
  { "source", "target = source, plays or shows it in the room" },
  { "volume_set", "value = volume 0-100" },
  { "volume_up", "value = how much louder in percent, empty for a little" },
  { "volume_down", "value = how much quieter in percent, empty for a little" },
  { "mute", "" },
  { "unmute", "" },
  { "play", "" },
  { "pause", "" },
  { "next", "next track" },
  { "previous", "previous track" },
  { "room_off", "turns the room's audio and video off" },
  { "thermostat_set", "target = thermostat (or empty with the room), value = temperature in degrees" },
  { "thermostat_up", "warmer; value = how many degrees, empty for one" },
  { "thermostat_down", "cooler; value = how many degrees, empty for one" },
  { "thermostat_mode", "value = one of the thermostat's modes" },
  { "temperature", "a question about the temperature; target = thermostat or empty with the room" },
  { "unknown", "the request fits none of the above or names nothing in the lists" },
}

--- Set of valid action names.
Context.VALID = {}
for _, a in ipairs(Context.ACTIONS) do
  Context.VALID[a[1]] = true
end

local function list(lines, title, items, describe)
  lines[#lines + 1] = title .. ":"
  if #items == 0 then
    lines[#lines + 1] = "- (none)"
  end
  for _, item in ipairs(items) do
    lines[#lines + 1] = "- " .. describe(item)
  end
  lines[#lines + 1] = ""
end

local function inRoom(item)
  if item.room ~= nil and item.room ~= "" then
    return item.name .. " (room: " .. item.room .. ")"
  end
  return item.name
end

--- Build the context text.
--- @param data CatalogData
--- @param opts? { defaultRoom?: string, extra?: string }
--- @return string
function Context.build(data, opts)
  opts = opts or {}
  local lines = {
    "You turn one spoken smart home request into one command for a Control4 home.",
    "The request follows at the end, after 'Request:'.",
    "",
    "Answer with a dictionary with exactly these keys, all text:",
    "- room: the room the request is about, written exactly as in the Rooms list, or empty",
    "- action: one action from the Actions list",
    "- target: the light, scene, scenario or source, written exactly as in its list, or empty",
    "- value: a number when the action takes one, otherwise empty",
    "- heard: the request as you understood it, in a few words",
    "",
    "Rules:",
    "- Always pick names from the lists below, even when the request mispronounces, shortens or translates them.",
    "- A name that appears in several rooms needs the room; take it from the request.",
    "- Media actions (source, volume, mute, play, pause, next, previous, room_off) work on a room.",
    "- 'Set the bedroom to 22', 'make it warmer', 'cool mode', 'how warm is it' are thermostat actions.",
    "- Words like 'a bit', 'a little' mean no value. 'Half' means 50.",
    "- If nothing fits, use action unknown and explain in heard.",
  }
  if opts.defaultRoom ~= nil and opts.defaultRoom ~= "" then
    lines[#lines + 1] = "- When the request names no room, leave room empty; the home uses " .. opts.defaultRoom .. "."
  end
  if opts.extra ~= nil and opts.extra ~= "" then
    lines[#lines + 1] = "- " .. opts.extra
  end
  lines[#lines + 1] = ""

  list(lines, "Actions", Context.ACTIONS, function(a)
    return a[2] ~= "" and (a[1] .. ": " .. a[2]) or a[1]
  end)
  list(lines, "Rooms", data.rooms, function(r)
    return r.name
  end)
  list(lines, "Lights", data.lights, inRoom)
  list(lines, "Scenes", data.scenes, inRoom)
  list(lines, "Scenarios", data.scenarios, inRoom)
  list(lines, "Sources", data.sources, inRoom)
  list(lines, "Thermostats", data.thermostats or {}, function(t)
    return inRoom(t) .. "; modes: " .. table.concat(t.modes or {}, ", ")
  end)
  return table.concat(lines, "\n")
end

return Context
