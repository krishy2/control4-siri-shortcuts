--- @module "voice.rtf"
--- Plain text from RTF. Shortcuts sends the Use Model response as a rich text
--- file when it is posted as the request body (`{\rtf1\ansi\ansicpg1252\cocoartf...`),
--- with the dictionary's JSON inside as escaped text (`\{"room":...\}`).
---
--- Handles what Cocoa writes: header groups (font, color tables) skipped,
--- `\{ \} \\` escapes, `\'hh` (Windows-1252), `\uN` with `\ucN`, `\par` and
--- `\line` as new lines. Pure Lua.

local Rtf = {}

-- Groups that hold no text.
local SKIP_GROUPS = {
  fonttbl = true,
  colortbl = true,
  expandedcolortbl = true,
  stylesheet = true,
  info = true,
  listtable = true,
  listoverridetable = true,
  pict = true,
}

-- Windows-1252 bytes 0x80-0x9F that are not Latin-1.
local CP1252 = {
  [0x80] = 0x20AC,
  [0x82] = 0x201A,
  [0x84] = 0x201E,
  [0x85] = 0x2026,
  [0x91] = 0x2018,
  [0x92] = 0x2019,
  [0x93] = 0x201C,
  [0x94] = 0x201D,
  [0x96] = 0x2013,
  [0x97] = 0x2014,
}

--- UTF-8 for a code point.
--- @param cp integer
--- @return string
local function utf8(cp)
  if cp < 0x80 then
    return string.char(cp)
  elseif cp < 0x800 then
    return string.char(0xC0 + math.floor(cp / 0x40), 0x80 + cp % 0x40)
  elseif cp < 0x10000 then
    return string.char(0xE0 + math.floor(cp / 0x1000), 0x80 + math.floor(cp / 0x40) % 0x40, 0x80 + cp % 0x40)
  end
  return string.char(
    0xF0 + math.floor(cp / 0x40000),
    0x80 + math.floor(cp / 0x1000) % 0x40,
    0x80 + math.floor(cp / 0x40) % 0x40,
    0x80 + cp % 0x40
  )
end

--- Is this RTF?
--- @param s string|nil
--- @return boolean
function Rtf.is(s)
  return type(s) == "string" and s:find("^%s*{\\rtf") ~= nil
end

--- The text of an RTF document.
--- @param s string
--- @return string
function Rtf.toText(s)
  local out = {}
  local pos, len = 1, #s
  local depth = 0
  local skipBelow = nil -- skipping while depth >= this
  local ucSkip = 1 -- characters to drop after \uN
  local pendingSkip = 0
  local groupStart = false -- just after "{": the first control word may start a skipped group

  local function emit(text)
    if skipBelow ~= nil then
      return
    end
    if pendingSkip > 0 then
      -- The fallback characters after \uN
      local n = math.min(pendingSkip, #text)
      pendingSkip = pendingSkip - n
      text = text:sub(n + 1)
    end
    out[#out + 1] = text
  end

  while pos <= len do
    local c = s:sub(pos, pos)
    if c == "{" then
      depth = depth + 1
      groupStart = true
      pos = pos + 1
    elseif c == "}" then
      if skipBelow ~= nil and depth <= skipBelow then
        skipBelow = nil
      end
      depth = depth - 1
      groupStart = false
      pos = pos + 1
    elseif c == "\\" then
      local nextChar = s:sub(pos + 1, pos + 1)
      if nextChar == "{" or nextChar == "}" or nextChar == "\\" then
        emit(nextChar)
        pos = pos + 2
      elseif nextChar == "'" then
        local byte = tonumber(s:sub(pos + 2, pos + 3), 16)
        if byte ~= nil then
          emit(utf8(CP1252[byte] or byte))
        end
        pos = pos + 4
      elseif nextChar == "*" then
        -- {\* ...}: an ignorable destination
        if groupStart and skipBelow == nil then
          skipBelow = depth
        end
        pos = pos + 2
      elseif nextChar:match("%a") then
        local word, num, after = s:match("^(%a+)(%-?%d*) ?()", pos + 1)
        num = tonumber(num)
        if groupStart and SKIP_GROUPS[word] and skipBelow == nil then
          skipBelow = depth
        elseif word == "par" or word == "line" then
          emit("\n")
        elseif word == "tab" then
          emit("\t")
        elseif word == "uc" and num ~= nil then
          ucSkip = num
        elseif word == "u" and num ~= nil then
          if num < 0 then
            num = num + 65536
          end
          emit(utf8(num))
          pendingSkip = ucSkip
        end
        pos = after
      else
        -- "\<newline>" is a paragraph; anything else is dropped
        if nextChar == "\n" or nextChar == "\r" then
          emit("\n")
        end
        pos = pos + 2
      end
      groupStart = false
    elseif c == "\n" or c == "\r" then
      pos = pos + 1
    else
      local text = s:match("^[^{}\\\r\n]+", pos)
      emit(text)
      pos = pos + #text
      groupStart = false
    end
  end
  return table.concat(out)
end

return Rtf
