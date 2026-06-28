local utils = require("utils")
local energy = require("energy")
local M = {}

function M.hasMethod(p, name)
  return p and type(p[name]) == "function"
end

function M.findMonitor()
  for _, name in ipairs(peripheral.getNames()) do
    if peripheral.getType(name) == "monitor" then
      return peripheral.wrap(name), name
    end
  end
end

function M.isTurbine(p)
  return M.hasMethod(p, "getRotorSpeed")
end

local function asNumber(v)
  return tonumber(v)
end

function M.reactorHasSteam(p)
  if not p then return false end

  -- Reliable Extreme Reactors source of truth:
  -- passive reactor => false
  -- active reactor  => true
  if M.hasMethod(p, "isActivelyCooled") then
    local v = utils.safe(function() return p.isActivelyCooled() end, nil)
    if v ~= nil then
      return v and true or false
    end
  end

  if M.hasMethod(p, "getCoolantAmountMax") then
    local max = utils.safe(function() return p.getCoolantAmountMax() end, nil)
    max = asNumber(max)
    if max ~= nil then return max > 0 end
  end

  if M.hasMethod(p, "getHotFluidAmountMax") then
    local max = utils.safe(function() return p.getHotFluidAmountMax() end, nil)
    max = asNumber(max)
    if max ~= nil then return max > 0 end
  end

  if M.hasMethod(p, "getHotFluidStats") then
    local stats = utils.safe(function() return p.getHotFluidStats() end, nil)

    if type(stats) == "table" then
      local capacity =
        asNumber(stats.fluidCapacity) or
        asNumber(stats.capacity) or
        asNumber(stats.max) or
        asNumber(stats.amountMax)

      if capacity ~= nil then return capacity > 0 end
    end
  end

  if M.hasMethod(p, "getHotFluidProducedLastTick") then
    local produced = utils.safe(function() return p.getHotFluidProducedLastTick() end, nil)
    produced = asNumber(produced)
    if produced and produced > 0 then return true end
  end

  if M.hasMethod(p, "getHotFluidGeneratedLastTick") then
    local produced = utils.safe(function() return p.getHotFluidGeneratedLastTick() end, nil)
    produced = asNumber(produced)
    if produced and produced > 0 then return true end
  end

  if M.hasMethod(p, "getFluidProducedLastTick") then
    local produced = utils.safe(function() return p.getFluidProducedLastTick() end, nil)
    produced = asNumber(produced)
    if produced and produced > 0 then return true end
  end

  return false
end

function M.isReactor(p)
  return M.hasMethod(p, "getControlRodLevel") and not M.isTurbine(p)
end

function M.findStorage()
  local firstCandidate, firstCandidateName = nil, nil

  for _, name in ipairs(peripheral.getNames()) do
    local p = peripheral.wrap(name)

    if p and not M.isReactor(p) and not M.isTurbine(p) then
      if energy.isEnergyStorage(p) then
        local stored, max, ok = energy.getStored(p)

        if ok then
          return p, name
        end

        if not firstCandidate then
          firstCandidate = p
          firstCandidateName = name
        end
      end
    end
  end

  return firstCandidate, firstCandidateName
end

function M.scan(state, cfg)
  state.reactors = {}
  state.turbines = {}
  state.storage, state.storageName = M.findStorage()
  state.monitor, state.monitorName = M.findMonitor()

  for _, name in ipairs(peripheral.getNames()) do
    local p = peripheral.wrap(name)

    if p then
      if M.isReactor(p) then
        local enabled = true
        if cfg and cfg.reactors and cfg.reactors[name] ~= nil then enabled = cfg.reactors[name] end

        table.insert(state.reactors, {
          name = name,
          p = p,
          kind = M.reactorHasSteam(p) and "ACTIVE" or "PASSIVE",
          enabled = enabled,
          managedActive = true,
          lastSteam = nil,
          steamProduced = 0
        })
      elseif M.isTurbine(p) then
        local enabled = true
        if cfg and cfg.turbines and cfg.turbines[name] ~= nil then enabled = cfg.turbines[name] end

        table.insert(state.turbines, {
          name = name,
          p = p,
          enabled = enabled
        })
      end
    end
  end
end

return M
