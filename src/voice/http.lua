--- @module "voice.http"
--- Minimal HTTP/1.1 for the Siri Shortcuts driver: collects one request per
--- connection from the bytes a TCP server delivers (headers can arrive split
--- across reads, the body follows Content-Length) and builds the reply.
---
--- Pure Lua, no Control4 calls, so it is tested on its own.

local Http = {}

--- Requests larger than this are refused (headers + body).
Http.MAX_REQUEST = 64 * 1024

local REASONS = {
  [200] = "OK",
  [400] = "Bad Request",
  [404] = "Not Found",
  [405] = "Method Not Allowed",
  [413] = "Payload Too Large",
  [500] = "Internal Server Error",
}

--- Decode %XX escapes and + in a query string value.
--- @param s string
--- @return string
function Http.urlDecode(s)
  s = tostring(s or ""):gsub("+", " ")
  return (s:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end))
end

--- Split `a=1&b=two` into a table.
--- @param query string|nil
--- @return table<string, string>
function Http.parseQuery(query)
  local out = {}
  for pair in tostring(query or ""):gmatch("[^&]+") do
    local key, value = pair:match("^([^=]*)=?(.*)$")
    if key ~= nil and key ~= "" then
      out[Http.urlDecode(key)] = Http.urlDecode(value)
    end
  end
  return out
end

--- @class HttpRequest
--- @field method string
--- @field path string
--- @field query table<string, string>
--- @field headers table<string, string> lower-case names
--- @field body string

--- A request in progress on one connection.
--- @class HttpReader
local Reader = {}
Reader.__index = Reader

--- @return HttpReader
function Http.reader()
  return setmetatable({ buffer = "" }, Reader)
end

--- Add received bytes.
--- @param data string
--- @return HttpRequest|nil request the complete request, once it is
--- @return integer|nil errorStatus an HTTP status to answer with when the request is broken
function Reader:feed(data)
  self.buffer = self.buffer .. tostring(data or "")
  if #self.buffer > Http.MAX_REQUEST then
    return nil, 413
  end
  if self.head == nil then
    local headerEnd = self.buffer:find("\r\n\r\n", 1, true)
    local sepLength = 4
    if headerEnd == nil then
      headerEnd = self.buffer:find("\n\n", 1, true)
      sepLength = 2
    end
    if headerEnd == nil then
      return nil, nil
    end
    local headText = self.buffer:sub(1, headerEnd - 1)
    self.buffer = self.buffer:sub(headerEnd + sepLength)
    local lines = {}
    for line in (headText .. "\n"):gmatch("([^\n]*)\n") do
      lines[#lines + 1] = (line:gsub("\r$", ""))
    end
    local method, target = (lines[1] or ""):match("^(%u+)%s+(%S+)")
    if method == nil then
      return nil, 400
    end
    local headers = {}
    for i = 2, #lines do
      local name, value = lines[i]:match("^([^:]+):%s*(.-)%s*$")
      if name ~= nil then
        headers[name:lower()] = value
      end
    end
    local path, query = target:match("^([^?]*)%??(.*)$")
    self.head = {
      method = method,
      path = path ~= "" and path or "/",
      query = Http.parseQuery(query),
      headers = headers,
    }
    self.chunked = tostring(headers["transfer-encoding"] or ""):lower():find("chunked", 1, true) ~= nil
    self.length = tonumber(headers["content-length"]) or 0
    if self.length < 0 then
      return nil, 400
    end
    -- A client that asks first gets "100 Continue" (see Reader:continueReply).
    self.expectContinue = tostring(headers["expect"] or ""):lower() == "100-continue"
  end
  local request = self.head
  if self.chunked then
    local body = Http.dechunk(self.buffer)
    if body == nil then
      return nil, nil
    end
    request.body = body
    return request, nil
  end
  if #self.buffer < self.length then
    return nil, nil
  end
  request.body = self.buffer:sub(1, self.length)
  return request, nil
end

--- The interim reply for a client that sent "Expect: 100-continue", once.
--- @return string|nil
function Reader:continueReply()
  if self.expectContinue and not self.continued then
    self.continued = true
    return "HTTP/1.1 100 Continue\r\n\r\n"
  end
  return nil
end

--- Decode a chunked body (Transfer-Encoding: chunked).
--- @param data string everything after the headers
--- @return string|nil body nil until the last chunk has arrived
function Http.dechunk(data)
  local parts, pos = {}, 1
  while true do
    local lineEnd = data:find("\r\n", pos, true)
    if lineEnd == nil then
      return nil
    end
    local size = tonumber((data:sub(pos, lineEnd - 1):match("^%s*(%x+)")), 16)
    if size == nil then
      return nil
    end
    if size == 0 then
      return table.concat(parts)
    end
    local chunkStart = lineEnd + 2
    if #data < chunkStart + size + 1 then
      return nil
    end
    parts[#parts + 1] = data:sub(chunkStart, chunkStart + size - 1)
    pos = chunkStart + size + 2
  end
end

--- Build a complete HTTP response that closes the connection.
--- @param status integer
--- @param body string|nil
--- @param contentType string|nil default text/plain
--- @return string
function Http.response(status, body, contentType)
  body = body or ""
  return table.concat({
    string.format("HTTP/1.1 %d %s", status, REASONS[status] or "Unknown"),
    "Content-Type: " .. (contentType or "text/plain; charset=utf-8"),
    "Content-Length: " .. #body,
    "Connection: close",
    "Cache-Control: no-store",
    "",
    body,
  }, "\r\n")
end

return Http
