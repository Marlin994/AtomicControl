local turbines = require("turbines")
local reactors = require("reactors")
local utils = require("utils")

local M = {}

M.RESERVE_NORMAL = 1.03
M.MEASURED_OVERRIDE_FACTOR = 1.08

M.DEFAULT_TRANSFER_EFFICIENCY = 1.00
M.MIN_TRANSFER_EFFICIENCY = 0.50
M.MAX_TRANSFER_EFFICIENCY = 1.10
M.LEARN_ALPHA = 0.05
M.LEARN_MIN_PRODUCTION = 100
M.LEARN_MIN_USAGE = 100
M.LEARN_RPM_MIN = 1780
M.LEARN_RPM_MAX = 1820
M.LEARN_REQUIRED_TICKS = 20

local function getCalibration(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local value = cfg.turbineCalibrations[entry.name]
  if type(value) == "table" then return tonumber(value.flow) end
  return tonumber(value)
end

function M.getTransferEfficiency(cfg)
  local eff = tonumber(cfg and cfg.steamTransferEfficiency) or M.DEFAULT_TRANSFER_EFFICIENCY
  return utils.clamp(eff, M.MIN_TRANSFER_EFFICIENCY, M.MAX_TRANSFER_EFFICIENCY)
end

function M.getDemand(state, cfg)
  local measured = 0
  local calibrated = 0
  local demand = 0
  local calibratedCount = 0
  local uncalibratedCount = 0

  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled then
      local current = turbines.getSteam(entry.p) or 0
      local cal = getCalibration(cfg, entry)

      measured = measured + current

      if cal and cal > 0 then
        calibrated = calibrated + cal
        calibratedCount = calibratedCount + 1

        if current > cal * M.MEASURED_OVERRIDE_FACTOR then
          demand = demand + current
        else
          demand = demand + cal
        end
      else
        uncalibratedCount = uncalibratedCount + 1
        demand = demand + current
      end
    end
  end

  return {
    measured = measured,
    calibrated = calibrated,
    demand = demand,
    calibratedCount = calibratedCount,
    uncalibratedCount = uncalibratedCount
  }
end

function M.getTarget(state, cfg)
  local demand = M.getDemand(state, cfg)
  local eff = M.getTransferEfficiency(cfg)

  if cfg.operationMode == "CYANITE" then
    return {
      demand = demand,
      target = nil,
      reserve = nil,
      transferEfficiency = eff
    }
  end

  return {
    demand = demand,
    target = (demand.demand / eff) * M.RESERVE_NORMAL,
    reserve = M.RESERVE_NORMAL,
    transferEfficiency = eff
  }
end

function M.getProduction(state)
  return reactors.getTotalSteamProduction(state.reactors or {})
end

local function turbinesStable(state)
  local count = 0

  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled then
      count = count + 1
      local rpm = turbines.getRPM(entry.p)
      local flow = turbines.getSteam(entry.p)

      if rpm < M.LEARN_RPM_MIN or rpm > M.LEARN_RPM_MAX then return false end
      if flow <= 0 then return false end
      if not turbines.getInductor(entry.p) then return false end
    end
  end

  return count > 0
end

function M.learnTransferEfficiency(state, cfg)
  if not state or not cfg then return end

  if cfg.operationMode == "CYANITE" then
    state.transferEfficiencyLearnTicks = 0
    return
  end

  local turbineUse = turbines.getTotalSteam(state.turbines or {})
  local production = M.getProduction(state)

  state.steamTransferEfficiencyMeasured = nil

  if turbineUse < M.LEARN_MIN_USAGE or production < M.LEARN_MIN_PRODUCTION then
    state.transferEfficiencyLearnTicks = 0
    return
  end

  if not turbinesStable(state) then
    state.transferEfficiencyLearnTicks = 0
    return
  end

  local measured = turbineUse / production
  measured = utils.clamp(measured, M.MIN_TRANSFER_EFFICIENCY, M.MAX_TRANSFER_EFFICIENCY)

  state.steamTransferEfficiencyMeasured = measured
  state.transferEfficiencyLearnTicks = (state.transferEfficiencyLearnTicks or 0) + 1

  if state.transferEfficiencyLearnTicks < M.LEARN_REQUIRED_TICKS then
    return
  end

  state.transferEfficiencyLearnTicks = 0

  local old = M.getTransferEfficiency(cfg)
  local learned = old + ((measured - old) * M.LEARN_ALPHA)
  learned = utils.clamp(learned, M.MIN_TRANSFER_EFFICIENCY, M.MAX_TRANSFER_EFFICIENCY)

  if math.abs(learned - old) >= 0.001 then
    cfg.steamTransferEfficiency = learned
    state.configDirty = true
  end
end

return M
