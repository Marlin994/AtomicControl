local utils = require("utils")

local M = {}

local function num(value)
  if type(value) == "number" then return value end
  if type(value) == "string" then return tonumber(value) end

  if type(value) == "table" then
    return tonumber(value.amount) or
           tonumber(value.stored) or
           tonumber(value.fluidAmount) or
           tonumber(value.current) or
           tonumber(value.value) or
           tonumber(value.produced) or
           tonumber(value.generated) or
           tonumber(value.production) or
           tonumber(value.energy) or
           tonumber(value.rf) or
           tonumber(value.fe)
  end

  return nil
end

local function statNumber(stats, ...)
  if type(stats) ~= "table" then return nil end

  local keys = {...}

  for _, key in ipairs(keys) do
    local n = num(stats[key])
    if n ~= nil then return n end
  end

  return nil
end

function M.getRod(r)
  if not r or not r.p then return 100 end

  local value = utils.safe(function() return r.p.getControlRodLevel(0) end, 100)
  return num(value) or 100
end

function M.setRods(r, level)
  if not r or not r.p then return end

  level = utils.clamp(math.floor(tonumber(level) or 100), 0, 100)

  local count = utils.safe(function() return r.p.getNumberOfControlRods() end, 1)
  count = math.max(1, math.floor(num(count) or 1))

  for i = 0, count - 1 do
    utils.safe(function() r.p.setControlRodLevel(i, level) end)
  end
end

function M.setActive(r, state)
  if not r or not r.p then return end
  utils.safe(function() r.p.setActive(state and true or false) end)
end

function M.getActive(r)
  if not r or not r.p then return false end

  local active = utils.safe(function() return r.p.getActive() end, nil)
  if active ~= nil then return active and true or false end

  active = utils.safe(function() return r.p.isActive() end, nil)
  if active ~= nil then return active and true or false end

  return false
end

function M.getRF(r)
  if not r or not r.p then return 0 end

  local rf = num(utils.safe(function() return r.p.getEnergyProducedLastTick() end, nil))
  if rf ~= nil then return rf end

  rf = num(utils.safe(function() return r.p.getEnergyGeneratedLastTick() end, nil))
  if rf ~= nil then return rf end

  local stats = utils.safe(function() return r.p.getEnergyStats() end, nil)
  if type(stats) == "table" then
    rf = statNumber(stats,
      "energyProducedLastTick",
      "energyGeneratedLastTick",
      "producedLastTick",
      "generatedLastTick",
      "produced",
      "generated",
      "output",
      "rf",
      "fe"
    )

    if rf ~= nil then return rf end
  end

  return 0
end

function M.getSteamPercent(r)
  if not r or not r.p then return 0, false end

  local amount = num(utils.safe(function() return r.p.getHotFluidAmount() end, nil))
  local max = num(utils.safe(function() return r.p.getHotFluidAmountMax() end, nil))

  if amount ~= nil and max ~= nil and max > 0 then
    return utils.clamp(amount / max, 0, 1), true
  end

  local stats = utils.safe(function() return r.p.getHotFluidStats() end, nil)
  if type(stats) == "table" then
    amount = statNumber(stats, "amount", "stored", "fluidAmount", "current", "value")
    max = statNumber(stats, "capacity", "max", "fluidCapacity", "amountMax", "maxAmount")

    if amount ~= nil and max ~= nil and max > 0 then
      return utils.clamp(amount / max, 0, 1), true
    end
  end

  return 0, false
end

function M.getSteamStored(r)
  if not r or not r.p then return nil end

  local amount = num(utils.safe(function() return r.p.getHotFluidAmount() end, nil))
  if amount ~= nil then return amount end

  local stats = utils.safe(function() return r.p.getHotFluidStats() end, nil)
  if type(stats) == "table" then
    amount = statNumber(stats, "amount", "stored", "fluidAmount", "current", "value")
    if amount ~= nil then return amount end
  end

  return nil
end

function M.getSteamProduction(r)
  if not r or not r.p then return 0 end

  local value = num(utils.safe(function() return r.p.getHotFluidProducedLastTick() end, nil))
  if value ~= nil then return value end

  value = num(utils.safe(function() return r.p.getHotFluidGeneratedLastTick() end, nil))
  if value ~= nil then return value end

  value = num(utils.safe(function() return r.p.getFluidProducedLastTick() end, nil))
  if value ~= nil then return value end

  local stats = utils.safe(function() return r.p.getHotFluidStats() end, nil)
  if type(stats) == "table" then
    value = statNumber(stats,
      "producedLastTick",
      "generatedLastTick",
      "fluidProducedLastTick",
      "hotFluidProducedLastTick",
      "production",
      "produced",
      "generated"
    )

    if value ~= nil then return value end
  end

  return num(r.steamProduced) or 0
end

function M.updateSteamProduction(r, updateSeconds)
  if not r or r.kind ~= "ACTIVE" then
    if r then r.steamProduced = 0 end
    return
  end

  local direct = num(M.getSteamProduction(r))

  if direct ~= nil and direct > 0 then
    r.steamProduced = direct
    return
  end

  local stored = num(M.getSteamStored(r))

  if stored == nil then
    r.steamProduced = 0
    return
  end

  if r.lastSteam == nil then
    r.lastSteam = stored
    r.steamProduced = 0
    return
  end

  local lastSteam = num(r.lastSteam)

  if lastSteam == nil then
    r.lastSteam = stored
    r.steamProduced = 0
    return
  end

  local diff = stored - lastSteam
  r.lastSteam = stored

  if diff > 0 then
    r.steamProduced = diff / ((tonumber(updateSeconds) or 0.5) * 20)
  else
    r.steamProduced = 0
  end
end

function M.getAverageSteamPercent(reactorList)
  local total, count = 0, 0

  for _, r in ipairs(reactorList or {}) do
    if r.enabled and r.kind == "ACTIVE" then
      local pct, ok = M.getSteamPercent(r)

      if ok then
        total = total + (num(pct) or 0)
        count = count + 1
      end
    end
  end

  if count == 0 then return 0, false end
  return total / count, true
end

function M.getTotalPassiveRF(reactorList)
  local total = 0

  for _, r in ipairs(reactorList or {}) do
    if r.enabled and r.kind == "PASSIVE" then
      total = total + (num(M.getRF(r)) or 0)
    end
  end

  return total
end

function M.getTotalSteamProduction(reactorList)
  local total = 0

  for _, r in ipairs(reactorList or {}) do
    if r.enabled and r.kind == "ACTIVE" then
      total = total + (num(r.steamProduced) or 0)
    end
  end

  return total
end

return M
