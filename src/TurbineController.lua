local utils = require("utils")
local turbines = require("turbines")

local M = {}

M.TARGET_RPM = 1800
M.RPM_DISENGAGE = 1700
M.RPM_REENGAGE = 1750

M.FLOW_STEP_FAR = 25
M.FLOW_STEP_MED = 10
M.FLOW_STEP_FINE = 5
M.FLOW_STEP_ULTRA = 1

M.CAL_STABLE_MIN = 1795
M.CAL_STABLE_MAX = 1805
M.CAL_STABLE_TICKS = 16
M.CAL_TIMEOUT_TICKS = 800

-- Adaptive calibration:
-- If a turbine runs stable near 1800 RPM for a while, AtomicControl slowly
-- learns the real flow needed for that turbine.
M.LEARN_MIN_RPM = 1798
M.LEARN_MAX_RPM = 1802
M.LEARN_REQUIRED_TICKS = 60
M.LEARN_CHANGE_THRESHOLD = 0.02
M.LEARN_ALPHA = 0.10

local function stepForRPM(rpm)
  local diff = math.abs((rpm or 0) - M.TARGET_RPM)

  if diff > 100 then return M.FLOW_STEP_FAR end
  if diff > 50 then return M.FLOW_STEP_MED end
  if diff > 25 then return M.FLOW_STEP_FINE end
  return M.FLOW_STEP_ULTRA
end

function M.getCalibration(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local value = cfg.turbineCalibrations[entry.name]

  if type(value) == "table" then
    return tonumber(value.flow)
  end

  return tonumber(value)
end

local function getIdleFlow(cfg, entry)
  if not cfg or not entry or not entry.name then return nil end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local value = cfg.turbineCalibrations[entry.name]

  if type(value) == "table" then
    if tonumber(value.idleFlow) then
      return tonumber(value.idleFlow)
    end

    if tonumber(value.flow) then
      return utils.clamp(math.floor(tonumber(value.flow) * 0.10), 25, 250)
    end
  end

  if tonumber(value) then
    return utils.clamp(math.floor(tonumber(value) * 0.10), 25, 250)
  end

  return nil
end

function M.setCalibration(cfg, entry, flow)
  if not cfg or not entry or not entry.name then return end
  cfg.turbineCalibrations = cfg.turbineCalibrations or {}

  local nominal = math.floor(flow or 0)

  cfg.turbineCalibrations[entry.name] = {
    flow = nominal,
    idleFlow = utils.clamp(math.floor(nominal * 0.10), 25, 250),
    rpm = M.TARGET_RPM,
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

  cfg.turbineCalibrations[entry.name] = {
    flow = rounded,
    idleFlow = utils.clamp(math.floor(rounded * 0.10), 25, 250),
    rpm = M.TARGET_RPM,
    learned = learned or oldTable.learned or false,
    calibratedAt = oldTable.calibratedAt or (os.epoch and os.epoch("utc") or os.clock()),
    updatedAt = os.epoch and os.epoch("utc") or os.clock()
  }
end

local function learnCalibration(state, cfg, entry, rpm, flow, storageFull)
  if storageFull or cfg.operationMode == "CYANITE" then
    entry.learnTicks = 0
    return
  end

  if not entry.enabled then
    entry.learnTicks = 0
    return
  end

  if not turbines.getInductor(entry.p) then
    entry.learnTicks = 0
    return
  end

  if rpm < M.LEARN_MIN_RPM or rpm > M.LEARN_MAX_RPM then
    entry.learnTicks = 0
    return
  end

  if flow <= 0 then
    entry.learnTicks = 0
    return
  end

  entry.learnTicks = (entry.learnTicks or 0) + 1

  if entry.learnTicks < M.LEARN_REQUIRED_TICKS then
    return
  end

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
  local rpm = turbines.getRPM(t)
  local flow = turbines.getFlow(t)
  local step = stepForRPM(rpm)

  entry.enabled = true
  turbines.setActive(t, true)

  if rpm < M.RPM_DISENGAGE then
    turbines.setInductor(t, false)
    turbines.setFlow(t, flow + math.max(step, M.FLOW_STEP_MED))
  elseif rpm < M.RPM_REENGAGE then
    turbines.setFlow(t, flow + step)
  else
    turbines.setInductor(t, true)

    if rpm < M.TARGET_RPM then
      turbines.setFlow(t, flow + step)
    elseif rpm > M.TARGET_RPM then
      turbines.setFlow(t, flow - step)
    end
  end

  if rpm >= M.CAL_STABLE_MIN and rpm <= M.CAL_STABLE_MAX then
    cal.stableTicks = cal.stableTicks + 1
  else
    cal.stableTicks = 0
  end

  cal.ticks = cal.ticks + 1

  if cal.stableTicks >= M.CAL_STABLE_TICKS then
    local finalFlow = turbines.getFlow(t)
    M.setCalibration(cfg, entry, finalFlow)
    state.configDirty = true
    state.calibration = nil
    state.statusLine = "T" .. tostring(cal.turbineIndex) .. " calibrated: " .. tostring(finalFlow) .. " mB/t"
    return true
  end

  if cal.ticks >= M.CAL_TIMEOUT_TICKS then
    local finalFlow = turbines.getFlow(t)

    if finalFlow > 0 then
      M.setCalibration(cfg, entry, finalFlow)
      state.configDirty = true
      state.statusLine = "T" .. tostring(cal.turbineIndex) .. " timeout saved: " .. tostring(finalFlow) .. " mB/t"
    else
      state.statusLine = "Calibration timeout"
    end

    state.calibration = nil
    return true
  end

  state.statusLine = "Cal T" .. tostring(cal.turbineIndex) .. ": " .. math.floor(rpm) .. " RPM / " .. math.floor(flow) .. " mB/t"
  return true
end

function M.update(state, cfg, storageFull)
  local needsSteam = false
  local cyanite = cfg.operationMode == "CYANITE"

  for _, entry in ipairs(state.turbines or {}) do
    local t = entry.p

    if not entry.enabled then
      turbines.setActive(t, false)
      turbines.setInductor(t, false)
      turbines.setFlow(t, 0)
      entry.learnTicks = 0
    else
      local rpm = turbines.getRPM(t)
      local flow = turbines.getFlow(t)
      local step = stepForRPM(rpm)
      local engaged = turbines.getInductor(t)
      local calibrated = M.getCalibration(cfg, entry)

      turbines.setActive(t, state.enabled)

      if storageFull and not cyanite then
        -- Storage full:
        -- Stop generation, but keep the rotor ready using a small idle flow.
        turbines.setInductor(t, false)

        local idle = getIdleFlow(cfg, entry) or 0

        if idle > 0 then
          if flow > idle then
            turbines.setFlow(t, flow - math.max(step, M.FLOW_STEP_MED))
          elseif flow < idle then
            turbines.setFlow(t, flow + M.FLOW_STEP_ULTRA)
          end
        else
          turbines.setFlow(t, 0)
        end

        entry.learnTicks = 0

      else
        -- If calibrated, quickly move toward the nominal baseline if we are far away.
        if calibrated and calibrated > 0 and math.abs(calibrated - flow) > 100 then
          if calibrated > flow then
            turbines.setFlow(t, flow + M.FLOW_STEP_FAR)
          else
            turbines.setFlow(t, flow - M.FLOW_STEP_FAR)
          end
        end

        if rpm < M.RPM_DISENGAGE then
          turbines.setInductor(t, false)
          turbines.setFlow(t, flow + math.max(step, M.FLOW_STEP_MED))
          needsSteam = true

        elseif rpm < M.RPM_REENGAGE then
          turbines.setInductor(t, engaged)
          turbines.setFlow(t, flow + step)
          needsSteam = true

        else
          turbines.setInductor(t, true)

          if rpm < M.TARGET_RPM then
            turbines.setFlow(t, flow + step)
            if rpm < M.TARGET_RPM - 10 then needsSteam = true end
          elseif rpm > M.TARGET_RPM then
            turbines.setFlow(t, flow - step)
          end
        end

        learnCalibration(state, cfg, entry, rpm, turbines.getFlow(t), storageFull)
      end
    end
  end

  return needsSteam
end

function M.lowestRPM(state)
  local lowest = nil

  for _, entry in ipairs(state.turbines or {}) do
    if entry.enabled then
      local rpm = turbines.getRPM(entry.p)

      if lowest == nil or rpm < lowest then
        lowest = rpm
      end
    end
  end

  return lowest or 0
end

return M
