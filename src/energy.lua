local utils = require("utils")
local M = {}

function M.getStored(storage)
  if not storage then return 0, 1, false end

  local stored = utils.safe(function() return storage.getEnergyStored() end, nil)
  local max = utils.safe(function() return storage.getMaxEnergyStored() end, nil)
  if stored and max and max > 0 then return stored, max, true end

  stored = utils.safe(function() return storage.getEnergy() end, nil)
  max = utils.safe(function() return storage.getMaxEnergy() end, nil)
  if stored and max and max > 0 then return stored, max, true end

  local pct = utils.safe(function() return storage.getEnergyFilledPercentage() end, nil)
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

function M.updateFlow(state, updateSeconds)
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
