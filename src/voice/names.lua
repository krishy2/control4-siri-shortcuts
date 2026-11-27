--- @module "voice.names"
--- Name matching for the Siri Shortcuts driver. The AI is asked to use the exact
--- names the driver gave it, but dictation and the model both make small
--- mistakes ("dinning", "Megjottunk", "living room light" for "Living Room
--- Ceiling"), so names are compared loosely: case and accents are ignored, then
--- whole names, contained names, shared words and spelling distance are tried.
---
--- Pure Lua, no Control4 calls.

local Names = {}

-- UTF-8 accented letters folded to ASCII (Hungarian first, then common Latin).
local FOLD = {
  ["á"] = "a",
  ["é"] = "e",
  ["í"] = "i",
  ["ó"] = "o",
  ["ö"] = "o",
  ["ő"] = "o",
  ["ú"] = "u",
  ["ü"] = "u",
  ["ű"] = "u",
  ["Á"] = "a",
  ["É"] = "e",
  ["Í"] = "i",
  ["Ó"] = "o",
  ["Ö"] = "o",
  ["Ő"] = "o",
  ["Ú"] = "u",
  ["Ü"] = "u",
  ["Ű"] = "u",
  ["à"] = "a",
  ["â"] = "a",
  ["ä"] = "a",
  ["ã"] = "a",
  ["å"] = "a",
  ["è"] = "e",
  ["ê"] = "e",
  ["ë"] = "e",
  ["ì"] = "i",
  ["î"] = "i",
  ["ï"] = "i",
  ["ò"] = "o",
  ["ô"] = "o",
  ["õ"] = "o",
  ["ù"] = "u",
  ["û"] = "u",
  ["ñ"] = "n",
  ["ç"] = "c",
  ["ß"] = "ss",
  ["ø"] = "o",
  ["æ"] = "ae",
  ["œ"] = "oe",
}

--- Lower case, accents folded, everything but letters and digits turned into
--- single spaces.
--- @param s string|nil
--- @return string
function Names.normalize(s)
  s = tostring(s or "")
  s = s:gsub("[\195-\197][\128-\191]", function(ch)
    return FOLD[ch] or ch
  end)
  s = s:lower():gsub("[^%w]+", " ")
  return (s:gsub("^ +", ""):gsub(" +$", ""))
end

--- @param s string normalized
--- @return string[]
local function words(s)
  local out = {}
  for w in s:gmatch("%S+") do
    out[#out + 1] = w
  end
  return out
end

--- Levenshtein distance (names are short).
--- @param a string
--- @param b string
--- @return integer
function Names.distance(a, b)
  local la, lb = #a, #b
  if la == 0 then
    return lb
  end
  if lb == 0 then
    return la
  end
  local prev = {}
  for j = 0, lb do
    prev[j] = j
  end
  for i = 1, la do
    local cur = { [0] = i }
    local ca = a:byte(i)
    for j = 1, lb do
      local cost = ca == b:byte(j) and 0 or 1
      cur[j] = math.min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + cost)
    end
    prev = cur
  end
  return prev[lb]
end

--- How well a spoken name fits a known one, 0..100.
--- @param spoken string normalized
--- @param known string normalized
--- @return number
function Names.score(spoken, known)
  if spoken == "" or known == "" then
    return 0
  end
  if spoken == known then
    return 100
  end
  local padSpoken, padKnown = " " .. spoken .. " ", " " .. known .. " "
  if padKnown:find(padSpoken, 1, true) or padSpoken:find(padKnown, 1, true) then
    return 80
  end
  local best = 0
  -- Shared words
  local a, b = words(spoken), words(known)
  local inB = {}
  for _, w in ipairs(b) do
    inB[w] = true
  end
  local shared = 0
  for _, w in ipairs(a) do
    if inB[w] then
      shared = shared + 1
    end
  end
  if shared > 0 then
    best = math.max(best, 70 * shared / math.max(#a, #b))
  end
  -- Spelling distance on the whole name, spaces ignored
  local sa, sb = spoken:gsub(" ", ""), known:gsub(" ", "")
  local longest = math.max(#sa, #sb)
  if longest > 0 then
    local similarity = 1 - Names.distance(sa, sb) / longest
    if similarity >= 0.7 then
      best = math.max(best, 75 * similarity)
    end
  end
  return best
end

--- Below this score a name is not considered a match.
Names.THRESHOLD = 45

--- @class NamedEntry
--- @field name string
--- @field room string|nil room name, nil for things without a room
--- @field id integer

--- Find the entry a spoken name means.
--- @param entries NamedEntry[]
--- @param spoken string
--- @param room string|nil room the request names, preferred when given
--- @return NamedEntry|nil match
--- @return NamedEntry[] candidates the equally good entries when it is ambiguous
function Names.find(entries, spoken, room)
  local s = Names.normalize(spoken)
  local r = Names.normalize(room)
  if s == "" then
    return nil, {}
  end
  local scored = {}
  for _, entry in ipairs(entries or {}) do
    local score = Names.score(s, Names.normalize(entry.name))
    -- "Living Room Ceiling" said as "ceiling" with room "Living Room"
    if entry.room ~= nil and score < 100 then
      score = math.max(score, Names.score(s, Names.normalize(entry.room .. " " .. entry.name)))
    end
    if score >= Names.THRESHOLD then
      if r ~= "" and entry.room ~= nil then
        if Names.normalize(entry.room) == r then
          score = score + 15
        else
          score = score - 15
        end
      end
      scored[#scored + 1] = { entry = entry, score = score }
    end
  end
  if #scored == 0 then
    return nil, {}
  end
  table.sort(scored, function(x, y)
    return x.score > y.score
  end)
  local top = scored[1].score
  local candidates = {}
  for _, item in ipairs(scored) do
    if top - item.score < 1 then
      candidates[#candidates + 1] = item.entry
    end
  end
  if #candidates == 1 then
    return candidates[1], candidates
  end
  return nil, candidates
end

--- Hidden Names: comma separated, * is a wildcard, case and accents ignored.
--- @param list string|nil
--- @return fun(name: string): boolean hidden
function Names.hider(list)
  local patterns = {}
  for item in tostring(list or ""):gmatch("[^,]+") do
    local n = Names.normalize((item:gsub("%*", " qqstarqq ")))
    if n ~= "" then
      local pattern = "^" .. n:gsub("([%^%$%(%)%%%.%[%]%+%-%?])", "%%%1"):gsub(" ?qqstarqq ?", ".*") .. "$"
      patterns[#patterns + 1] = pattern
    end
  end
  return function(name)
    local n = Names.normalize(name)
    for _, p in ipairs(patterns) do
      if n:find(p) then
        return true
      end
    end
    return false
  end
end

return Names
