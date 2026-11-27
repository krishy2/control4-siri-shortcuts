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
    self.length = tonumber(headers["content-length"]) or 0
    if self.length < 0 then
      return nil, 400
    end
  end
  if #self.buffer < self.length then
    return nil, nil
  end
  local request = self.head
  request.body = self.buffer:sub(1, self.length)
  return request, nil
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
