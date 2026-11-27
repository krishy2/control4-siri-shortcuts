-- Tests for the Siri Shortcuts driver: HTTP parsing (src/voice/http.lua), name
-- matching (names.lua), reading the project (catalog.lua), the context text
-- (context.lua) and carrying out commands (commands.lua).
--
-- Run from the repo root:
--   make test
-- or:
--   ./test/run_test.sh test_siri_shortcuts.lua

local T = require("testlib")
require("c4_shim")
require("lib.utils")
require("drivers-common-public.global.handlers")
require("drivers-common-public.global.lib")
require("drivers-common-public.global.timer")
JSON = JSON or require("JSON")

local Http = require("voice.http")
local Names = require("voice.names")
local Catalog = require("voice.catalog")
local Context = require("voice.context")
local Commands = require("voice.commands")

local function decode(s)
  return JSON:decode(s)
end

-----------------------------------------------------------------------
T.section("HTTP: a request in pieces")
local reader = Http.reader()
local req, status = reader:feed("POST /execute HTTP/1.1\r\nHost: 10.0.0.2:8765\r\nContent-Le")
T.eq("headers not complete yet", { req, status }, {})
req, status = reader:feed('ngth: 18\r\nContent-Type: application/json\r\n\r\n{"action":')
T.eq("body not complete yet", { req, status }, {})
req = reader:feed('"pause"}')
T.eq("method", req.method, "POST")
T.eq("path", req.path, "/execute")
T.eq("header names in lower case", req.headers["content-type"], "application/json")
T.eq("body", req.body, '{"action":"pause"}')

T.section("HTTP: GET with a query")
req = Http.reader():feed("GET /execute?action=volume_set&room=Living%20Room&value=30 HTTP/1.1\r\n\r\n")
T.eq("query decoded", req.query, { action = "volume_set", room = "Living Room", value = "30" })
T.eq("no body", req.body, "")

T.section("HTTP: broken and oversized")
local _, bad = Http.reader():feed("hello\r\n\r\n")
T.eq("no request line", bad, 400)
local _, big = Http.reader():feed(string.rep("x", Http.MAX_REQUEST + 1))
T.eq("too large", big, 413)

T.section("HTTP: response")
local resp = Http.response(200, "Dining on.")
T.contains("status line", resp, "HTTP/1.1 200 OK\r\n")
T.contains("length counts bytes", resp, "Content-Length: 10\r\n")
T.contains("closes", resp, "Connection: close")
T.truthy("body last", resp:sub(-10) == "Dining on.")

-----------------------------------------------------------------------
T.section("Names: normalize")
T.eq("accents and case", Names.normalize("Megjöttünk!"), "megjottunk")
T.eq("punctuation", Names.normalize("  Living-Room / Ceiling "), "living room ceiling")
T.eq("Hungarian long accents", Names.normalize("Gyertyafény ŐSZ"), "gyertyafeny osz")

local lights = {
  { id = 1, name = "Dining", room = "Living Room" },
  { id = 2, name = "Ceiling", room = "Living Room" },
  { id = 3, name = "Ceiling", room = "Bedroom" },
  { id = 4, name = "Entrance", room = "Entrance" },
}

T.section("Names: find")
T.eq("exact", (Names.find(lights, "Dining")).id, 1)
T.eq("misspelled", (Names.find(lights, "dinning")).id, 1)
T.eq("room picks the one", (Names.find(lights, "Ceiling", "Bedroom")).id, 3)
T.eq("room in the spoken name", (Names.find(lights, "bedroom ceiling")).id, 3)
local none, candidates = Names.find(lights, "Ceiling")
T.eq("ambiguous without a room", none, nil)
T.eq("both candidates", #candidates, 2)
T.eq("unknown", (Names.find(lights, "Garage")), nil)

T.section("Names: hidden")
local hidden = Names.hider("Test*, Purchased Drivers")
T.truthy("wildcard", hidden("Test light 2"))
T.truthy("exact, case ignored", hidden("purchased drivers"))
T.falsy("others", hidden("Dining"))

-----------------------------------------------------------------------
T.section("Catalog: reading the project")
local ROOM_LIVING, ROOM_BED = 100, 200
local SCENES, MACROS = 900, 901
ShimSetDevices({
  [ROOM_LIVING] = { deviceName = "Living Room", driverFileName = "roomdevice.c4i" },
  [ROOM_BED] = { deviceName = "Bedroom", driverFileName = "roomdevice.c4i" },
  [11] = { deviceName = "Dining", driverFileName = "light_v2.c4i", roomId = "100", roomName = "Living Room" },
  [12] = { deviceName = "Ceiling", driverFileName = "light_v2.c4i", roomId = "200", roomName = "Bedroom" },
  [13] = { deviceName = "Old Lamp", driverFileName = "light.c4i", roomId = "200", roomName = "Bedroom" },
  [21] = {
    deviceName = "Megjöttünk",
    driverFileName = "uibutton.c4i",
    roomId = "100",
    roomName = "Living Room",
    protocol = { [20] = { driverFileName = "uibutton.c4i", deviceName = "Megjöttünk" } },
  },
  [23] = {
    deviceName = "Air Quality",
    driverFileName = "uibutton.c4i",
    roomId = "100",
    roomName = "Living Room",
    protocol = { [22] = { driverFileName = "cp_mqtt_general_webview.c4z", deviceName = "Air Quality" } },
  },
  [31] = { deviceName = "Sonos", driverFileName = "sonos.c4z", roomId = "100", roomName = "Living Room" },
  [32] = { deviceName = "Apple TV", driverFileName = "appletv.c4z", roomId = "100", roomName = "Living Room" },
  [SCENES] = { deviceName = "Advanced Lighting", driverFileName = "control4_agent_adv_lighting.c4i" },
  [MACROS] = { deviceName = "Macros", driverFileName = "control4_agent_macros.c4i" },
})
C4.SendUIRequest = function(_, device, request)
  if device == SCENES and request == "GET_SCENE_LIST" then
    return "<scene_list><scene_info><scene_id>0</scene_id><name>Evening</name><is_active>False</is_active>"
      .. "</scene_info><scene_info><scene_id>3</scene_id><name>All Off</name></scene_info></scene_list>"
  elseif device == MACROS and request == "GET_MACROS" then
    return "<macros><macro><id>7</id><name>Good Night</name></macro></macros>"
  elseif device == ROOM_LIVING and request == "GET_LISTEN_DEVICES" then
    return "<devices><device><id>31</id></device><device><id>32</id></device><device><id>4294966295</id></device></devices>"
  elseif device == ROOM_LIVING and request == "GET_WATCH_DEVICES" then
    return '<devices><device deviceid="32" name="Apple TV"/></devices>'
  end
  return nil
end

local data = Catalog.read({ hidden = Names.hider("Old*") })
T.eq("rooms", data.rooms, { { id = 200, name = "Bedroom" }, { id = 100, name = "Living Room" } })
T.eq("lights sorted by room, hidden left out", #data.lights, 2)
T.eq(
  "first light",
  { data.lights[1].name, data.lights[1].room, data.lights[1].kind },
  { "Ceiling", "Bedroom", "light_v2" }
)
T.eq("scenes from GET_SCENE_LIST", data.scenes, { { id = 3, name = "All Off" }, { id = 0, name = "Evening" } })
T.eq("scene agent", data.sceneAgent, SCENES)
local scenarioNames = {}
for _, s in ipairs(data.scenarios) do
  scenarioNames[#scenarioNames + 1] = s.name .. "/" .. s.kind
end
T.eq(
  "custom button and macro; the webview button is not a scenario",
  scenarioNames,
  { "Good Night/macro", "Megjöttünk/button" }
)
local sourceNames = {}
for _, s in ipairs(data.sources) do
  sourceNames[#sourceNames + 1] = s.name .. "/" .. s.kind .. "/" .. s.room
end
T.eq(
  "sources: Navigator ids skipped, Apple TV once as video",
  sourceNames,
  { "Sonos/audio/Living Room", "Apple TV/video/Living Room" }
)
T.eq("summary", Catalog.summary(data), "2 rooms, 2 lights, 2 scenes, 2 scenarios, 2 sources")

T.section("Catalog: no agents")
ShimSetDevices({
  [11] = { deviceName = "Dining", driverFileName = "light_v2.c4i", roomId = "100", roomName = "Living Room" },
})
local small = Catalog.read()
T.eq("room from the light", small.rooms, { { id = 100, name = "Living Room" } })
T.eq("no scenes", #small.scenes, 0)
T.contains("noted", table.concat(small.notes, ";"), "no Advanced Lighting agent")

-----------------------------------------------------------------------
T.section("Context")
local text = Context.build(data, { defaultRoom = "Living Room", extra = "Nappali means Living Room." })
T.contains("keys", text, "- room:")
T.contains("actions listed", text, "volume_set: value = volume 0-100")
T.contains("lights with rooms", text, "- Dining (room: Living Room)")
T.contains("scenes", text, "- Evening")
T.contains("scenarios", text, "- Megjöttünk (room: Living Room)")
T.contains("default room", text, "the home uses Living Room")
T.contains("extra instructions", text, "- Nappali means Living Room.")
T.excludes("hidden name", text, "Old Lamp")

-----------------------------------------------------------------------
T.section("Commands: parse")
T.eq(
  "dictionary JSON",
  Commands.parse('{"room":"Living Room","action":"Volume Set","target":"","value":30,"heard":"x"}', nil, decode),
  { room = "Living Room", action = "volume_set", target = "", value = "30", heard = "x" }
)
T.eq(
  "JSON in a code block, keys in any case",
  Commands.parse('```json\n{"Action":"pause","Room":"Bedroom"}\n```', nil, decode).action,
  "pause"
)
T.eq("query fields", Commands.parse("", { action = "play", room = "Bedroom" }, decode).room, "Bedroom")
T.eq("nothing usable", Commands.parse("hello", nil, decode), nil)

local sent, variables = {}, {}
local function run(cmd, extra)
  sent = {}
  local opts = {
    send = function(device, command, params)
      sent[#sent + 1] = { device, command, params }
    end,
    variable = function(device, id)
      return variables[device .. ":" .. id]
    end,
    defaultRoomId = ROOM_LIVING,
    volumeStep = 10,
  }
  for k, v in pairs(extra or {}) do
    opts[k] = v
  end
  local full = { room = "", action = "", target = "", value = "", heard = "" }
  for k, v in pairs(cmd) do
    full[k] = v
  end
  return Commands.run(full, data, opts)
end

T.section("Commands: lights")
T.eq(
  "on",
  { run({ action = "light_on", target = "dinning" }) },
  { "Dining on.", { { device = 11, command = "ON", params = {} } }, true }
)
T.eq("sent", sent, { { 11, "ON", {} } })
local reply = run({ action = "light_level", target = "Dining", value = "40" })
T.eq("level reply", reply, "Dining 40 percent.")
T.eq("level command", sent[1][2], "SET_BRIGHTNESS_TARGET")
T.eq("level value", sent[1][3].LIGHT_BRIGHTNESS_TARGET, 40)
T.eq("room's lights off", (run({ action = "light_off", room = "Bedroom" })), "Lights in Bedroom off.")
T.eq("level needs a number", (run({ action = "light_level", target = "Dining" })), "To what level?")
T.eq("unknown light", (run({ action = "light_on", target = "Garage" })), "I don't know a light called Garage.")

T.section("Commands: scenes and scenarios")
run({ action = "scene", target = "evening" })
T.eq("activate", sent, { { SCENES, "ACTIVATE_SCENE", { SCENE_ID = 0 } } })
run({ action = "scene_off", target = "All Off" })
T.eq("deactivate", sent, { { SCENES, "DEACTIVATE_SCENE", { SCENE_ID = 3 } } })
T.eq("button", (run({ action = "scenario", target = "Megjottunk" })), "Megjöttünk.")
T.eq("button pressed", sent, { { 21, "SELECT", {} } })
run({ action = "scenario", target = "good night" })
T.eq("macro", sent, { { MACROS, "EXECUTE_MACRO", { id = 7 } } })

T.section("Commands: room media")
T.eq("source", (run({ action = "source", target = "sonos", room = "living room" })), "Sonos in Living Room.")
T.eq("audio source", sent, { { ROOM_LIVING, "SELECT_AUDIO_DEVICE", { deviceid = 31 } } })
run({ action = "source", target = "Apple TV" })
T.eq("video source in the default room", sent, { { ROOM_LIVING, "SELECT_VIDEO_DEVICE", { deviceid = 32 } } })
T.eq(
  "source not in the room",
  (run({ action = "source", target = "Sonos", room = "Bedroom" })),
  "I don't know a source in Bedroom called Sonos."
)
T.eq("volume", (run({ action = "volume_set", value = "30" })), "Living Room volume 30.")
variables[ROOM_LIVING .. ":1011"] = "35"
T.eq("quieter from the room's volume", (run({ action = "volume_down" })), "Living Room volume 25.")
T.eq("set", sent, { { ROOM_LIVING, "SET_VOLUME_LEVEL", { LEVEL = 25 } } })
variables = {}
run({ action = "volume_up", value = "6" })
T.eq("volume unknown: pulses", #sent, 3)
T.eq("pulse up", sent[1][2], "PULSE_VOL_UP")
run({ action = "pause", room = "Living Room" })
T.eq("pause", sent, { { ROOM_LIVING, "PAUSE", {} } })
run({ action = "room_off" })
T.eq("room off", sent, { { ROOM_LIVING, "ROOM_OFF", {} } })
T.eq("no room known", (run({ action = "play" }, { defaultRoomId = 999 })), "Which room?")
T.eq("unknown room", (run({ action = "play", room = "Garage" })), "I don't know a room called Garage.")

T.section("Commands: not understood, test mode")
local r, s, ok = run({ action = "unknown", heard = "order a pizza" })
T.eq("unknown", { r, #s, ok }, { "Sorry, I can't do that. I heard: order a pizza", 0, false })
T.eq("made-up action", (select(3, run({ action = "fly" }))), false)
local dryReply, dry = run({ action = "light_on", target = "Dining" }, { dryRun = true })
T.eq("test mode describes", dry[1].command, "ON")
T.eq("test mode sends nothing", sent, {})
T.eq("test mode reply", dryReply, "Dining on.")

-----------------------------------------------------------------------
T.section("Driver: start-up and HTTP")
local realGetDriverConfigInfo = C4.GetDriverConfigInfo
C4.GetDriverConfigInfo = function(c4, section)
  if section == "minimum_os_version" then
    return "3.3.0"
  end
  return realGetDriverConfigInfo(c4, section)
end
local propertyWrites = {}
C4.UpdateProperty = function(_, name, value)
  propertyWrites[name] = value
end
local xml = assert(io.open("drivers/cp_siri_shortcuts/driver.xml")):read("*a")
for block in xml:gmatch("<property>(.-)</property>") do
  Properties[block:match("<name>(.-)</name>")] = block:match("<default>(.-)</default>") or ""
end
Properties["Log Level"] = "2 - Warning"
ShimSetDevices({
  [ROOM_LIVING] = { deviceName = "Living Room", driverFileName = "roomdevice.c4i" },
  [11] = { deviceName = "Dining", driverFileName = "light_v2.c4i", roomId = "100", roomName = "Living Room" },
  [SCENES] = { deviceName = "Advanced Lighting", driverFileName = "control4_agent_adv_lighting.c4i" },
})
C4.GetControllerNetworkAddress = function()
  return "192.168.1.10"
end
C4.RoomGetId = function()
  return ROOM_LIVING
end
local fired = {}
C4.FireEvent = function(_, name)
  fired[#fired + 1] = name
end
local deviceCommands = {}
C4.SendToDevice = function(_, device, command, params)
  deviceCommands[#deviceCommands + 1] = { device, command, params }
end

-- A TCP server and client with the callbacks C4:CreateTCPServer offers.
local server
local function fakeClient()
  local c = { written = {}, closed = false, handlers = {} }
  for _, name in ipairs({ "OnRead", "OnWrite", "OnDisconnect", "OnError" }) do
    c[name] = function(self, fn)
      self.handlers[name] = fn
      return self
    end
  end
  c.ReadUpTo = function() end
  c.Write = function(self, data)
    self.written[#self.written + 1] = data
    return true
  end
  c.Close = function(self)
    self.closed = true
  end
  return c
end
C4.CreateTCPServer = function()
  server = { handlers = {} }
  for _, name in ipairs({ "OnListen", "OnError", "OnAccept" }) do
    server[name] = function(self, fn)
      self.handlers[name] = fn
      return self
    end
  end
  server.Option = function() end
  server.Close = function() end
  server.Listen = function(self, _, port)
    self.port = port
    self.handlers.OnListen(self, { ip = "*", port = port })
    return true
  end
  return server
end
local function request(raw)
  local client = fakeClient()
  server.handlers.OnAccept(server, client)
  client.handlers.OnRead(client, raw)
  if client.written[1] ~= nil then
    client.handlers.OnWrite(client)
  end
  return client.written[1] or "", client
end

local started, startErr = T.capture(function()
  dofile("drivers/cp_siri_shortcuts/driver.lua")
  OnDriverInit()
  OnDriverLateInit()
end)
T.check("the driver starts", started, startErr)
T.eq("listens on the default port", server.port, 8765)
T.eq("status", propertyWrites["Driver Status"], "Listening on port 8765")
T.eq("context URL", propertyWrites["Context URL"], "http://192.168.1.10:8765/context")
T.eq("names read", propertyWrites["Known Names"], "1 rooms, 1 lights, 2 scenes, 0 scenarios, 0 sources")

local ctx, conn = request("GET /context HTTP/1.1\r\nHost: x\r\n\r\n")
T.contains("context answered", ctx, "HTTP/1.1 200 OK")
T.contains("context names the light", ctx, "- Dining (room: Living Room)")
T.contains("default room is the driver's room", ctx, "the home uses Living Room")
T.truthy("closed after writing", conn.closed)

local body = '{"room":"","action":"light_level","target":"Dining","value":"25","heard":"dining to 25"}'
local ex = request("POST /execute HTTP/1.1\r\nContent-Length: " .. #body .. "\r\n\r\n" .. body)
T.contains("spoken reply", ex, "\r\n\r\nDining 25 percent.")
T.eq("light set", deviceCommands[1][2], "SET_BRIGHTNESS_TARGET")
T.eq("last command shown", propertyWrites["Last Reply"], "Dining 25 percent.")
T.eq("event", fired[#fired], "Command Received")

Properties["Execute Commands"] = "No"
deviceCommands = {}
ex = request("GET /execute?action=scene&target=evening HTTP/1.1\r\n\r\n")
T.contains("test mode answer", ex, "Test mode. Evening.")
T.eq("test mode sends nothing", #deviceCommands, 0)
T.contains("but says what it would send", propertyWrites["Last Sent"], "ACTIVATE_SCENE -> 900 SCENE_ID=0")

request("POST /execute HTTP/1.1\r\nContent-Length: 5\r\n\r\nhello")
T.eq("unreadable command: event", fired[#fired], "Command Not Understood")
T.contains("unknown path", (request("GET /nope HTTP/1.1\r\n\r\n")), "404 Not Found")
T.contains("names as JSON", (request("GET /names HTTP/1.1\r\n\r\n")), '"name":"Dining"')

ShimResetDevices()
T.finish()
