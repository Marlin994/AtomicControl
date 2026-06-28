local utils = require("utils")
local M = {}

local function has(storage, method)
  return storage and type(storage[method]) == "function"
end

local function call(storage, method)
  if not has(storage, method) then return nil end
  return utils.safe(function() return storage[method]() end, nil)
end

function M.isEnergyStorage(storage)
  if not storage then return false end

  if has(storage, "getEnergyStored") and has(storage, "getMaxEnergyStored") then return true end
  if has(storage, "getEnergyStored") and has(storage, "getEnergyCapacity") then return true end
  if has(storage, "getEnergyStats") then return true end
  if has(storage, "getEnergy") and has(storage, "getMaxEnergy") then return true end
  if has(storage, "getStored") and has(storage, "getCapacity") then return true end
  if has(storage, "getRFStored") and has(storage, "getMaxRFStored") then return true end
  if has(storage, "getEnergyFilledPercentage") then return true end

  return false
end

function M.getStored(storage)
  if not storage then return 0, 1, false end

  local stored = call(storage, "getEnergyStored")
  local max = call(storage, "getMaxEnergyStored")
  if stored and max and max > 0 then return stored, max, true end

  stored = call(storage, "getEnergyStored")
  max = call(storage, "getEnergyCapacity")
  if stored and max and max > 0 then return stored, max, true end

  local stats = call(storage, "getEnergyStats")
  if type(stats) == "table" then
    stored = stats.energyStored
    max = stats.energyCapacity
    if stored and max and max > 0 then return stored, max, true end
  end

  stored = call(storage, "getEnergy")
  max = call(storage, "getMaxEnergy")
  if stored and max and max > 0 then return stored, max, true end

  stored = call(storage, "getStored")
  max = call(storage, "getCapacity")
  if stored and max and max > 0 then return stored, max, true end

  stored = call(storage, "getRFStored")
  max = call(storage, "getMaxRFStored")
  if stored and max and max > 0 then return stored, max, true end

  local pct = call(storage, "getEnergyFilledPercentage")
  if pct then
    if pct > 1 then pct = pct / 100 end
    return pct, 1, true
  end

  return 0, 1, false
end

function M.getPercent(storage)
  local stored, max, ok = M.getStored(storage)
  if not ok or max <= 0 then return 0, false end
  return utils.clamp(stored / max, 0, 1), true
end

local function getDirectIo(storage)
  if not storage then return nil end

  local inserted = call(storage, "getEnergyInsertedLastTick")
  local extracted = call(storage, "getEnergyExtractedLastTick")

  if inserted ~= nil or extracted ~= nil then
    inserted = tonumber(inserted) or 0
    extracted = tonumber(extracted) or 0

    return {
      input = inserted,
      output = extracted,
      net = inserted - extracted
    }
  end

  local io = call(storage, "getEnergyIoLastTick")
  if io ~= nil then
    io = tonumber(io) or 0

    if io >= 0 then
      return { input = io, output = 0, net = io }
    else
      return { input = 0, output = math.abs(io), net = io }
    end
  end

  local stats = call(storage, "getEnergyStats")
  if type(stats) == "table" then
    inserted = tonumber(stats.energyInsertedLastTick)
    extracted = tonumber(stats.energyExtractedLastTick)

    if inserted ~= nil or extracted ~= nil then
      inserted = inserted or 0
      extracted = extracted or 0

      return {
        input = inserted,
        output = extracted,
        net = inserted - extracted
      }
    end

    io = tonumber(stats.energyIoLastTick)
    if io ~= nil then
      if io >= 0 then
        return { input = io, output = 0, net = io }
      else
        return { input = 0, output = math.abs(io), net = io }
      end
    end
  end

  return nil
end

function M.updateFlow(state, updateSeconds)
  local direct = getDirectIo(state.storage)

  if direct then
    state.storageInRF = direct.input
    state.storageOutRF = direct.output
    state.storageNetRF = direct.net
    return
  end

  local storedNow, maxNow, ok = M.getStored(state.storage)

  if not ok then
    state.storageInRF = 0
    state.storageOutRF = 0
    state.storageNetRF = 0
    return
  end

  if state.lastStorage == nil then
    state.lastStorage = storedNow
    state.storageInRF = 0
    state.storageOutRF = 0
    state.storageNetRF = 0
    return
  end

  local diff = storedNow - state.lastStorage
  state.lastStorage = storedNow

  local rfPerTick = diff / ((updateSeconds or 0.5) * 20)
  state.storageNetRF = rfPerTick

  if rfPerTick >= 0 then
    state.storageInRF = rfPerTick
    state.storageOutRF = 0
  else
    state.storageInRF = 0
    state.storageOutRF = math.abs(rfPerTick)
  end
end

return M
