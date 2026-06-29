local turbines = require("turbines")
local reactors = require("reactors")
local utils = require("utils")

local M = {}

M.RESERVE_NORMAL = 1.03
M.MEASURED_OVERRIDE_FACTOR = 1.08

-- Learned factor:
-- turbine steam actually used / reactor steam produced.
-- 1.00 means no measured transfer loss.
M.DEFAULT_TRANSFER_EFFICIENCY = 1.00
M.MIN_TRANSFER_EFFICIENCY = 0.50
M.MAX_TRANSFER_EFFICIENCY = 1.10

-- Learning:
-- The value is now learned more permissively. RPM is used as a quality signal,
-- not as a hard blocker.
M.LEARN_ALPHA_STABLE = 0.05
M.LEARN_ALPHA_UNSTABLE = 0.015
M.LEARN_MIN_PRODUCTION = 500
M.LEARN_MIN_USAGE = 500
M.LEARN_RPM_MIN = 1780
M.LEARN_RPM_MAX = 1820
M.LEARN_REQUIRED_TICKS_STABLE = 20
M.LEARN_REQUIRED_TICKS_UNSTABLE = 60

local function getCalibration(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local value = cfg.turbineCalibrations[entry.name]
  if type(value) == "table" then return tonumber(value.flow) end
  return tonumber(value)
end

local function getTargetRPM(cfg, entry)
  if not cfg or not entry or not entry.name then return 1800 end
  if type(cfg.turbineCalibrations) ~= "table" then return 1800 end

  local value = cfg.turbineCalibrations[entry.name]
  if type(value) == "table" then return tonumber(value.rpm) or 1800 end
  return 1800
end

local function deviceAutoEnabled(cfg, entry)
  if not entry or not entry.name then return true end
  if type(cfg) ~= "table" then return true end
  if type(cfg.deviceAutoEnabled) ~= "table" then return true end
  return cfg.deviceAutoEnabled[entry.name] ~= false
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
    if entry.enabled and deviceAutoEnabled(cfg, entry) then
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
    -- If only part of the produced steam reaches the turbines,
    -- reactor production must be higher than turbine demand.
    target = (demand.demand / eff) * M.RESERVE_NORMAL,
    reserve = M.RESERVE_NORMAL,
    transferEfficiency = eff
  }
end

function M.getProduction(state)
  return reactors.getTotalSteamProduction(state.reactors or {})
end

local function turbineQuality(state, cfg)
  local count = 0
  local stable = true
  local anyInductor = false

  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled and deviceAutoEnabled(cfg, entry) then
      count = count + 1

      local rpm = turbines.getRPM(entry.p)
      local flow = turbines.getSteam(entry.p)
      local targetRPM = getTargetRPM(cfg, entry)

      if turbines.getInductor(entry.p) then
        anyInductor = true
      end

      if math.abs((rpm or 0) - targetRPM) > 20 then
        stable = false
      end

      if flow <= 0 then
        stable = false
      end
    end
  end

  return {
    hasTurbine = count > 0,
    stable = stable and count > 0 and anyInductor,
    hasInductor = anyInductor
  }
end

function M.learnTransferEfficiency(state, cfg)
  if not state or not cfg then return end

  if cfg.operationMode == "CYANITE" then
    state.transferEfficiencyLearnTicks = 0
    state.steamTransferEfficiencyMeasured = nil
    return
  end

  local turbineUse = turbines.getTotalSteam(state.turbines or {})
  local production = M.getProduction(state)

  if turbineUse < M.LEARN_MIN_USAGE or production < M.LEARN_MIN_PRODUCTION then
    state.transferEfficiencyLearnTicks = 0
    state.steamTransferEfficiencyMeasured = nil
    return
  end

  local measured = turbineUse / production
  measured = utils.clamp(measured, M.MIN_TRANSFER_EFFICIENCY, M.MAX_TRANSFER_EFFICIENCY)

  -- Always expose the live measured value to the UI when data is meaningful.
  state.steamTransferEfficiencyMeasured = measured

  local quality = turbineQuality(state, cfg)

  if not quality.hasTurbine then
    state.transferEfficiencyLearnTicks = 0
    return
  end

  -- Stable RPM learns faster. Unstable RPM still learns, but slower and only
  -- when at least one turbine is actually engaged.
  if quality.stable then
    state.transferEfficiencyLearnTicks = (state.transferEfficiencyLearnTicks or 0) + 1

    if state.transferEfficiencyLearnTicks < M.LEARN_REQUIRED_TICKS_STABLE then
      return
    end

    state.transferEfficiencyLearnTicks = 0

    local old = M.getTransferEfficiency(cfg)
    local learned = old + ((measured - old) * M.LEARN_ALPHA_STABLE)
    learned = utils.clamp(learned, M.MIN_TRANSFER_EFFICIENCY, M.MAX_TRANSFER_EFFICIENCY)

    if math.abs(learned - old) >= 0.001 then
      cfg.steamTransferEfficiency = learned
      state.configDirty = true
    end

    return
  end

  if not quality.hasInductor then
    state.transferEfficiencyLearnTicks = 0
    return
  end

  state.transferEfficiencyLearnTicks = (state.transferEfficiencyLearnTicks or 0) + 1

  if state.transferEfficiencyLearnTicks < M.LEARN_REQUIRED_TICKS_UNSTABLE then
    return
  end

  state.transferEfficiencyLearnTicks = 0

  local old = M.getTransferEfficiency(cfg)
  local learned = old + ((measured - old) * M.LEARN_ALPHA_UNSTABLE)
  learned = utils.clamp(learned, M.MIN_TRANSFER_EFFICIENCY, M.MAX_TRANSFER_EFFICIENCY)

  if math.abs(learned - old) >= 0.001 then
    cfg.steamTransferEfficiency = learned
    state.configDirty = true
  end
end

return M
