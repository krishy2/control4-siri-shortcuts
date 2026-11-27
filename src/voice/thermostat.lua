--- @module "voice.thermostat"
--- Thermostats for the Siri Shortcuts driver: set the temperature, warmer or
--- cooler, change the HVAC mode, and say the temperature.
---
--- Talks to the thermostatV2 proxy the way Control4 programming and the
--- Director API do:
---   SET_SETPOINT_HEAT / SET_SETPOINT_COOL / SET_SETPOINT_SINGLE { CELSIUS | FAHRENHEIT }
---   SET_MODE_HVAC { MODE }
--- and reads its variables by name: TEMPERATURE_C/_F, HEAT_SETPOINT_C/_F,
--- COOL_SETPOINT_C/_F, SINGLE_SETPOINT_C/_F, HVAC_MODE, HVAC_MODES_LIST,
--- HVAC_STATE.
---
--- Spoken temperatures are in the project's scale (C4:GetTemperatureScale).

local Names = require("voice.names")

local Thermostat = {}

Thermostat.C4I = { "thermostatV2.c4i", "thermostatv2.c4i", "thermostat_v2.c4i", "thermostat.c4i" }
Thermostat.DEFAULT_MODES = { "Off", "Heat", "Cool", "Auto" }
--- Warmer / cooler without a number, in degrees of the project's scale.
Thermostat.DEFAULT_STEP = 1

--- Actions this module carries out.
Thermostat.ACTIONS = {
  thermostat_set = true,
  thermostat_up = true,
  thermostat_down = true,
  thermostat_mode = true,
  temperature = true,
}

--- "C" or "F" from the project's scale ("CELSIUS", "FAHRENHEIT", "C", "F").
--- @param scale string|nil
--- @return string
function Thermostat.scaleLetter(scale)
  return tostring(scale or ""):upper():sub(1, 1) == "F" and "F" or "C"
end

--- Number from a variable value ("23.5", "235" is not guessed).
local function num(v)
  return tonumber(v)
end

--- Round to one decimal for speaking ("22", "22.5").
--- @param n number
--- @return string
function Thermostat.say(n)
  local r = math.floor(n * 10 + 0.5) / 10
  if r == math.floor(r) then
    return string.format("%d", r)
  end
  return string.format("%.1f", r)
end

--- The modes a thermostat offers, from HVAC_MODES_LIST.
--- @param vars table<string, string>
--- @return string[]
function Thermostat.modes(vars)
  local out = {}
  for item in tostring(vars.HVAC_MODES_LIST or ""):gmatch("[^,]+") do
    item = item:gsub("^%s+", ""):gsub("%s+$", "")
    if item ~= "" then
      out[#out + 1] = item
    end
  end
  if #out == 0 then
    return Thermostat.DEFAULT_MODES
  end
  return out
end

--- What a thermostat reports, in the project's scale.
--- @param vars table<string, string>
--- @param scale string "C" or "F"
--- @return { temperature: number|nil, heat: number|nil, cool: number|nil, single: number|nil, mode: string|nil, state: string|nil, humidity: number|nil }
function Thermostat.state(vars, scale)
  local s = "_" .. scale
  return {
    temperature = num(vars["TEMPERATURE" .. s]),
    heat = num(vars["HEAT_SETPOINT" .. s]),
    cool = num(vars["COOL_SETPOINT" .. s]),
    single = num(vars["SINGLE_SETPOINT" .. s]),
    mode = vars.HVAC_MODE,
    state = vars.HVAC_STATE,
    humidity = num(vars.HUMIDITY),
  }
end

--- The setpoint a new target goes to: "single", "heat" or "cool".
--- Follows the mode; in Auto (or unknown) it heats towards a target above the
--- room temperature and cools towards one below it.
--- @param st table from Thermostat.state
--- @param target number
--- @return string
function Thermostat.which(st, target)
  local mode = tostring(st.mode or ""):lower()
  if st.single ~= nil and st.heat == nil and st.cool == nil then
    return "single"
  end
  if st.heat ~= nil and st.cool == nil then
    return "heat"
  end
  if st.cool ~= nil and st.heat == nil then
    return "cool"
  end
  if mode:find("cool", 1, true) then
    return "cool"
  end
  if mode:find("heat", 1, true) then
    return "heat"
  end
  if st.temperature ~= nil and target > st.temperature then
    return "heat"
  end
  if st.temperature ~= nil then
    return "cool"
  end
  return st.cool ~= nil and "cool" or "heat"
end

local SETPOINT_COMMAND = {
  single = "SET_SETPOINT_SINGLE",
  heat = "SET_SETPOINT_HEAT",
  cool = "SET_SETPOINT_COOL",
}

--- The thermostat a command means: by name, else the room's only one, else the
--- project's only one.
--- @param data CatalogData
--- @param target string
--- @param room CatalogRoom|nil
--- @return CatalogItem|nil
--- @return string|nil problem
function Thermostat.resolve(data, target, room)
  local list = data.thermostats or {}
  if #list == 0 then
    return nil, "There is no thermostat."
  end
  if target ~= nil and target ~= "" then
    local found, candidates = Names.find(list, target, room and room.name or nil)
    if found ~= nil then
      return found
    end
    if #candidates > 1 then
      local names = {}
      for i, c in ipairs(candidates) do
        names[i] = c.room and (c.name .. " in " .. c.room) or c.name
      end
      return nil, "Which one: " .. table.concat(names, " or ") .. "?"
    end
    -- "Living room" said as the target: try it as a room.
    local asRoom = Names.find(data.rooms, target, nil)
    if asRoom ~= nil then
      room = asRoom
    else
      return nil, "I don't know a thermostat called " .. target .. "."
    end
  end
  if room ~= nil then
    local inRoom = {}
    for _, t in ipairs(list) do
      if t.roomId == room.id then
        inRoom[#inRoom + 1] = t
      end
    end
    if #inRoom == 1 then
      return inRoom[1]
    elseif #inRoom == 0 then
      return nil, "There is no thermostat in " .. room.name .. "."
    end
    local names = {}
    for i, t in ipairs(inRoom) do
      names[i] = t.name
    end
    return nil, "Which one: " .. table.concat(names, " or ") .. "?"
  end
  if #list == 1 then
    return list[1]
  end
  return nil, "Which thermostat?"
end

--- Words for modes that are not the mode's name.
Thermostat.MODE_WORDS = {
  cooling = "cool",
  cold = "cool",
  ac = "cool",
  ["air conditioning"] = "cool",
  ["air conditioner"] = "cool",
  heating = "heat",
  warm = "heat",
  automatic = "auto",
  fan = "fan only",
  ventilation = "fan only",
  dehumidify = "dry",
}

--- The mode a spoken word means: the mode's name, a word for it, or a name
--- the word starts with ("cooling" -> Cool).
--- @param modes { id: integer, name: string }[]
--- @param spoken string
--- @return { id: integer, name: string }|nil
function Thermostat.findMode(modes, spoken)
  local word = Names.normalize(spoken)
  word = Thermostat.MODE_WORDS[word] or word
  local found = Names.find(modes, word, nil)
  if found ~= nil then
    return found
  end
  for _, m in ipairs(modes) do
    local name = Names.normalize(m.name)
    if name ~= "" and word:sub(1, #name) == name then
      return m
    end
  end
  return nil
end

--- How a thermostat is named in a reply: its room when it has one.
local function label(t)
  return (t.room ~= nil and t.room ~= "") and t.room or t.name
end

--- Run a thermostat action.
--- @param cmd table parsed command
--- @param data CatalogData
--- @param room CatalogRoom|nil room named in the request (or nil)
--- @param defaultRoom CatalogRoom|nil
--- @param opts { send: fun(id: integer, command: string, params: table), variables: fun(id: integer): table<string, string>, scale: string }
--- @return string reply
--- @return boolean understood
function Thermostat.run(cmd, data, room, defaultRoom, opts)
  local t, problem = Thermostat.resolve(data, cmd.target, room)
  if t == nil and room == nil and (cmd.target == nil or cmd.target == "") and defaultRoom ~= nil then
    -- Nothing named: the default room's thermostat, if it has exactly one.
    local fallback = Thermostat.resolve(data, "", defaultRoom)
    t = fallback or t
  end
  if t == nil then
    return problem, false
  end
  local scale = opts.scale
  local vars = opts.variables(t.id) or {}
  local st = Thermostat.state(vars, scale)
  local action = cmd.action

  if action == "temperature" then
    if st.temperature == nil then
      return "I can't read the temperature in " .. label(t) .. ".", false
    end
    local parts = { label(t) .. " is " .. Thermostat.say(st.temperature) .. " degrees" }
    local which = Thermostat.which(st, st.temperature)
    local setpoint = st[which]
    if tostring(st.mode or ""):lower() == "off" then
      parts[#parts + 1] = "the thermostat is off"
    elseif setpoint ~= nil then
      parts[#parts + 1] = "set to " .. Thermostat.say(setpoint)
    end
    return table.concat(parts, ", ") .. ".", true
  end

  -- The mode asked for: thermostat_mode's value, or the mode key of any thermostat command.
  local modes = {}
  for i, m in ipairs(Thermostat.modes(vars)) do
    modes[i] = { id = i, name = m }
  end
  local function modeNames()
    local names = {}
    for i, m in ipairs(modes) do
      names[i] = m.name
    end
    return table.concat(names, ", ")
  end
  local wantedMode = cmd.mode or ""
  if action == "thermostat_mode" and wantedMode == "" then
    wantedMode = tostring(cmd.value ~= "" and cmd.value or cmd.target or "")
  end
  local newMode = nil
  if wantedMode ~= "" then
    local found = Thermostat.findMode(modes, wantedMode)
    if found == nil then
      return label(t) .. " can be " .. modeNames() .. ".", false
    end
    newMode = found.name
  elseif action == "thermostat_mode" then
    return label(t) .. " can be " .. modeNames() .. ".", false
  end

  if action == "thermostat_mode" then
    opts.send(t.id, "SET_MODE_HVAC", { MODE = newMode })
    return label(t) .. " " .. newMode:lower() .. ".", true
  end

  -- Setpoint commands with a mode: switch first, then the setpoint follows the new mode.
  if newMode ~= nil and action ~= "temperature" then
    opts.send(t.id, "SET_MODE_HVAC", { MODE = newMode })
    st.mode = newMode
  end

  -- Setpoints
  local target, which
  if action == "thermostat_set" then
    target = tonumber(cmd.value)
    if target == nil then
      return "To what temperature?", false
    end
    which = Thermostat.which(st, target)
  else
    -- Warmer / cooler moves the setpoint in use: the mode's, else the one the
    -- thermostat is working towards (HVAC_STATE).
    local mode = tostring(st.mode or ""):lower()
    local state = tostring(st.state or ""):lower()
    if st.single ~= nil and st.heat == nil and st.cool == nil then
      which = "single"
    elseif st.heat ~= nil and st.cool == nil then
      which = "heat"
    elseif st.cool ~= nil and st.heat == nil then
      which = "cool"
    elseif mode:find("cool", 1, true) or state:find("cool", 1, true) then
      which = "cool"
    elseif mode:find("heat", 1, true) or state:find("heat", 1, true) then
      which = "heat"
    else
      which = st.cool ~= nil and "cool" or "heat"
    end
    local base = st[which]
    if base == nil then
      return "I can't read the setpoint of " .. label(t) .. ".", false
    end
    local step = tonumber(cmd.value) or Thermostat.DEFAULT_STEP
    target = base + (action == "thermostat_up" and step or -step)
  end
  local params = scale == "F" and { FAHRENHEIT = target } or { CELSIUS = target }
  opts.send(t.id, SETPOINT_COMMAND[which], params)
  local reply = label(t) .. " set to " .. Thermostat.say(target) .. " degrees"
  if newMode ~= nil and newMode:lower() ~= "off" then
    reply = label(t) .. " " .. newMode:lower() .. ", set to " .. Thermostat.say(target) .. " degrees"
  end
  if tostring(st.mode or ""):lower() == "off" then
    reply = reply .. "; the thermostat is off"
  end
  return reply .. ".", true
end

return Thermostat
