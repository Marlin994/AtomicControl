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

local function numberOrNil(v)
  v = tonumber(v)
  if v == nil then return nil end
  return v
end

function M.reactorHasSteam(p)
  if not p then return false end

  -- Strong indicators for actively cooled reactors.
  -- Do NOT use getHotFluidAmount alone. Passive reactors can expose it too.
  if M.hasMethod(p, "getHotFluidProducedLastTick") then return true end
  if M.hasMethod(p, "getHotFluidGeneratedLastTick") then return true end
  if M.hasMethod(p, "getFluidProducedLastTick") then return true end

  -- Some versions expose stats instead of explicit production methods.
  if M.hasMethod(p, "getHotFluidStats") then
    local stats = utils.safe(function() return p.getHotFluidStats() end, nil)

    if type(stats) == "table" then
      local capacity =
        numberOrNil(stats.capacity) or
        numberOrNil(stats.max) or
        numberOrNil(stats.fluidCapacity) or
        numberOrNil(stats.amountMax)

      local amount =
        numberOrNil(stats.amount) or
        numberOrNil(stats.stored) or
        numberOrNil(stats.fluidAmount)

      local produced =
        numberOrNil(stats.producedLastTick) or
        numberOrNil(stats.generatedLastTick) or
        numberOrNil(stats.amountProducedLastTick)

      -- A real active reactor usually has a hot-fluid tank with capacity,
      -- or reports hot-fluid production. Passive reactors may expose empty
      -- compatibility methods, so require meaningful data.
      if produced and produced > 0 then return true end
      if capacity and capacity > 0 then return true end
      if amount and amount > 0 then return true end
    end
  end

  -- Last fallback: only classify as active if a max/capacity method exists
  -- and returns a positive value. getHotFluidAmount alone is not enough.
  if M.hasMethod(p, "getHotFluidAmountMax") then
    local max = utils.safe(function() return p.getHotFluidAmountMax() end, nil)
    max = numberOrNil(max)
    if max and max > 0 then return true end
  end

  if M.hasMethod(p, "getHotFluidCapacity") then
    local max = utils.safe(function() return p.getHotFluidCapacity() end, nil)
    max = numberOrNil(max)
    if max and max > 0 then return true end
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
