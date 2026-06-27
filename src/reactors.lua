local utils = require("utils")
local M = {}

function M.getRod(r)
  if not r or not r.p then return 100 end
  return utils.safe(function() return r.p.getControlRodLevel(0) end, 100)
end

function M.setRods(r, level)
  if not r or not r.p then return end
  level = utils.clamp(math.floor(level or 100), 0, 100)
  local count = utils.safe(function() return r.p.getNumberOfControlRods() end, 1)
  for i = 0, count - 1 do
    utils.safe(function() r.p.setControlRodLevel(i, level) end)
  end
end

function M.setActive(r, state)
  if not r or not r.p then return end
  utils.safe(function() r.p.setActive(state) end)
end

function M.getActive(r)
  if not r or not r.p then return false end
  local active = utils.safe(function() return r.p.getActive() end, nil)
  if active ~= nil then return active end
  active = utils.safe(function() return r.p.isActive() end, nil)
  if active ~= nil then return active end
  return false
end

function M.getRF(r)
  if not r or not r.p then return 0 end
  local rf = utils.safe(function() return r.p.getEnergyProducedLastTick() end, nil)
  if rf ~= nil then return rf end
  rf = utils.safe(function() return r.p.getEnergyGeneratedLastTick() end, nil)
  if rf ~= nil then return rf end
  local stats = utils.safe(function() return r.p.getEnergyStats() end, nil)
  if stats then
    return stats.energyProducedLastTick or stats.energyGeneratedLastTick or stats.producedLastTick or 0
  end
  return 0
end

function M.getSteamPercent(r)
  if not r or not r.p then return 0, false end
  local amount = utils.safe(function() return r.p.getHotFluidAmount() end, nil)
  local max = utils.safe(function() return r.p.getHotFluidAmountMax() end, nil)
  if amount and max and max > 0 then return utils.clamp(amount / max, 0, 1), true end

  local stats = utils.safe(function() return r.p.getHotFluidStats() end, nil)
  if stats then
    amount = stats.amount or stats.stored or stats.fluidAmount
    max = stats.capacity or stats.max or stats.fluidCapacity
    if amount and max and max > 0 then return utils.clamp(amount / max, 0, 1), true end
  end
  return 0, false
end

function M.getSteamStored(r)
  if not r or not r.p then return nil end
  local amount = utils.safe(function() return r.p.getHotFluidAmount() end, nil)
  if amount ~= nil then return amount end
  local stats = utils.safe(function() return r.p.getHotFluidStats() end, nil)
  if stats then return stats.amount or stats.stored or stats.fluidAmount end
  return nil
end

function M.getSteamProduction(r)
  if not r or not r.p then return 0 end

  local v = utils.safe(function() return r.p.getHotFluidProducedLastTick() end, nil)
  if v ~= nil then return v end

  v = utils.safe(function() return r.p.getHotFluidGeneratedLastTick() end, nil)
  if v ~= nil then return v end

  v = utils.safe(function() return r.p.getFluidProducedLastTick() end, nil)
  if v ~= nil then return v end

  return r.steamProduced or 0
end

function M.updateSteamProduction(r, updateSeconds)
  if not r or r.kind ~= "ACTIVE" then
    r.steamProduced = 0
    return
  end

  local direct = M.getSteamProduction(r)
  if direct and direct > 0 then
    r.steamProduced = direct
    return
  end

  local stored = M.getSteamStored(r)
  if stored == nil then
    r.steamProduced = 0
    return
  end

  if r.lastSteam == nil then
    r.lastSteam = stored
    r.steamProduced = 0
    return
  end

  local diff = stored - r.lastSteam
  r.lastSteam = stored
  if diff > 0 then
    r.steamProduced = diff / ((updateSeconds or 0.5) * 20)
  else
    r.steamProduced = 0
  end
end

function M.getAverageSteamPercent(reactors)
  local total, count = 0, 0
  for _, r in ipairs(reactors or {}) do
    if r.enabled and r.kind == "ACTIVE" then
      local pct, ok = M.getSteamPercent(r)
      if ok then
        total = total + pct
        count = count + 1
      end
    end
  end
  if count == 0 then return 0, false end
  return total / count, true
end

function M.getTotalPassiveRF(reactors)
  local total = 0
  for _, r in ipairs(reactors or {}) do
    if r.enabled and r.kind == "PASSIVE" then total = total + M.getRF(r) end
  end
  return total
end

function M.getTotalSteamProduction(reactors)
  local total = 0
  for _, r in ipairs(reactors or {}) do
    if r.enabled and r.kind == "ACTIVE" then total = total + (r.steamProduced or 0) end
  end
  return total
end

return M
