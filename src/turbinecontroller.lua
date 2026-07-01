local utils = require("utils")
local turbines = require("turbines")

local M = {}

local function deviceAutoEnabled(cfg, entry)
  if not entry or not entry.name then return true end
  if type(cfg) ~= "table" then return true end
  if type(cfg.deviceAutoEnabled) ~= "table" then
    cfg.deviceAutoEnabled = {}
    return true
  end

  local value = cfg.deviceAutoEnabled[entry.name]
  if value == nil then return true end
  return value and true or false
end


local function numberOr(value, fallback)
  local n = tonumber(value)
  if n == nil then return fallback or 0 end
  return n
end


M.TARGET_RPM = 1800
M.RPM_DISENGAGE = 1700
M.RPM_REENGAGE = 1750
M.RPM_DEADBAND = 2

M.FLOW_STEP_FAR = 25
M.FLOW_STEP_MED = 10
M.FLOW_STEP_FINE = 5
M.FLOW_STEP_ULTRA = 1

M.PID_KP = 0.06
M.PID_KI = 0.004
M.PID_KD = 0.02
M.PID_INTEGRAL_LIMIT = 250

M.CAL_STABLE_MIN = 1795
M.CAL_STABLE_MAX = 1805
M.CAL_STABLE_TICKS = 16
M.CAL_TIMEOUT_TICKS = 800

M.LEARN_MIN_RPM = 1798
M.LEARN_MAX_RPM = 1802
M.LEARN_REQUIRED_TICKS = 60
M.LEARN_CHANGE_THRESHOLD = 0.02
M.LEARN_ALPHA = 0.10

local function maxStepForRPM(rpm, targetRPM)
  targetRPM = targetRPM or M.TARGET_RPM
  local diff = math.abs((rpm or 0) - targetRPM)

  if diff > 100 then return M.FLOW_STEP_FAR end
  if diff > 50 then return M.FLOW_STEP_MED end
  if diff > 25 then return M.FLOW_STEP_FINE end
  return M.FLOW_STEP_ULTRA
end

local function clamp(v, min, max)
  v = numberOr(v, 0)
  min = numberOr(min, 0)
  max = numberOr(max, 0)

  if v < min then return min end
  if v > max then return max end
  return v
end

local function integerPart(v)
  if v >= 0 then
    return math.floor(v)
  else
    return math.ceil(v)
  end
end

function M.getCalibration(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local value = cfg.turbineCalibrations[entry.name]
  if type(value) == "table" then return tonumber(value.flow) end
  return tonumber(value)
end

function M.getTargetRPM(cfg, entry)
  if not cfg or not entry or not entry.name then return M.TARGET_RPM end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local value = cfg.turbineCalibrations[entry.name]
  if type(value) == "table" then
    return utils.clamp(math.floor(tonumber(value.rpm) or M.TARGET_RPM), 1200, 2200)
  end

  return M.TARGET_RPM
end


local function getIdleFlow(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local value = cfg.turbineCalibrations[entry.name]

  if type(value) == "table" then
    if tonumber(value.idleFlow) then return tonumber(value.idleFlow) end
    if tonumber(value.flow) then return utils.clamp(math.floor(tonumber(value.flow) * 0.10), 25, 250) end
  end

  if tonumber(value) then return utils.clamp(math.floor(tonumber(value) * 0.10), 25, 250) end
  return nil
end

function M.setCalibration(cfg, entry, flow)
  if not cfg or not entry or not entry.name then return end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local nominal = math.floor(flow or 0)
  local targetRPM = M.getTargetRPM(cfg, entry)

  cfg.turbineCalibrations[entry.name] = {
    flow = nominal,
    idleFlow = utils.clamp(math.floor(nominal * 0.10), 25, 250),
    rpm = targetRPM,
    learned = false,
    calibratedAt = os.epoch and os.epoch("utc") or os.clock()
  }
end

local function updateCalibrationValue(cfg, entry, newFlow, learned)
  if not cfg or not entry or not entry.name then return end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local rounded = math.floor(newFlow or 0)
  if rounded <= 0 then return end

  local old = cfg.turbineCalibrations[entry.name]
  local oldTable = type(old) == "table" and old or {}

  local targetRPM = tonumber(oldTable.rpm) or M.getTargetRPM(cfg, entry)

  cfg.turbineCalibrations[entry.name] = {
    flow = rounded,
    idleFlow = utils.clamp(math.floor(rounded * 0.10), 25, 250),
    rpm = targetRPM,
    learned = learned or oldTable.learned or false,
    calibratedAt = oldTable.calibratedAt or (os.epoch and os.epoch("utc") or os.clock()),
    updatedAt = os.epoch and os.epoch("utc") or os.clock()
  }
end

local function resetPid(entry)
  entry.pidIntegral = 0
  entry.pidLastError = nil
  entry.pidCarry = 0
end

local function pidFlowDelta(entry, rpm, targetRPM)
  targetRPM = targetRPM or M.TARGET_RPM
  local error = targetRPM - (rpm or 0)
  local absError = math.abs(error)

  if absError <= M.RPM_DEADBAND then
    entry.pidIntegral = (entry.pidIntegral or 0) * 0.80
    entry.pidLastError = error
    entry.pidCarry = 0
    return 0
  end

  local maxStep = maxStepForRPM(rpm, targetRPM)

  entry.pidIntegral = clamp((entry.pidIntegral or 0) + error, -M.PID_INTEGRAL_LIMIT, M.PID_INTEGRAL_LIMIT)

  local derivative = 0
  if entry.pidLastError ~= nil then
    derivative = error - entry.pidLastError
  end
  entry.pidLastError = error

  local output =
    (M.PID_KP * error) +
    (M.PID_KI * entry.pidIntegral) +
    (M.PID_KD * derivative)

  output = clamp(output, -maxStep, maxStep)

  entry.pidCarry = (entry.pidCarry or 0) + output
  entry.pidCarry = clamp(entry.pidCarry, -maxStep, maxStep)

  local delta = integerPart(entry.pidCarry)

  if delta ~= 0 then
    entry.pidCarry = entry.pidCarry - delta
  end

  return clamp(delta, -maxStep, maxStep)
end

local function learnCalibration(state, cfg, entry, rpm, flow, storageFull, targetRPM)
  if storageFull or cfg.operationMode == "CYANITE" then
    entry.learnTicks = 0
    return
  end

  if not entry.enabled then entry.learnTicks = 0 return end
  if not turbines.getInductor(entry.p) then entry.learnTicks = 0 return end
  if math.abs((rpm or 0) - (targetRPM or M.TARGET_RPM)) > 2 then entry.learnTicks = 0 return end
  flow = numberOr(flow, 0)
  if flow <= 0 then entry.learnTicks = 0 return end

  entry.learnTicks = (entry.learnTicks or 0) + 1
  if entry.learnTicks < M.LEARN_REQUIRED_TICKS then return end
  entry.learnTicks = 0

  local old = M.getCalibration(cfg, entry)

  if not old or old <= 0 then
    updateCalibrationValue(cfg, entry, flow, true)
    state.configDirty = true
    state.statusLine = "Learned T calibration: " .. math.floor(flow) .. " mB/t"
    return
  end

  local diff = math.abs(flow - old) / old

  if diff >= M.LEARN_CHANGE_THRESHOLD then
    local learnedFlow = old + ((flow - old) * M.LEARN_ALPHA)
    updateCalibrationValue(cfg, entry, learnedFlow, true)
    state.configDirty = true
    state.statusLine = "Adjusted T calibration: " .. math.floor(learnedFlow) .. " mB/t"
  end
end

function M.startCalibration(state)
  local entry = state.turbines and state.turbines[state.selectedTurbine or 1]
  if not entry then return false end

  resetPid(entry)

  state.calibration = {
    active = true,
    turbineIndex = state.selectedTurbine or 1,
    turbineName = entry.name,
    stableTicks = 0,
    ticks = 0
  }

  state.statusLine = "Calibration T" .. tostring(state.selectedTurbine) .. " started"
  return true
end

function M.runCalibration(state, cfg)
  local cal = state.calibration
  if not cal or not cal.active then return false end

  local entry = state.turbines[cal.turbineIndex]

  if not entry or entry.name ~= cal.turbineName then
    state.calibration = nil
    state.statusLine = "Calibration cancelled"
    return true
  end

  local t = entry.p
  local rpm = numberOr(turbines.getRPM(t), 0)
  local flow = numberOr(turbines.getFlow(t), 0)
  local targetRPM = numberOr(M.getTargetRPM(cfg, entry), M.TARGET_RPM)

  entry.enabled = true
  turbines.setActive(t, true)

  if rpm < targetRPM - 100 then
    turbines.setInductor(t, false)
  elseif rpm >= targetRPM - 50 then
    turbines.setInductor(t, true)
  end

  local delta = pidFlowDelta(entry, rpm, targetRPM)
  if delta ~= 0 then turbines.setFlow(t, flow + delta) end

  if rpm >= targetRPM - 5 and rpm <= targetRPM + 5 then
    cal.stableTicks = cal.stableTicks + 1
  else
    cal.stableTicks = 0
  end

  cal.ticks = cal.ticks + 1

  if cal.stableTicks >= M.CAL_STABLE_TICKS then
    local finalFlow = numberOr(turbines.getFlow(t), 0)
    M.setCalibration(cfg, entry, finalFlow)
    state.configDirty = true
    state.calibration = nil
    resetPid(entry)
    state.statusLine = "T" .. tostring(cal.turbineIndex) .. " calibrated: " .. tostring(finalFlow) .. " mB/t"
    return true
  end

  if cal.ticks >= M.CAL_TIMEOUT_TICKS then
    local finalFlow = numberOr(turbines.getFlow(t), 0)

    if finalFlow > 0 then
      M.setCalibration(cfg, entry, finalFlow)
      state.configDirty = true
      state.statusLine = "T" .. tostring(cal.turbineIndex) .. " timeout saved: " .. tostring(finalFlow) .. " mB/t"
    else
      state.statusLine = "Calibration timeout"
    end

    state.calibration = nil
    resetPid(entry)
    return true
  end

  state.statusLine = "Cal T" .. tostring(cal.turbineIndex) .. ": " .. math.floor(rpm) .. "/" .. math.floor(targetRPM) .. " RPM / " .. math.floor(flow) .. " mB/t"
  return true
end

function M.update(state, cfg, storageFull)
  local needsSteam = false
  local cyanite = cfg.operationMode == "CYANITE"

  for _, entry in ipairs(state.turbines or {}) do
    local t = entry.p

    if not deviceAutoEnabled(cfg, entry) then
      entry.enabled = false
      turbines.setActive(t, false)
      turbines.setInductor(t, false)
      turbines.setFlow(t, 0)
      entry.learnTicks = 0
      resetPid(entry)
    elseif not entry.enabled then
      turbines.setActive(t, false)
      turbines.setInductor(t, false)
      turbines.setFlow(t, 0)
      entry.learnTicks = 0
      resetPid(entry)
    else
      local rpm = numberOr(turbines.getRPM(t), 0)
      local flow = numberOr(turbines.getFlow(t), 0)
      local engaged = turbines.getInductor(t)
      local calibrated = M.getCalibration(cfg, entry)
      calibrated = calibrated and numberOr(calibrated, 0) or nil
      local targetRPM = numberOr(M.getTargetRPM(cfg, entry), M.TARGET_RPM)

      turbines.setActive(t, state.enabled)

      if storageFull and not cyanite then
        turbines.setInductor(t, false)

        local idle = getIdleFlow(cfg, entry) or 0

        if idle > 0 then
          local idleError = idle - flow

          if math.abs(idleError) > 1 then
            local maxStep = M.FLOW_STEP_MED
            turbines.setFlow(t, flow + clamp(idleError, -maxStep, maxStep))
          end
        else
          turbines.setFlow(t, 0)
        end

        entry.learnTicks = 0
        resetPid(entry)
      else
        if calibrated and calibrated > 0 and math.abs(targetRPM - rpm) > 50 and math.abs(calibrated - flow) > 150 then
          if calibrated > flow then
            turbines.setFlow(t, flow + M.FLOW_STEP_FAR)
          else
            turbines.setFlow(t, flow - M.FLOW_STEP_FAR)
          end
        end

        if rpm < targetRPM - 100 then
          turbines.setInductor(t, false)
          needsSteam = true
        elseif rpm < targetRPM - 50 then
          turbines.setInductor(t, engaged)
          needsSteam = true
        else
          turbines.setInductor(t, true)
        end

        local delta = pidFlowDelta(entry, rpm, targetRPM)
        if delta ~= 0 then turbines.setFlow(t, turbines.getFlow(t) + delta) end

        if rpm < targetRPM - 10 then needsSteam = true end

        learnCalibration(state, cfg, entry, rpm, turbines.getFlow(t), storageFull, targetRPM)
      end
    end
  end

  return needsSteam
end

function M.lowestRPM(state)
  local lowest = nil

  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled then
      local rpm = numberOr(turbines.getRPM(entry.p), 0)
      if lowest == nil or rpm < lowest then lowest = rpm end
    end
  end

  return lowest or 0
end

return M
