local utils = require("utils")
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

function M.reactorHasSteam(p)
  if M.hasMethod(p, "getHotFluidAmount") then
    local v = utils.safe(function() return p.getHotFluidAmount() end, nil)
    if v ~= nil then return true end
  end

  if M.hasMethod(p, "getHotFluidStats") then
    local v = utils.safe(function() return p.getHotFluidStats() end, nil)
    if v ~= nil then return true end
  end

  return false
end

function M.isReactor(p)
  return M.hasMethod(p, "getControlRodLevel") and not M.isTurbine(p)
end

function M.findStorage()
  for _, name in ipairs(peripheral.getNames()) do
    local p = peripheral.wrap(name)
    if p then
      if M.hasMethod(p, "getEnergyStored") and M.hasMethod(p, "getMaxEnergyStored") then return p, name end
      if M.hasMethod(p, "getEnergy") and M.hasMethod(p, "getMaxEnergy") then return p, name end
      if M.hasMethod(p, "getEnergyFilledPercentage") then return p, name end
    end
  end
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
