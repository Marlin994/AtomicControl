local utils = require("utils")

local M = {}

M.DEFAULT_MAX_FLOW = 2000

local function num(value)
  if type(value) == "number" then return value end
  if type(value) == "string" then return tonumber(value) end

  if type(value) == "table" then
    return tonumber(value.amount) or
           tonumber(value.flow) or
           tonumber(value.rate) or
           tonumber(value.speed) or
           tonumber(value.rpm) or
           tonumber(value.energy) or
           tonumber(value.rf) or
           tonumber(value.fe) or
           tonumber(value.value) or
           tonumber(value.current) or
           tonumber(value.max)
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

function M.getFlow(t)
  if not t then return 0 end

  local flow = num(utils.safe(function() return t.getFluidFlowRateMax() end, nil))
  if flow ~= nil then return flow end

  return 0
end

function M.getMaxFlow(t)
  if not t then return M.DEFAULT_MAX_FLOW end

  local v = num(utils.safe(function() return t.getFluidFlowRateMaxMax() end, nil))
  if v ~= nil and v > 0 then return v end

  v = num(utils.safe(function() return t.getFluidFlowRateMaxLimit() end, nil))
  if v ~= nil and v > 0 then return v end

  v = num(utils.safe(function() return t.getFluidFlowRateMaxCapacity() end, nil))
  if v ~= nil and v > 0 then return v end

  return M.DEFAULT_MAX_FLOW
end

function M.setFlow(t, flow)
  if not t then return end

  flow = utils.clamp(math.floor(tonumber(flow) or 0), 0, M.getMaxFlow(t))
  utils.safe(function() t.setFluidFlowRateMax(flow) end)
end

function M.getRPM(t)
  if not t then return 0 end

  local rpm = num(utils.safe(function() return t.getRotorSpeed() end, nil))
  if rpm ~= nil then return rpm end

  rpm = num(utils.safe(function() return t.getRotorRPM() end, nil))
  if rpm ~= nil then return rpm end

  rpm = num(utils.safe(function() return t.getRPM() end, nil))
  if rpm ~= nil then return rpm end

  local stats = utils.safe(function() return t.getRotorStats() end, nil)
  if type(stats) == "table" then
    rpm = statNumber(stats, "rotorSpeed", "speed", "rpm", "rotorRPM")
    if rpm ~= nil then return rpm end
  end

  return 0
end

function M.getRF(t)
  if not t then return 0 end

  local rf = num(utils.safe(function() return t.getEnergyProducedLastTick() end, nil))
  if rf ~= nil then return rf end

  rf = num(utils.safe(function() return t.getEnergyGeneratedLastTick() end, nil))
  if rf ~= nil then return rf end

  local stats = utils.safe(function() return t.getEnergyStats() end, nil)
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

function M.getSteam(t)
  if not t then return 0 end

  local v = num(utils.safe(function() return t.getFluidFlowRate() end, nil))
  if v ~= nil then return v end

  v = num(utils.safe(function() return t.getInputAmountLastTick() end, nil))
  if v ~= nil then return v end

  local stats = utils.safe(function() return t.getFluidStats() end, nil)
  if type(stats) == "table" then
    v = statNumber(stats, "flow", "rate", "amount", "input", "inputRate", "fluidFlowRate")
    if v ~= nil then return v end
  end

  return M.getFlow(t)
end

function M.setActive(t, state)
  if not t then return end
  utils.safe(function() t.setActive(state and true or false) end)
end

function M.setInductor(t, state)
  if not t then return end
  utils.safe(function() t.setInductorEngaged(state and true or false) end)
end

function M.getInductor(t)
  if not t then return false end

  local v = utils.safe(function() return t.getInductorEngaged() end, nil)
  if v ~= nil then return v and true or false end

  v = utils.safe(function() return t.isInductorEngaged() end, nil)
  if v ~= nil then return v and true or false end

  return true
end

function M.setup(list)
  for _, entry in ipairs(list or {}) do
    if entry and entry.p then
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
end

function M.getTotalRF(list)
  local total = 0

  for _, entry in ipairs(list or {}) do
    if entry and entry.enabled and entry.p then
      total = total + (num(M.getRF(entry.p)) or 0)
    end
  end

  return total
end

function M.getTotalSteam(list)
  local total = 0

  for _, entry in ipairs(list or {}) do
    if entry and entry.enabled and entry.p then
      total = total + (num(M.getSteam(entry.p)) or 0)
    end
  end

  return total
end

return M
