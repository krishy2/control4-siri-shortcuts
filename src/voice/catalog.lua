--- @module "voice.catalog"
--- What the Siri Shortcuts driver can control, read from the project: rooms,
--- lights, Advanced Lighting scenes, scenarios (custom buttons and macros) and
--- each room's Listen and Watch sources. The AI gets these names in the
--- context, and commands are matched against them.
---
--- Read with documented calls where they exist:
---   C4:GetDevices({ C4iNames = ... })  devices with their room (OS 2.10+)
---   C4:SendUIRequest(room, "GET_LISTEN_DEVICES" / "GET_WATCH_DEVICES")
---     (confirmed on the user's controller with the ESPHome room media work)
--- and, where Control4 documents nothing, with the requests a controller is
--- known to answer (Advanced Lighting GET_SCENE_LIST, Macros GET_MACROS; seen
--- on OS 4.3). A request that is not answered just leaves that list empty.

local Names = require("voice.names")
local Thermostat = require("voice.thermostat")

local Catalog = {}

Catalog.ROOM_C4I = "roomdevice.c4i"
Catalog.LIGHT_C4I = { "light_v2.c4i", "light.c4i" }
Catalog.BUTTON_C4I = { "uibutton.c4i" }
Catalog.SCENE_AGENT_C4I = { "control4_agent_adv_lighting.c4i", "control4_agent_advanced_lighting.c4i" }
Catalog.MACRO_AGENT_C4I = { "control4_agent_macros.c4i" }
Catalog.SCENE_REQUESTS = { "GET_SCENE_LIST", "GET_SCENES", "GET_ALL_SCENES" }
Catalog.MACRO_REQUESTS = { "GET_MACROS", "GET_MACRO_LIST" }
--- Experience buttons that are not scenarios: web views, and this suite's own.
Catalog.BUTTON_EXCLUDE = { "webview", "cp_mqtt", "cp_siri" }
--- Device IDs near 2^32 in Navigator lists are Navigator's own entries.
Catalog.MAX_DEVICE_ID = 100000

--- @class CatalogRoom
--- @field id integer
--- @field name string

--- @class CatalogItem
--- @field id integer
--- @field name string
--- @field room string|nil
--- @field roomId integer|nil
--- @field kind string|nil "light_v2" | "light" | "button" | "macro" | "audio" | "video"

--- @class CatalogData
--- @field rooms CatalogRoom[]
--- @field lights CatalogItem[]
--- @field scenes CatalogItem[]
--- @field scenarios CatalogItem[]
--- @field sources CatalogItem[]
--- @field thermostats CatalogItem[] with `modes` (string[])
--- @field sceneAgent integer|nil
--- @field macroAgent integer|nil
--- @field notes string[] what could not be read, for the log

local function call(fn, ...)
  if type(fn) ~= "function" then
    return nil
  end
  local ok, result = pcall(fn, C4, ...)
  if ok then
    return result
  end
  return nil
end

local function unescape(s)
  return (
    tostring(s or ""):gsub("&lt;", "<"):gsub("&gt;", ">"):gsub("&quot;", '"'):gsub("&apos;", "'"):gsub("&amp;", "&")
  )
end

--- Text of the first of `tags` in an XML fragment (element or attribute).
local function field(block, tags)
  for _, tag in ipairs(tags) do
    local v = block:match("<" .. tag .. "[^>]*>(.-)</" .. tag .. ">")
    if v ~= nil then
      return unescape(v)
    end
    v = block:match("%s" .. tag .. '="([^"]*)"')
    if v ~= nil then
      return unescape(v)
    end
  end
  return nil
end

--- Records with an id and a name in a reply: <scene_info><scene_id>0</scene_id>
--- <name>All On</name>...</scene_info>, <macro><id>3</id><name>...</name></macro>.
--- @param xml string|nil
--- @param tags string[] element names of one record
--- @param idTags string[]
--- @return { id: integer, name: string }[]
function Catalog.records(xml, tags, idTags)
  local out, seen = {}, {}
  if type(xml) ~= "string" then
    return out
  end
  xml = xml:find("&lt;", 1, true) and not xml:find("<", 1, true) and unescape(xml) or xml
  for _, tag in ipairs(tags) do
    for block in xml:gmatch("<" .. tag .. "[%s>].-</" .. tag .. ">") do
      local id = tonumber(field(block, idTags))
      local name = field(block, { "name", "display_name", "NAME" })
      if id ~= nil and name ~= nil and name ~= "" and not seen[id] then
        seen[id] = true
        out[#out + 1] = { id = math.floor(id), name = name }
      end
    end
  end
  return out
end

--- Every device ID in a reply, in order: <id>12</id>, <deviceid>12</deviceid>,
--- id="12".
--- @param xml string|nil
--- @return integer[]
function Catalog.deviceIds(xml)
  local out, seen = {}, {}
  if type(xml) ~= "string" then
    return out
  end
  local function add(v)
    local id = tonumber(v)
    if id ~= nil and id > 0 and id < Catalog.MAX_DEVICE_ID and not seen[id] then
      seen[id] = true
      out[#out + 1] = math.floor(id)
    end
  end
  local found = {}
  for _, pattern in ipairs({
    "()<[Ii][Dd]>%s*(%d+)%s*</",
    "()<[Dd]evice_?[Ii][Dd]>%s*(%d+)%s*</",
    '()%s[Ii][Dd]="(%d+)"',
    '()%s[Dd]evice_?[Ii][Dd]="(%d+)"',
  }) do
    for position, value in xml:gmatch(pattern) do
      found[#found + 1] = { position = position, value = value }
    end
  end
  table.sort(found, function(a, b)
    return a.position < b.position
  end)
  for _, f in ipairs(found) do
    add(f.value)
  end
  return out
end

--- A device's variables by name: { HVAC_MODE = "Cool", ... }.
--- @param id integer
--- @return table<string, string>
function Catalog.variables(id)
  local out = {}
  local list = call(C4.GetDeviceVariables, id)
  for _, v in pairs(type(list) == "table" and list or {}) do
    if type(v) == "table" and v.name ~= nil then
      out[tostring(v.name)] = v.value ~= nil and tostring(v.value) or nil
    end
  end
  return out
end

--- Devices of these driver files: id -> { deviceName, roomId, roomName, protocol }.
local function devicesOf(files)
  local list = call(C4.GetDevices, { C4iNames = table.concat(files, ",") })
  return type(list) == "table" and list or {}
end

--- First device of an agent's driver file.
local function agentId(files)
  for _, file in ipairs(files) do
    local list = call(C4.GetDevicesByC4iName, file)
    if type(list) == "table" then
      for k, v in pairs(list) do
        local id = tonumber(type(v) == "number" and v or k)
        if id ~= nil then
          return math.floor(id)
        end
      end
    end
    for id in pairs(devicesOf({ file })) do
      return tonumber(id)
    end
  end
  return nil
end

local function sortByName(list)
  table.sort(list, function(a, b)
    local ra, rb = a.room or "", b.room or ""
    if ra ~= rb then
      return ra < rb
    end
    return a.name < b.name
  end)
  return list
end

--- The protocol driver file name of a proxy, as GetDevices reports it.
local function protocolFile(device)
  for _, p in pairs(type(device.protocol) == "table" and device.protocol or {}) do
    if type(p) == "table" and p.driverFileName ~= nil then
      return tostring(p.driverFileName)
    end
  end
  return ""
end

--- Read everything from the project.
--- @param opts? { hidden?: fun(name: string): boolean, ownId?: integer }
--- @return CatalogData
function Catalog.read(opts)
  opts = opts or {}
  local hidden = opts.hidden or function()
    return false
  end
  local data = { rooms = {}, lights = {}, scenes = {}, scenarios = {}, sources = {}, thermostats = {}, notes = {} }
  local roomNames = {}

  local function noteRoom(id, name)
    id = tonumber(id)
    if id ~= nil and name ~= nil and name ~= "" and roomNames[id] == nil then
      roomNames[id] = tostring(name)
    end
  end

  -- Rooms: the room devices, plus the room of every device found below.
  for k, v in pairs(call(C4.GetDevicesByC4iName, Catalog.ROOM_C4I) or {}) do
    local id = tonumber(type(v) == "number" and v or k)
    local name = type(v) == "string" and v or nil
    if (name == nil or name == "") and id ~= nil then
      name = call(C4.GetDeviceDisplayName, id)
    end
    noteRoom(id, name)
  end

  -- Lights
  for id, device in pairs(devicesOf(Catalog.LIGHT_C4I)) do
    id = tonumber(id)
    if id ~= nil and type(device) == "table" and not hidden(device.deviceName or "") then
      noteRoom(device.roomId, device.roomName)
      table.insert(data.lights, {
        id = id,
        name = tostring(device.deviceName or ("Light " .. id)),
        room = device.roomName,
        roomId = tonumber(device.roomId),
        kind = device.driverFileName == "light.c4i" and "light" or "light_v2",
      })
    end
  end

  -- Thermostats, with the modes each offers
  for id, device in pairs(devicesOf(Thermostat.C4I)) do
    id = tonumber(id)
    if id ~= nil and type(device) == "table" and not hidden(device.deviceName or "") then
      noteRoom(device.roomId, device.roomName)
      table.insert(data.thermostats, {
        id = id,
        name = tostring(device.deviceName or ("Thermostat " .. id)),
        room = device.roomName,
        roomId = tonumber(device.roomId),
        modes = Thermostat.modes(Catalog.variables(id)),
      })
    end
  end

  -- Scenarios: Experience (custom) buttons ...
  for id, device in pairs(devicesOf(Catalog.BUTTON_C4I)) do
    id = tonumber(id)
    local protocol = protocolFile(type(device) == "table" and device or {}):lower()
    local excluded = id == opts.ownId
    for _, word in ipairs(Catalog.BUTTON_EXCLUDE) do
      excluded = excluded or protocol:find(word, 1, true) ~= nil
    end
    if id ~= nil and type(device) == "table" and not excluded and not hidden(device.deviceName or "") then
      noteRoom(device.roomId, device.roomName)
      table.insert(data.scenarios, {
        id = id,
        name = tostring(device.deviceName or ("Button " .. id)),
        room = device.roomName,
        roomId = tonumber(device.roomId),
        kind = "button",
      })
    end
  end

  -- ... and macros
  data.macroAgent = agentId(Catalog.MACRO_AGENT_C4I)
  if data.macroAgent ~= nil then
    local found = {}
    for _, request in ipairs(Catalog.MACRO_REQUESTS) do
      found = Catalog.records(call(C4.SendUIRequest, data.macroAgent, request, {}), { "macro" }, { "id", "macro_id" })
      if #found > 0 then
        break
      end
    end
    for _, macro in ipairs(found) do
      if not hidden(macro.name) then
        table.insert(data.scenarios, { id = macro.id, name = macro.name, kind = "macro" })
      end
    end
  end

  -- Advanced Lighting scenes
  data.sceneAgent = agentId(Catalog.SCENE_AGENT_C4I)
  if data.sceneAgent == nil then
    table.insert(data.notes, "no Advanced Lighting agent found")
  else
    local found = {}
    for _, request in ipairs(Catalog.SCENE_REQUESTS) do
      found = Catalog.records(
        call(C4.SendUIRequest, data.sceneAgent, request, {}),
        { "scene_info", "scene" },
        { "scene_id", "id" }
      )
      if #found > 0 then
        break
      end
    end
    if #found == 0 then
      table.insert(data.notes, "the Advanced Lighting agent listed no scenes")
    end
    for _, scene in ipairs(found) do
      if not hidden(scene.name) then
        table.insert(data.scenes, { id = scene.id, name = scene.name })
      end
    end
  end

  -- Rooms, sorted, then each room's sources
  for id, name in pairs(roomNames) do
    if not hidden(name) then
      table.insert(data.rooms, { id = id, name = name })
    end
  end
  table.sort(data.rooms, function(a, b)
    return a.name < b.name
  end)

  local sourceIds, perRoom = {}, {}
  for _, room in ipairs(data.rooms) do
    perRoom[room.id] = {}
    for _, kind in ipairs({ "audio", "video" }) do
      local request = kind == "audio" and "GET_LISTEN_DEVICES" or "GET_WATCH_DEVICES"
      for _, id in ipairs(Catalog.deviceIds(call(C4.SendUIRequest, room.id, request, {}))) do
        table.insert(perRoom[room.id], { id = id, kind = kind })
        sourceIds[#sourceIds + 1] = id
      end
    end
  end
  local names = {}
  if #sourceIds > 0 then
    for id, device in pairs(call(C4.GetDevices, { DeviceIds = table.concat(sourceIds, ",") }) or {}) do
      if type(device) == "table" and device.deviceName ~= nil then
        names[tonumber(id)] = tostring(device.deviceName)
      end
    end
  end
  for _, room in ipairs(data.rooms) do
    local seen = {}
    for _, s in ipairs(perRoom[room.id]) do
      local name = names[s.id] or call(C4.GetDeviceDisplayName, s.id)
      -- A device in both lists is offered once, as a Watch source.
      local key = s.id
      if name ~= nil and name ~= "" and not hidden(name) then
        if seen[key] == nil then
          seen[key] = #data.sources + 1
          table.insert(data.sources, { id = s.id, name = name, room = room.name, roomId = room.id, kind = s.kind })
        elseif s.kind == "video" then
          data.sources[seen[key]].kind = "video"
        end
      end
    end
  end

  sortByName(data.lights)
  sortByName(data.thermostats)
  sortByName(data.scenarios)
  table.sort(data.scenes, function(a, b)
    return a.name < b.name
  end)
  return data
end

--- Short summary for the Known Names property.
--- @param data CatalogData
--- @return string
function Catalog.summary(data)
  return string.format(
    "%d rooms, %d lights, %d scenes, %d scenarios, %d sources, %d thermostats",
    #data.rooms,
    #data.lights,
    #data.scenes,
    #data.scenarios,
    #data.sources,
    #(data.thermostats or {})
  )
end

--- The room a name means.
--- @param data CatalogData
--- @param spoken string|nil
--- @return CatalogRoom|nil
--- @return CatalogRoom[] candidates
function Catalog.findRoom(data, spoken)
  return Names.find(data.rooms, spoken, nil)
end

return Catalog
