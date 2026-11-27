--- @module "voice.commands"
--- Carries out the command the shortcut posts to /execute: the dictionary
--- Apple's model made from the request ({ room, action, target, value, heard }),
--- sent as JSON. Names are matched against the catalog, the Control4 command is
--- sent, and a short sentence comes back for the shortcut to speak.
---
--- Control4 calls go through `opts.send` and `opts.variable`, so the module is
--- tested without a controller.
---
--- Commands sent:
---   lights (light_v2 / light)   ON, OFF, SET_BRIGHTNESS_TARGET (light_v2) / SET_LEVEL (light)
---   Advanced Lighting agent     ACTIVATE_SCENE / DEACTIVATE_SCENE { SCENE_ID }
---   custom buttons (uibutton)   SELECT, as a touch screen sends when the button is pressed
---   Macros agent                EXECUTE_MACRO { id }
---   rooms                       SELECT_AUDIO_DEVICE / SELECT_VIDEO_DEVICE { deviceid },
---                               SET_VOLUME_LEVEL { LEVEL }, PULSE_VOL_UP / PULSE_VOL_DOWN,
---                               MUTE_ON, MUTE_OFF, PLAY, PAUSE, SKIP_FWD, SKIP_REV, ROOM_OFF

local Names = require("voice.names")
local Context = require("voice.context")
local Rtf = require("voice.rtf")
local Thermostat = require("voice.thermostat")

local Commands = {}

--- Room variable: current volume (0-100).
Commands.ROOM_VOLUME_VAR = 1011

local ROOM_MEDIA = {
  mute = { "MUTE_ON", "muted" },
  unmute = { "MUTE_OFF", "unmuted" },
  play = { "PLAY", "playing" },
  pause = { "PAUSE", "paused" },
  ["next"] = { "SKIP_FWD", "next track" },
  previous = { "SKIP_REV", "previous track" },
  room_off = { "ROOM_OFF", "off" },
}

local NEEDS_ROOM = {
  source = true,
  volume_set = true,
  volume_up = true,
  volume_down = true,
}
for name in pairs(ROOM_MEDIA) do
  NEEDS_ROOM[name] = true
end

local function trim(s)
  return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

--- Read the posted command. Accepts the dictionary as JSON, JSON inside other
--- text (a model answering in a code block), JSON inside RTF (Shortcuts posts
--- the Use Model response as a rich text file), or form/query fields.
--- @param body string|nil
--- @param query table<string, string>|nil
--- @param decode fun(s: string): any JSON decoder
--- @return table|nil command { room, action, target, value, heard }
function Commands.parse(body, query, decode)
  local t
  body = tostring(body or "")
  if Rtf.is(body) then
    body = Rtf.toText(body)
  end
  -- Typographic quotes from rich text
  body = body:gsub("\226\128\156", '"'):gsub("\226\128\157", '"')
  if t == nil and body:find("=", 1, true) and not body:find("{", 1, true) then
    local form = {}
    for pair in body:gmatch("[^&\r\n]+") do
      local k, v = pair:match("^%s*([%w_]+)%s*=%s*(.-)%s*$")
      if k ~= nil then
        form[k:lower()] = v:gsub("+", " "):gsub("%%(%x%x)", function(h)
          return string.char(tonumber(h, 16))
        end)
      end
    end
    if form.action ~= nil then
      query = form
    end
  end
  local first, last = body:find("{", 1, true), nil
  for i = #body, 1, -1 do
    if body:sub(i, i) == "}" then
      last = i
      break
    end
  end
  if first ~= nil and last ~= nil and last > first then
    local ok, decoded = pcall(decode, body:sub(first, last))
    if ok and type(decoded) == "table" then
      t = decoded
    end
  end
  if t == nil and query ~= nil and query.action ~= nil then
    t = query
  end
  if t == nil then
    return nil
  end
  -- Keys in any case; a model may nest the dictionary one level down.
  local function get(key)
    for k, v in pairs(t) do
      if tostring(k):lower() == key then
        return v
      end
    end
    return nil
  end
  if get("action") == nil then
    for _, v in pairs(t) do
      if type(v) == "table" then
        return Commands.parse(nil, v, decode) or Commands.parse(nil, nil, decode)
      end
    end
  end
  local function text(key)
    local v = get(key)
    if v == nil or type(v) == "table" then
      return ""
    end
    return trim(v)
  end
  return {
    room = text("room"),
    action = text("action"):lower():gsub("[%s%-]+", "_"),
    target = text("target"),
    value = text("value"),
    heard = text("heard"),
    mode = text("mode"),
  }
end

--- @class CommandOptions
--- @field send fun(deviceId: integer, command: string, params: table)
--- @field variable fun(deviceId: integer, variableId: integer): any
--- @field defaultRoomId integer|nil
--- @field volumeStep number|nil percent for volume_up/down without a value (default 10)
--- @field dryRun boolean|nil only describe, send nothing
--- @field variables (fun(deviceId: integer): table<string, string>)|nil a device's variables by name
--- @field scale string|nil the project's temperature scale (C4:GetTemperatureScale)

--- Find a room by name, else the default room.
local function resolveRoom(data, spoken, opts)
  if spoken ~= nil and spoken ~= "" then
    local room, candidates = Names.find(data.rooms, spoken, nil)
    if room ~= nil then
      return room
    end
    if #candidates > 1 then
      return nil, "Which room: " .. Commands.namesOf(candidates) .. "?"
    end
    return nil, "I don't know a room called " .. spoken .. "."
  end
  for _, room in ipairs(data.rooms) do
    if room.id == opts.defaultRoomId then
      return room
    end
  end
  return nil, "Which room?"
end

--- "A, B or C"
--- @param items { name: string, room?: string }[]
--- @return string
function Commands.namesOf(items)
  local names = {}
  for i, item in ipairs(items) do
    if i > 5 then
      break
    end
    local n = item.name
    if item.room ~= nil and item.room ~= "" then
      n = n .. " in " .. item.room
    end
    names[#names + 1] = n
  end
  if #names <= 1 then
    return names[1] or ""
  end
  return table.concat(names, ", ", 1, #names - 1) .. " or " .. names[#names]
end

--- Find a named thing; returns it or a question / error sentence.
local function resolve(list, what, spoken, room)
  if spoken == nil or spoken == "" then
    return nil, "Which " .. what .. "?"
  end
  local found, candidates = Names.find(list, spoken, room)
  if found ~= nil then
    return found
  end
  if #candidates > 1 then
    return nil, "Which one: " .. Commands.namesOf(candidates) .. "?"
  end
  return nil, "I don't know a " .. what .. " called " .. spoken .. "."
end

local function clamp(n)
  return math.max(0, math.min(100, math.floor(n + 0.5)))
end

--- Run a parsed command.
--- @param cmd table from Commands.parse
--- @param data CatalogData
--- @param opts CommandOptions
--- @return string reply sentence to speak
--- @return { device: integer, command: string, params: table }[] sent what was (or, dry run, would be) sent
--- @return boolean understood false when nothing was done
function Commands.run(cmd, data, opts)
  local sent = {}
  local function send(device, command, params)
    sent[#sent + 1] = { device = device, command = command, params = params or {} }
    if not opts.dryRun then
      opts.send(device, command, params or {})
    end
  end
  local action = cmd.action
  if not Context.VALID[action] or action == "unknown" then
    local heard = cmd.heard ~= "" and (" " .. cmd.heard) or ""
    return "Sorry, I can't do that." .. (heard ~= "" and (" I heard:" .. heard) or ""), sent, false
  end

  if Thermostat.ACTIONS[action] then
    local named = cmd.room ~= "" and Names.find(data.rooms, cmd.room, nil) or nil
    if cmd.room ~= "" and named == nil then
      return "I don't know a room called " .. cmd.room .. ".", sent, false
    end
    local defaultRoom
    for _, r in ipairs(data.rooms) do
      if r.id == opts.defaultRoomId then
        defaultRoom = r
      end
    end
    local reply, understood = Thermostat.run(cmd, data, named, defaultRoom, {
      send = send,
      variables = opts.variables or function()
        return {}
      end,
      scale = Thermostat.scaleLetter(opts.scale),
    })
    return reply, sent, understood
  end

  -- Rooms first for media; for lights the room only helps to pick the name.
  local room, problem
  if NEEDS_ROOM[action] then
    room, problem = resolveRoom(data, cmd.room, opts)
    if room == nil then
      return problem, sent, false
    end
  elseif cmd.room ~= "" then
    room = Names.find(data.rooms, cmd.room, nil)
  end
  local roomName = room and room.name or (cmd.room ~= "" and cmd.room or nil)

  if action == "light_on" or action == "light_off" or action == "light_level" then
    local level = tonumber(cmd.value)
    if action == "light_level" and level == nil then
      return "To what level?", sent, false
    end
    local targets = {}
    if cmd.target == "" and action ~= "light_level" and room ~= nil then
      for _, light in ipairs(data.lights) do
        if light.roomId == room.id then
          targets[#targets + 1] = light
        end
      end
      if #targets == 0 then
        return "There are no lights in " .. room.name .. ".", sent, false
      end
    else
      local light, err = resolve(data.lights, "light", cmd.target, roomName)
      if light == nil then
        return err, sent, false
      end
      targets = { light }
    end
    for _, light in ipairs(targets) do
      if action == "light_on" then
        send(light.id, "ON", {})
      elseif action == "light_off" then
        send(light.id, "OFF", {})
      elseif light.kind == "light" then
        send(light.id, "SET_LEVEL", { LEVEL = clamp(level) })
      else
        send(light.id, "SET_BRIGHTNESS_TARGET", { LIGHT_BRIGHTNESS_TARGET = clamp(level), LEVEL = clamp(level) })
      end
    end
    local what = cmd.target == "" and ("Lights in " .. room.name) or targets[1].name
    if action == "light_on" then
      return what .. " on.", sent, true
    elseif action == "light_off" then
      return what .. " off.", sent, true
    end
    return what .. " " .. clamp(level) .. " percent.", sent, true
  end

  if action == "scene" or action == "scene_off" then
    if data.sceneAgent == nil then
      return "There is no Advanced Lighting agent.", sent, false
    end
    local scene, err = resolve(data.scenes, "scene", cmd.target, roomName)
    if scene == nil then
      return err, sent, false
    end
    send(data.sceneAgent, action == "scene" and "ACTIVATE_SCENE" or "DEACTIVATE_SCENE", { SCENE_ID = scene.id })
    return scene.name .. (action == "scene" and "." or " off."), sent, true
  end

  if action == "scenario" then
    local scenario, err = resolve(data.scenarios, "scenario", cmd.target, roomName)
    if scenario == nil then
      return err, sent, false
    end
    if scenario.kind == "macro" then
      if data.macroAgent == nil then
        return "There is no Macros agent.", sent, false
      end
      send(data.macroAgent, "EXECUTE_MACRO", { id = scenario.id })
    else
      send(scenario.id, "SELECT", {})
    end
    return scenario.name .. ".", sent, true
  end

  -- Room media from here on; `room` is set.
  if action == "source" then
    local inRoom = {}
    for _, s in ipairs(data.sources) do
      if s.roomId == room.id then
        inRoom[#inRoom + 1] = s
      end
    end
    local source, err = resolve(inRoom, "source in " .. room.name, cmd.target, nil)
    if source == nil then
      return err, sent, false
    end
    send(room.id, source.kind == "video" and "SELECT_VIDEO_DEVICE" or "SELECT_AUDIO_DEVICE", { deviceid = source.id })
    return source.name .. " in " .. room.name .. ".", sent, true
  end

  if action == "volume_set" then
    local level = tonumber(cmd.value)
    if level == nil then
      return "What volume?", sent, false
    end
    send(room.id, "SET_VOLUME_LEVEL", { LEVEL = clamp(level) })
    return room.name .. " volume " .. clamp(level) .. ".", sent, true
  end

  if action == "volume_up" or action == "volume_down" then
    local step = tonumber(cmd.value) or opts.volumeStep or 10
    local current = tonumber(opts.variable and opts.variable(room.id, Commands.ROOM_VOLUME_VAR))
    if current == nil then
      -- Volume unknown: pulse instead, one pulse per 2 percent.
      local pulses = math.max(1, math.min(25, math.floor(step / 2 + 0.5)))
      for _ = 1, pulses do
        send(room.id, action == "volume_up" and "PULSE_VOL_UP" or "PULSE_VOL_DOWN", {})
      end
      return room.name .. (action == "volume_up" and " louder." or " quieter."), sent, true
    end
    local level = clamp(current + (action == "volume_up" and step or -step))
    send(room.id, "SET_VOLUME_LEVEL", { LEVEL = level })
    return room.name .. " volume " .. level .. ".", sent, true
  end

  local media = ROOM_MEDIA[action]
  send(room.id, media[1], {})
  return room.name .. " " .. media[2] .. ".", sent, true
end

return Commands
