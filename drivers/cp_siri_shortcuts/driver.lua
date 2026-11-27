--- Siri Shortcuts Driver
--- Voice control of the Control4 home from iPhone, iPad and Apple Watch through
--- one Apple Shortcut, with no extra hardware and no cloud service of our own.
---
--- The controller serves two plain HTTP endpoints on the LAN (Port property):
---   GET  /context  the instructions for Apple's model with every room, light,
---                  scene, scenario and source in the project, read live
---   POST /execute  the dictionary the model made ({ room, action, target,
---                  value, heard }) as JSON; the reply is a sentence to speak
--- The shortcut: Get Contents of URL (/context) -> Dictate Text -> Text
--- (context + "Request: " + dictation) -> Use Model (Output: Dictionary) ->
--- Get Contents of URL (POST /execute, body: the dictionary) -> Speak Text.
---
--- No authentication: anything on the LAN can send commands (by design).
---
--- Control Pro - https://control-pro.co.uk - c4@control-pro.co.uk

DRIVER_GITHUB_REPO = "krishy2/control4-siri-shortcuts"
DRIVER_FILENAMES = { "cp_siri_shortcuts.c4z" }

require("lib.utils")
require("drivers-common-public.global.handlers")
require("drivers-common-public.global.lib")
require("drivers-common-public.global.timer")
JSON = JSON or require("JSON")

local log = require("lib.logging")
local persist = require("lib.persist")
local githubUpdater = require("lib.github-updater")
local Http = require("voice.http")
local Names = require("voice.names")
local Catalog = require("voice.catalog")
local Context = require("voice.context")
local Commands = require("voice.commands")

-- The names are read again when the context is asked for and they are older than this.
local CATALOG_MAX_AGE = 30 * ONE_SECOND
-- A connection that sends no complete request in this time is closed.
local CONNECTION_TIMEOUT = 15 * ONE_SECOND
local READ_SIZE = 16384
-- How often Automatic Updates looks for a new release.
local UPDATE_INTERVAL = 30 * ONE_MINUTE
-- Remembers a sent update until the restarted driver confirms its version.
local UPDATE_PERSIST_KEY = "PendingUpdate"

-- Runtime state
local gServer = nil
local gCatalog = nil
local gCatalogAt = nil
local gConnectionCount = 0

-----------------------------------------------------------------------
-- Catalog and context
-----------------------------------------------------------------------

--- Default room for media commands that name none: the property, else the driver's own room.
--- @return integer|nil
local function defaultRoomId()
  local chosen = tointeger(Properties["Default Room"])
  if chosen ~= nil and chosen > 0 then
    return chosen
  end
  local ok, own = pcall(C4.RoomGetId, C4)
  return ok and tointeger(own) or nil
end

--- Read the project's names (again when older than CATALOG_MAX_AGE, or always with force).
--- @param force boolean|nil
--- @return CatalogData
local function catalog(force)
  local now = C4:GetTime()
  if force or gCatalog == nil or gCatalogAt == nil or now - gCatalogAt > CATALOG_MAX_AGE then
    gCatalog = Catalog.read({
      hidden = Names.hider(Properties["Hidden Names"]),
      ownId = C4:GetDeviceID(),
    })
    gCatalogAt = now
    local summary = Catalog.summary(gCatalog)
    UpdateProperty("Known Names", summary)
    log:debug("Names read: %s", summary)
    for _, note in ipairs(gCatalog.notes) do
      log:debug("Names: %s", note)
    end
  end
  return gCatalog
end

--- The default room's name, for the context.
--- @param data CatalogData
--- @return string|nil
local function defaultRoomName(data)
  local id = defaultRoomId()
  for _, room in ipairs(data.rooms) do
    if room.id == id then
      return room.name
    end
  end
  return nil
end

--- @return string
local function contextText()
  local data = catalog(false)
  return Context.build(data, { defaultRoom = defaultRoomName(data), extra = Properties["Extra Instructions"] })
end

-----------------------------------------------------------------------
-- Requests
-----------------------------------------------------------------------

local function describeSent(sent)
  local parts = {}
  for _, s in ipairs(sent) do
    local params = {}
    for k, v in pairs(s.params) do
      params[#params + 1] = tostring(k) .. "=" .. tostring(v)
    end
    table.sort(params)
    parts[#parts + 1] = string.format("%s -> %d %s", s.command, s.device, table.concat(params, " "))
  end
  return table.concat(parts, "; ")
end

--- Carry out a posted command.
--- @param request HttpRequest
--- @return integer status
--- @return string reply
local function execute(request)
  local cmd = Commands.parse(request.body, request.query, function(s)
    return JSON:decode(s)
  end)
  if cmd == nil then
    local headers = request.headers or {}
    local what = string.format(
      "%d bytes, %s%s",
      #(request.body or ""),
      tostring(headers["content-type"] or "no content type"),
      headers["transfer-encoding"] and (", " .. headers["transfer-encoding"]) or ""
    )
    log:warn("Execute: no command in %s: %s", what, string.sub(request.body or "", 1, 500))
    UpdateProperty("Last Command", "(unreadable, " .. what .. ") " .. string.sub(request.body or "", 1, 200))
    UpdateProperty("Last Reply", "Sorry, the command did not arrive.")
    C4:FireEvent("Command Not Understood")
    return 400, "Sorry, the command did not arrive."
  end
  local summary = string.format(
    "room=%s action=%s target=%s value=%s heard=%s",
    cmd.room,
    cmd.action,
    cmd.target,
    cmd.value,
    cmd.heard
  )
  local dryRun = Properties["Execute Commands"] == "No"
  local reply, sent, understood = Commands.run(cmd, catalog(false), {
    send = function(device, command, params)
      C4:SendToDevice(device, command, params)
    end,
    variable = function(device, variableId)
      local ok, value = pcall(C4.GetDeviceVariable, C4, device, variableId)
      return ok and value or nil
    end,
    variables = Catalog.variables,
    scale = (function()
      local ok, scale = pcall(C4.GetTemperatureScale, C4)
      return ok and scale or "CELSIUS"
    end)(),
    defaultRoomId = defaultRoomId(),
    volumeStep = tonumber(Properties["Volume Step"]) or 10,
    dryRun = dryRun,
  })
  if dryRun then
    reply = "Test mode. " .. reply
  end
  log:info("Execute: %s -> %s [%s]", summary, reply, describeSent(sent))
  UpdateProperty("Last Command", summary)
  UpdateProperty("Last Reply", reply)
  UpdateProperty("Last Sent", describeSent(sent))
  C4:FireEvent(understood and "Command Received" or "Command Not Understood")
  return 200, reply
end

local HELP = table.concat({
  "Control4 Siri Shortcuts driver.",
  "GET  /context  instructions and names for the shortcut's Use Model action",
  "POST /execute  the model's dictionary as JSON; answers with a sentence to speak",
  "GET  /names    the names this driver knows, as JSON",
}, "\n")

--- Answer one request.
--- @param request HttpRequest
--- @return string response
local function handle(request)
  local path = request.path:gsub("/+$", "")
  local headers = request.headers or {}
  log:debug(
    "HTTP %s %s (%d bytes, %s)",
    request.method,
    request.path,
    #(request.body or ""),
    tostring(headers["content-type"] or "no content type")
  )
  log:trace("HTTP body: %s", request.body)
  if path == "/context" and request.method == "GET" then
    UpdateProperty("Last Request", "Context " .. os.date("%Y-%m-%d %H:%M:%S"))
    return Http.response(200, contextText())
  elseif path == "/execute" and (request.method == "POST" or request.method == "GET") then
    return Http.response(execute(request))
  elseif path == "/names" and request.method == "GET" then
    local data = catalog(false)
    return Http.response(
      200,
      JSON:encode({
        rooms = data.rooms,
        lights = data.lights,
        scenes = data.scenes,
        scenarios = data.scenarios,
        sources = data.sources,
        notes = data.notes,
      }),
      "application/json"
    )
  elseif path == "" and request.method == "GET" then
    return Http.response(200, HELP)
  elseif path == "/context" or path == "/execute" or path == "/names" then
    return Http.response(405, "Method not allowed")
  end
  return Http.response(404, "Not found. " .. HELP)
end

-----------------------------------------------------------------------
-- HTTP server
-----------------------------------------------------------------------

local function accept(client)
  gConnectionCount = gConnectionCount + 1
  local timerId = "Connection" .. gConnectionCount
  local reader = Http.reader()
  local done = false
  local replied = false
  local function close()
    if not done then
      done = true
      CancelTimer(timerId)
      pcall(client.Close, client, true)
    end
  end
  local function reply(response)
    if done or replied then
      return
    end
    replied = true
    -- Closed once written (OnWrite), or by the timeout at the latest.
    if client:Write(response) == nil then
      close()
    end
  end
  SetTimer(timerId, CONNECTION_TIMEOUT, close)
  client
    :OnRead(function(cli, data)
      local ok, err = xpcall(function()
        local request, status = reader:feed(data)
        if status ~= nil then
          reply(Http.response(status, "Bad request"))
        elseif request ~= nil then
          reply(handle(request))
        else
          local continue = reader:continueReply()
          if continue ~= nil then
            cli:Write(continue)
          end
          cli:ReadUpTo(READ_SIZE)
        end
      end, debug.traceback)
      if not ok then
        log:error("HTTP request failed: %s", err)
        reply(Http.response(500, "Sorry, something went wrong in the driver."))
      end
    end)
    :OnWrite(function()
      -- Only the final reply closes; a "100 Continue" does not.
      if replied then
        close()
      end
    end)
    :OnDisconnect(function()
      done = true
      CancelTimer(timerId)
    end)
    :OnError(function(_, code, msg)
      log:debug("HTTP connection error %s (%s)", tostring(code), tostring(msg))
      close()
    end)
  client:ReadUpTo(READ_SIZE)
end

local function controllerAddress()
  local ok, ip = pcall(C4.GetControllerNetworkAddress, C4)
  if ok and not IsEmpty(ip) then
    return tostring(ip)
  end
  return "<controller IP>"
end

local function updateUrls(port)
  local base = string.format("http://%s:%d", controllerAddress(), port)
  UpdateProperty("Context URL", base .. "/context")
  UpdateProperty("Execute URL", base .. "/execute")
end

local function stopServer()
  if gServer ~= nil then
    local srv = gServer
    gServer = nil
    pcall(srv.Close, srv)
  end
end

local function startServer()
  stopServer()
  local port = tointeger(Properties["Port"]) or 8765
  updateUrls(port)
  local srv = C4:CreateTCPServer()
  if srv == nil then
    UpdateProperty("Driver Status", "Error: could not create the server")
    return
  end
  gServer = srv
  pcall(srv.Option, srv, "reuseaddr", true)
  srv
    :OnListen(function()
      if gServer == srv then
        UpdateProperty("Driver Status", string.format("Listening on port %d", port))
        log:info("Listening on port %d", port)
      end
    end)
    :OnError(function(_, code, msg)
      if gServer == srv then
        gServer = nil
        UpdateProperty("Driver Status", string.format("Error %s: %s (port %d)", tostring(code), tostring(msg), port))
        log:error("Server error %s: %s (port %d)", tostring(code), tostring(msg), port)
      end
    end)
    :OnAccept(function(_, client)
      if gServer ~= srv then
        pcall(client.Close, client, false)
        return
      end
      local ok, err = xpcall(function()
        accept(client)
      end, debug.traceback)
      if not ok then
        log:error("Accepting a connection failed: %s", err)
        pcall(client.Close, client, false)
      end
    end)
  if srv:Listen("*", port) == nil then
    gServer = nil
    UpdateProperty("Driver Status", string.format("Error: listening on port %d was refused", port))
  end
end

-----------------------------------------------------------------------
-- Driver lifecycle
-----------------------------------------------------------------------

function OnDriverInit()
  C4:AllowExecute(true)
  gInitialized = false
  log:setLogName(C4:GetDeviceData(C4:GetDeviceID(), "name"))
  log:setLogLevel(Properties["Log Level"])
  log:setLogMode(Properties["Log Mode"])
  log:trace("OnDriverInit()")
end

function OnDriverLateInit()
  log:trace("OnDriverLateInit()")
  if not CheckMinimumVersion("Driver Status") then
    return
  end
  UpdateProperty("Driver Status", "Initializing")
  for p, _ in pairs(Properties) do
    local status, err = pcall(OnPropertyChanged, p)
    if not status and err ~= nil then
      log:error(err)
    end
  end
  gInitialized = true
  -- The server must not be created during OnDriverInit.
  startServer()
  catalog(true)

  -- Automatic Updates: one instance checks (the lowest device ID), every 30 minutes.
  SetTimer("UpdateCheck", UPDATE_INTERVAL, function()
    if IsUpdateLeader() and Properties["Automatic Updates"] == "On" then
      log:info("Checking for a driver update")
      UpdateDrivers()
    end
  end, true)
  -- After an update: say whether the new version is running.
  if persist:get(UPDATE_PERSIST_KEY, nil) ~= nil then
    SetTimer("UpdateVerify", 30 * ONE_SECOND, VerifyDriverUpdate)
  end
end

function OnDriverDestroyed()
  stopServer()
end

-----------------------------------------------------------------------
-- Property change handlers
-----------------------------------------------------------------------

function OPC.Driver_Version(propertyValue)
  C4:UpdateProperty("Driver Version", C4:GetDriverConfigInfo("version"))
end

function OPC.Log_Mode(propertyValue)
  log:setLogMode(propertyValue)
  CancelTimer("LogMode")
  if not log:isEnabled() then
    return
  end
  log:warn("Log mode '%s' will expire in 3 hours", propertyValue)
  SetTimer("LogMode", 3 * ONE_HOUR, function()
    log:warn("Setting log mode to 'Off' (timer expired)")
    UpdateProperty("Log Mode", "Off", true)
  end)
end

function OPC.Log_Level(propertyValue)
  log:setLogLevel(propertyValue)
  local debug = log:getLogLevel() >= 6 and log:isPrintEnabled()
  DEBUGPRINT, DEBUG_TIMER, DEBUG_RFN, DEBUG_URL = debug, debug, debug, debug
end

function OPC.Port(propertyValue)
  if gInitialized then
    startServer()
  end
end

--- Settings that change the names or the context: read the names again.
local function namesChanged()
  if gInitialized then
    catalog(true)
  end
end

OPC.Hidden_Names = namesChanged
OPC.Default_Room = namesChanged

-----------------------------------------------------------------------
-- Actions
-----------------------------------------------------------------------

function EC.Refresh_Names(tParams)
  local data = catalog(true)
  log:print("Names read: %s", Catalog.summary(data))
  for _, note in ipairs(data.notes) do
    log:print("Note: %s", note)
  end
end

function EC.Print_Context(tParams)
  log:print("==== Context sent to the shortcut ====\n%s\n==== end ====", contextText())
end

function EC.Restart_Server(tParams)
  startServer()
end

function EC.UpdateDrivers(tParams)
  log:trace("EC.UpdateDrivers()")
  UpdateDrivers(true, true)
end

-----------------------------------------------------------------------
-- Updates from GitHub releases
-----------------------------------------------------------------------

--- Only one instance checks for updates: the one with the lowest device ID.
--- @return boolean
function IsUpdateLeader()
  local lowest = nil
  for k, v in pairs(C4:GetDevicesByC4iName(DRIVER_FILENAMES[1]) or {}) do
    local id = tonumber(type(v) == "number" and v or k)
    if id ~= nil and (lowest == nil or id < lowest) then
      lowest = id
    end
  end
  return lowest == nil or lowest == C4:GetDeviceID()
end

--- Installed drivers of this repository and their versions.
--- @return string[] filenames, table<string, string> versions
local function installedDrivers()
  local files, versions = {}, {}
  for _, filename in ipairs(DRIVER_FILENAMES) do
    if not IsEmpty(C4:GetDevicesByC4iName(filename) or {}) then
      files[#files + 1] = filename
      local ok, v = pcall(GetDriverVersion, filename)
      versions[filename] = ok and v or nil
    end
  end
  return files, versions
end

--- After an update was sent: check that the driver now runs the release's version.
function VerifyDriverUpdate()
  local pending = persist:get(UPDATE_PERSIST_KEY, nil)
  if type(pending) ~= "table" then
    return
  end
  persist:delete(UPDATE_PERSIST_KEY)
  CancelTimer("UpdateVerify")
  local _, versions = installedDrivers()
  local failed = {}
  for _, filename in ipairs(pending.drivers or {}) do
    if versions[filename] ~= pending.version then
      failed[#failed + 1] = string.format("%s is on %s", filename, tostring(versions[filename] or "unknown"))
    end
  end
  if IsEmpty(failed) then
    log:print("Update to %s succeeded: version %s", pending.tag, pending.version)
  else
    log:print(
      "Update to %s FAILED: %s (expected %s). Run Update Drivers again or install the .c4z from GitHub.",
      pending.tag,
      table.concat(failed, ", "),
      pending.version
    )
  end
end

local function errorText(err)
  if type(err) == "table" then
    local parts = {}
    for _, e in pairs(err) do
      parts[#parts + 1] = tostring(e)
    end
    return table.concat(parts, "; ")
  end
  return tostring(err)
end

--- Update the driver from the GitHub repository's latest release.
--- @param forceUpdate? boolean Reinstall even if up to date.
--- @param manual? boolean Asked for by the user: every step goes to the log.
function UpdateDrivers(forceUpdate, manual)
  log:trace("UpdateDrivers(%s, %s)", forceUpdate, manual)
  local say = function(...)
    if manual then
      log:print(...)
    else
      log:info(...)
    end
  end
  local files, versions = installedDrivers()
  local current = {}
  for _, filename in ipairs(files) do
    current[#current + 1] = string.format("%s %s", filename, tostring(versions[filename] or "?"))
  end
  say(
    "Update started: checking %s for the latest release (installed: %s)",
    DRIVER_GITHUB_REPO,
    table.concat(current, ", ")
  )
  githubUpdater
    :updateAll(DRIVER_GITHUB_REPO, DRIVER_FILENAMES, Properties["Update Channel"] == "Prerelease", forceUpdate)
    :next(function(updatedDrivers)
      local release = githubUpdater.lastRelease or {}
      local tag = tostring(release.tag_name or "?")
      if IsEmpty(updatedDrivers) then
        say("Update finished: already on the latest release %s, nothing to install", tag)
        return
      end
      local version = tag:gsub("^[vV]", "")
      persist:set(UPDATE_PERSIST_KEY, { tag = tag, version = version, drivers = updatedDrivers })
      log:print("Update: %s downloaded and sent to the controller; the driver restarts now", tag)
    end, function(error)
      local text = errorText(error)
      if manual then
        log:print("Update FAILED: %s", text)
      end
      log:error("An error occurred updating the driver: %s", text)
    end)
end
