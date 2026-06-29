local utils = require("utils")

local M = {}

local lastStored = nil

local function call(p, name)
  if not p or type(p[name]) ~= "function" then return nil end
  return utils.safe(function() return p[name]() end, nil)
end

local function num(v)
  if type(v) == "number" then return v end
  if type(v) == "string" then return tonumber(v) end

  if type(v) == "table" then
    return tonumber(v.amount) or
           tonumber(v.stored) or
           tonumber(v.energy) or
           tonumber(v.value) or
           tonumber(v.current) or
           tonumber(v.rf) or
           tonumber(v.fe)
  end

  return nil
end

local function statNumber(stats, ...)
  if type(stats) ~= "table" then return nil end

  local keys = {...}
  for _, key in ipairs(keys) do
    local value = stats[key]
    local n = num(value)
    if n then return n end
  end

  return nil
end

local function getStats(p)
  local stats = call(p, "getEnergyStats")
  if type(stats) == "table" then return stats end
  return nil
end

function M.isEnergyStorage(storage)
  if not storage then return false end

  if type(storage.getEnergyStored) == "function" and
     (type(storage.getMaxEnergyStored) == "function" or type(storage.getEnergyCapacity) == "function") then
    return true
  end

  if type(storage.getEnergyStats) == "function" then
    local stats = getStats(storage)
    if stats then
      local stored = statNumber(stats, "stored", "energyStored", "energy", "amount", "current", "rf", "fe")
      local max = statNumber(stats, "capacity", "maxEnergyStored", "energyCapacity", "max", "amountMax", "maxEnergy", "capacityRF", "capacityFE")
      if stored ~= nil or max ~= nil then return true end
    end
    return true
  end

  if type(storage.getEnergy) == "function" and type(storage.getMaxEnergy) == "function" then return true end
  if type(storage.getStored) == "function" and type(storage.getCapacity) == "function" then return true end
  if type(storage.getRFStored) == "function" and type(storage.getMaxRFStored) == "function" then return true end
  if type(storage.getEnergyFilledPercentage) == "function" then return true end

  return false
end

function M.getStored(storage)
  if not storage then return nil end

  local v = num(call(storage, "getEnergyStored"))
  if v then return v end

  v = num(call(storage, "getEnergy"))
  if v then return v end

  v = num(call(storage, "getStored"))
  if v then return v end

  v = num(call(storage, "getRFStored"))
  if v then return v end

  local stats = getStats(storage)
  if stats then
    v = statNumber(stats, "stored", "energyStored", "energy", "amount", "current", "rf", "fe")
    if v then return v end
  end

  return nil
end

function M.getCapacity(storage)
  if not storage then return nil end

  local v = num(call(storage, "getMaxEnergyStored"))
  if v then return v end

  v = num(call(storage, "getEnergyCapacity"))
  if v then return v end

  v = num(call(storage, "getMaxEnergy"))
  if v then return v end

  v = num(call(storage, "getCapacity"))
  if v then return v end

  v = num(call(storage, "getMaxRFStored"))
  if v then return v end

  local stats = getStats(storage)
  if stats then
    v = statNumber(stats, "capacity", "maxEnergyStored", "energyCapacity", "max", "amountMax", "maxEnergy", "capacityRF", "capacityFE")
    if v then return v end
  end

  return nil
end

function M.getPercent(storage)
  if not storage then return 0, false end

  local filled = num(call(storage, "getEnergyFilledPercentage"))
  if filled ~= nil then
    if filled > 1 then filled = filled / 100 end
    return utils.clamp(filled, 0, 1), true
  end

  local stored = M.getStored(storage)
  local max = M.getCapacity(storage)

  stored = tonumber(stored)
  max = tonumber(max)

  if stored ~= nil and max ~= nil and max > 0 then
    return utils.clamp(stored / max, 0, 1), true
  end

  return 0, false
end

local function directInserted(storage)
  return num(call(storage, "getEnergyInsertedLastTick"))
end

local function directExtracted(storage)
  return num(call(storage, "getEnergyExtractedLastTick"))
end

local function directIo(storage)
  return num(call(storage, "getEnergyIoLastTick"))
end

local function statsInserted(stats)
  return statNumber(stats, "insertedLastTick", "energyInsertedLastTick", "inserted", "input", "in", "rfIn", "feIn")
end

local function statsExtracted(stats)
  return statNumber(stats, "extractedLastTick", "energyExtractedLastTick", "extracted", "output", "out", "rfOut", "feOut")
end

function M.updateFlow(state)
  if not state then return end

  local storage = state.storage
  local stored = M.getStored(storage)

  state.storageInRF = 0
  state.storageOutRF = 0
  state.storageNetRF = 0

  if not storage then
    lastStored = nil
    return
  end

  local inserted = directInserted(storage)
  local extracted = directExtracted(storage)

  if inserted or extracted then
    state.storageInRF = inserted or 0
    state.storageOutRF = extracted or 0
    state.storageNetRF = state.storageInRF - state.storageOutRF
    lastStored = stored
    return
  end

  local io = directIo(storage)
  if io then
    state.storageNetRF = io
    if io >= 0 then
      state.storageInRF = io
      state.storageOutRF = 0
    else
      state.storageInRF = 0
      state.storageOutRF = -io
    end
    lastStored = stored
    return
  end

  local stats = getStats(storage)
  if stats then
    inserted = statsInserted(stats)
    extracted = statsExtracted(stats)

    if inserted or extracted then
      state.storageInRF = inserted or 0
      state.storageOutRF = extracted or 0
      state.storageNetRF = state.storageInRF - state.storageOutRF
      lastStored = stored
      return
    end
  end

  if stored and lastStored then
    local delta = stored - lastStored
    state.storageNetRF = delta
    if delta >= 0 then
      state.storageInRF = delta
      state.storageOutRF = 0
    else
      state.storageInRF = 0
      state.storageOutRF = -delta
    end
  end

  lastStored = stored
end

return M
