local M = {}
local current = {}
local fallback = {}

local function loadFile(code)
  local path = "lang/" .. tostring(code or "de") .. ".lua"
  if fs.exists(path) then
    local ok, data = pcall(dofile, path)
    if ok and type(data) == "table" then return data end
  end
  return nil
end

function M.load(code)
  fallback = loadFile("de") or {}
  current = loadFile(code or "de") or fallback
  return M
end

function M.get(key)
  if current[key] ~= nil then return current[key] end
  if fallback[key] ~= nil then return fallback[key] end
  return tostring(key)
end

setmetatable(M, { __index = function(_, key) return M.get(key) end })

return M
