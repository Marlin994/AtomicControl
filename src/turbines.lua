local utils = require("utils")
local M = {}

M.DEFAULT_MAX_FLOW = 2000

function M.getFlow(t)
  return utils.safe(function() return t.getFluidFlowRateMax() end, 0)
end

function M.getMaxFlow(t)
  local v = utils.safe(function() return t.getFluidFlowRateMaxMax() end, nil)
  if v and v > 0 then return v end

  v = utils.safe(function() return t.getFluidFlowRateMaxLimit() end, nil)
  if v and v > 0 then return v end

  return M.DEFAULT_MAX_FLOW
end

function M.setFlow(t, flow)
  flow = utils.clamp(math.floor(flow or 0), 0, M.getMaxFlow(t))
  utils.safe(function() t.setFluidFlowRateMax(flow) end)
end

function M.getRPM(t)
  return utils.safe(function() return t.getRotorSpeed() end, 0)
end

function M.getRF(t)
  local rf = utils.safe(function() return t.getEnergyProducedLastTick() end, nil)
  if rf ~= nil then return rf end

  rf = utils.safe(function() return t.getEnergyGeneratedLastTick() end, nil)
  if rf ~= nil then return rf end

  return 0
end

function M.getSteam(t)
  local v = utils.safe(function() return t.getFluidFlowRate() end, nil)
  if v ~= nil then return v end
  return M.getFlow(t)
end

function M.setActive(t, state)
  utils.safe(function() t.setActive(state) end)
end

function M.setInductor(t, state)
  utils.safe(function() t.setInductorEngaged(state) end)
end

function M.getInductor(t)
  local v = utils.safe(function() return t.getInductorEngaged() end, nil)
  if v ~= nil then return v end

  v = utils.safe(function() return t.isInductorEngaged() end, nil)
  if v ~= nil then return v end

  return true
end

function M.setup(list)
  for _, entry in ipairs(list or {}) do
    if entry.enabled then
      M.setActive(entry.p, true)
      utils.safe(function() entry.p.setVentOverflow() end)
    else
      M.setActive(entry.p, false)
      M.setInductor(entry.p, false)
      M.setFlow(entry.p, 0)
    end
  end
end

function M.getTotalRF(list)
  local total = 0

  for _, entry in ipairs(list or {}) do
    if entry.enabled then
      total = total + M.getRF(entry.p)
    end
  end

  return total
end

function M.getTotalSteam(list)
  local total = 0

  for _, entry in ipairs(list or {}) do
    if entry.enabled then
      total = total + M.getSteam(entry.p)
    end
  end

  return total
end

return M
